package OpenILS::Application::Search::Browse;
use base qw/OpenILS::Application/;
use strict; use warnings;

# Most of this code is copied directly from ../../WWW/EGCatLoader/Browse.pm
# and modified to be API-compatible.

use Digest::MD5 qw/md5_hex/;
use Apache2::Const -compile => qw/OK/;
use MARC::Record;
use List::Util qw/first/;

use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::Normalize qw/search_normalize/;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::SettingsClient;

my $U = 'OpenILS::Application::AppUtils';
my $browse_cache;
my $browse_timeout;

sub initialize { return 1; }

sub child_init {
    if (not defined $browse_cache) {
        my $conf = new OpenSRF::Utils::SettingsClient;

        $browse_timeout = $conf->config_value(
            "apps", "open-ils.search", "app_settings", "cache_timeout"
        ) || 300;
        $browse_cache = new OpenSRF::Utils::Cache("global");
    }
}

__PACKAGE__->register_method(
    method      => "browse",
    api_name    => "open-ils.search.browse.staff",
    stream      => 1,
    signature   => {
        desc    => q/Bib + authority browse/,
        params  => [{
            params => {
                name => 'Browse Parameters',
                desc => q/Hash of arguments:
                    browse_class
                        -- title, author, subject, series
                    term
                        -- term to browse for
                    org_unit
                        -- context org unit ID
                    copy_location_group
                        -- copy location filter ID
                    limit
                        -- return this many results
                    pivot
                        -- browse entry ID
                /
            }
        }]
    }
);

__PACKAGE__->register_method(
    method      => "browse",
    api_name    => "open-ils.search.browse",
    stream      => 1,
    signature   => {
        desc    => q/See open-ils.search.browse.staff/
    }
);

sub browse {
    my ($self, $client, $params) = @_;

    $params->{staff} = 1 if $self->api_name =~ /staff/;
    my ($cache_key, @params) = prepare_browse_parameters($params);

    my $results = $browse_cache->get_cache($cache_key);

    if (!$results) {
        $results = 
            new_editor()->json_query({from => ['metabib.browse', @params]});
        if ($results) {
            $browse_cache->put_cache($cache_key, $results, $browse_timeout);
        }
    }

    my ($warning, $alternative) = 
        leading_article_test($params->{browse_class}, $params->{term});

    for my $result (@$results) {
        $result->{leading_article_warning} = $warning;
        $result->{leading_article_alternative} = $alternative;
        flesh_browse_results([$result]);
        $client->respond($result);
    }

    return undef;
}


# Returns cache key and a list of parameters for DB proc metabib.browse().
sub prepare_browse_parameters {
    my ($params) = @_;

    no warnings 'uninitialized';

    my @params = (
        $params->{browse_class},
        $params->{term},
        $params->{org_unit},
        $params->{copy_location_group},
        $params->{staff} ? 't' : 'f',
        $params->{pivot},
        $params->{limit} || 10
    );

    return (
        "oils_browse_" . md5_hex(OpenSRF::Utils::JSON->perl2JSON(\@params)),
        @params
    );
}

sub leading_article_test {
    my ($browse_class, $bterm) = @_;

    my $flag_name = "opac.browse.warnable_regexp_per_class";
    my $flag = new_editor()->retrieve_config_global_flag($flag_name);

    return unless $flag->enabled eq 't';

    my $map;
    my $warning;
    my $alternative;

    eval { $map = OpenSRF::Utils::JSON->JSON2perl($flag->value); };
    if ($@) {
        $logger->warn("cgf '$flag_name' enabled but value is invalid JSON? $@");
        return;
    }

    # Don't crash over any of the things that could go wrong in here:
    eval {
        if ($map->{$browse_class}) {
            if ($bterm =~ qr/$map->{$browse_class}/i) {
                $warning = 1;
                ($alternative = $bterm) =~ s/$map->{$browse_class}//;
            }
        }
    };

    if ($@) {
        $logger->warn("cgf '$flag_name' has valid JSON in value, but: $@");
    }

    return ($warning, $alternative);
}

# flesh_browse_results() attaches data from authority records. It
# changes $results and returns 1 for success, undef for failure
# $results must be an arrayref of result rows from the DB's metabib.browse()
sub flesh_browse_results {
    my ($results) = @_;

    for my $authority_field_name ( qw/authorities sees/ ) {
        for my $r (@$results) {
            # Turn comma-seprated strings of numbers in "authorities" and "sees"
            # columns into arrays.
            if ($r->{$authority_field_name}) {
                $r->{$authority_field_name} = [split /,/, $r->{$authority_field_name}];
            } else {
                $r->{$authority_field_name} = [];
            }
            $r->{"list_$authority_field_name"} = [ @{$r->{$authority_field_name} } ];
        }

        # Group them in one arrray, not worrying about dupes because we're about
        # to use them in an IN () comparison in a SQL query.
        my @auth_ids = map { @{$_->{$authority_field_name}} } @$results;

        if (@auth_ids) {
            # Get all linked authority records themselves
            my $linked = new_editor()->json_query({
                select => {
                    are => [qw/id marc control_set/],
                    aalink => [{column => "target", transform => "array_agg",
                        aggregate => 1}]
                },
                from => {
                    are => {
                        aalink => {
                            type => "left",
                            fkey => "id", field => "source"
                        }
                    }
                },
                where => {"+are" => {id => \@auth_ids}}
            }) or return;

            map_authority_headings_to_results(
                $linked, $results, \@auth_ids, $authority_field_name);
        }
    }

    return 1;
}

sub map_authority_headings_to_results {
    my ($linked, $results, $auth_ids, $authority_field_name) = @_;

    # Use the linked authority records' control sets to find and pick
    # out non-main-entry headings. Build the headings and make a
    # combined data structure for the template's use.
    my %linked_headings_by_auth_id = map {
        $_->{id} => find_authority_headings_and_notes($_)
    } @$linked;

    # Avoid sending the full MARC blobs to the caller.
    delete $_->{marc} for @$linked;

    # Graft this authority heading data onto our main result set at the
    # named column, either "authorities" or "sees".
    foreach my $row (@$results) {
        $row->{$authority_field_name} = [
            map { $linked_headings_by_auth_id{$_} } @{$row->{$authority_field_name}}
        ];
    }

    # Get linked-bib counts for each of those authorities, and put THAT
    # information into place in the data structure.
    my $counts = new_editor()->json_query({
        select => {
            abl => [
                {column => "id", transform => "count",
                    alias => "count", aggregate => 1},
                "authority"
            ]
        },
        from => {abl => {}},
        where => {
            "+abl" => {
                authority => [
                    @$auth_ids,
                    $U->unique_unnested_numbers(map { $_->{target} } @$linked)
                ]
            }
        }
    }) or return;

    my %auth_counts = map { $_->{authority} => $_->{count} } @$counts;

    # Soooo nesty!  We look for places where we'll need a count of bibs
    # linked to an authority record, and put it there for the template to find.
    for my $row (@$results) {
        for my $auth (@{$row->{$authority_field_name}}) {
            if ($auth->{headings}) {
                for my $outer_heading (@{$auth->{headings}}) {
                    for my $heading_blob (@{(values %$outer_heading)[0]}) {
                        if ($heading_blob->{target}) {
                            $heading_blob->{target_count} =
                                $auth_counts{$heading_blob->{target}};
                        }
                    }
                }
            }
        }
    }
}


# TOOD consider locale-aware caching
sub get_acsaf {
    my $control_set = shift;

    my $acs = new_editor()
        ->search_authority_control_set_authority_field(
            {control_set => $control_set}
        );

    return {  map { $_->id => $_ } @$acs };
}

sub find_authority_headings_and_notes {
    my ($row) = @_;

    my $acsaf_table = get_acsaf($row->{control_set});

    $row->{headings} = [];

    my $record;
    eval {
        $record = new_from_xml MARC::Record($row->{marc});
    };

    if ($@) {
        $logger->warn("Problem with MARC from authority record #" .
            $row->{id} . ": $@");
        return $row;    # We're called in map(), so we must move on without
                        # a fuss.
    }

    extract_public_general_notes($record, $row);

    # extract headings from the main authority record along with their
    # types
    my $parsed_headings = new_editor()->json_query({
        from => ['authority.extract_headings', $row->{marc}]
    });
    my %heading_type_map = ();
    if ($parsed_headings) {
        foreach my $h (@$parsed_headings) {
            $heading_type_map{$h->{normalized_heading}} =
                $h->{purpose} eq 'variant' ? 'variant' :
                $h->{purpose} eq 'related' ? $h->{related_type} :
                '';
        }
    }

    # By applying grep in this way, we get acsaf objects that *have* and
    # therefore *aren't* main entries, which is what we want.
    foreach my $acsaf (values(%$acsaf_table)) {
        my @fields = $record->field($acsaf->tag);
        my %sf_lookup = map { $_ => 1 } split("", $acsaf->display_sf_list);
        my @headings;

        foreach my $field (@fields) {
            my $h = { main_entry => ( $acsaf->main_entry ? 0 : 1 ),
                      heading => get_authority_heading($field, \%sf_lookup, $acsaf->joiner) };

            my $norm = search_normalize($h->{heading});
            if (exists $heading_type_map{$norm}) {
                $h->{type} = $heading_type_map{$norm};
            }
            # XXX I was getting "target" from authority.authority_linking, but
            # that makes no sense: that table can only tell you that one
            # authority record as a whole points at another record.  It does
            # not record when a specific *field* in one authority record
            # points to another record (not that it makes much sense for
            # one authority record to have links to multiple others, but I can't
            # say there definitely aren't cases for that).
            $h->{target} = $2
                if ($field->subfield('0') || "") =~ /(^|\))(\d+)$/;

            # The target is the row id if this is a main entry...
            $h->{target} = $row->{id} if $h->{main_entry};

            push @headings, $h;
        }

        push @{$row->{headings}}, {$acsaf->id => \@headings} if @headings;
    }

    return $row;
}


# Break out any Public General Notes (field 680) for display. These are
# sometimes (erroneously?) called "scope notes." I say erroneously,
# tentatively, because LoC doesn't seem to document a "scope notes"
# field for authority records, while it does so for classification
# records, which are something else. But I am not a librarian.
sub extract_public_general_notes {
    my ($record, $row) = @_;

    # Make a list of strings, each string being a concatentation of any
    # subfields 'i', '5', or 'a' from one field 680, in order of appearance.
    $row->{notes} = [
        map {
            join(
                " ",
                map { $_->[1] } grep { $_->[0] =~ /[i5a]/ } $_->subfields
            )
        } $record->field('680')
    ];
}

sub get_authority_heading {
    my ($field, $sf_lookup, $joiner) = @_;

    $joiner ||= ' ';

    return join(
        $joiner,
        map { $_->[1] } grep { $sf_lookup->{$_->[0]} } $field->subfields
    );
}

1;
