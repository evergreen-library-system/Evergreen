package OpenILS::WWW::EGCatLoader;

use strict;
use warnings;

use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::Normalize qw/search_normalize/;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Cache;
use OpenSRF::Utils::SettingsClient;

use Digest::MD5 qw/md5_hex/;
use Apache2::Const -compile => qw/OK/;
use MARC::Record;
use List::Util qw/first/;
#use Data::Dumper;
#$Data::Dumper::Indent = 0;

my $U = 'OpenILS::Application::AppUtils';
my $browse_cache;
my $browse_timeout;

# Plain procedural functions start here.
#
sub _init_browse_cache {
    if (not defined $browse_cache) {
        my $conf = new OpenSRF::Utils::SettingsClient;

        $browse_timeout = $conf->config_value(
            "apps", "open-ils.search", "app_settings", "cache_timeout"
        ) || 300;
        $browse_cache = new OpenSRF::Utils::Cache("global");
    }
}

sub _get_authority_heading {
    my ($field, $sf_lookup, $joiner) = @_;

    $joiner ||= ' ';

    return join(
        $joiner,
        map { $_->[1] } grep { $sf_lookup->{$_->[0]} } $field->subfields
    );
}

# Object methods start here.
#

# Returns cache key and a list of parameters for DB proc metabib.browse().
sub prepare_browse_parameters {
    my ($self) = @_;

    no warnings 'uninitialized';

    # XXX TODO add config.global_flag rows for browse limit-limit ?

    my @params = (
        scalar($self->cgi->param('qtype')),
        scalar($self->cgi->param('bterm')),
        $self->ctx->{copy_location_group_org} ||
            $self->ctx->{aou_tree}->()->id,
        $self->ctx->{copy_location_group},
        $self->ctx->{is_staff} ? 't' : 'f',
        scalar($self->cgi->param('bpivot')),
        int(
            $self->cgi->param('blimit') ||
            $self->ctx->{opac_hits_per_page} || 10
        )
    );

    return (
        "oils_browse_" . md5_hex(OpenSRF::Utils::JSON->perl2JSON(\@params)),
        @params
    );
}

# Break out any Public General Notes (field 680) for display. These are
# sometimes (erroneously?) called "scope notes." I say erroneously,
# tentatively, because LoC doesn't seem to document a "scope notes"
# field for authority records, while it does so for classification
# records, which are something else. But I am not a librarian.
sub extract_public_general_notes {
    my ($self, $record, $row) = @_;

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

sub find_authority_headings_and_notes {
    my ($self, $row) = @_;

    my $acsaf_table =
        $self->ctx->{get_authority_fields}->($row->{control_set});

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

    $self->extract_public_general_notes($record, $row);

    # By applying grep in this way, we get acsaf objects that *have* and
    # therefore *aren't* main entries, which is what we want.
    foreach my $acsaf (values(%$acsaf_table)) {
        my @fields = $record->field($acsaf->tag);
        my %sf_lookup = map { $_ => 1 } split("", $acsaf->display_sf_list);
        my @headings;

        foreach my $field (@fields) {
            my $h = { main_entry => ( $acsaf->main_entry ? 0 : 1 ),
                      heading => _get_authority_heading($field, \%sf_lookup), $acsaf->joiner };

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

sub map_authority_headings_to_results {
    my ($self, $linked, $results, $auth_ids, $authority_field_name) = @_;

    # Use the linked authority records' control sets to find and pick
    # out non-main-entry headings. Build the headings and make a
    # combined data structure for the template's use.
    my %linked_headings_by_auth_id = map {
        $_->{id} => $self->find_authority_headings_and_notes($_)
    } @$linked;

    # Graft this authority heading data onto our main result set at the
    # named column, either "authorities" or "sees".
    foreach my $row (@$results) {
        $row->{$authority_field_name} = [
            map { $linked_headings_by_auth_id{$_} } @{$row->{$authority_field_name}}
        ];
    }

    # Get linked-bib counts for each of those authorities, and put THAT
    # information into place in the data structure.
    my $counts = $self->editor->json_query({
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

# flesh_browse_results() attaches data from authority records. It
# changes $results and returns 1 for success, undef for failure (in which
# case $self->editor->event should always point to the reason for failure).
# $results must be an arrayref of result rows from the DB's metabib.browse()
sub flesh_browse_results {
    my ($self, $results) = @_;

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
            my $linked = $self->editor->json_query({
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

            $self->map_authority_headings_to_results($linked, $results, \@auth_ids, $authority_field_name);
        }
    }

    return 1;
}

sub load_browse_impl {
    my ($self, @params) = @_;

    my $results = $self->editor->json_query({
        from => [ "metabib.browse", @params ]
    });

    if (not $results) {  # DB error, not empty result set.
        $logger->warn(
            "error in browse (direct): " . $self->editor->event->{textcode}
        );
        $self->ctx->{browse_error} = 1;

        return;
    } elsif (not $self->flesh_browse_results($results)) {
        $logger->warn(
            "error in browse (flesh): " . $self->editor->event->{textcode}
        );
        $self->ctx->{browse_error} = 1;

        return;
    }

    return $results;
}

# Find paging information, put it into $self->ctx, and return "real"
# rows from $results, excluding those that contain only paging
# information.
sub infer_browse_paging {
    my ($self, $results) = @_;

    foreach (@$results) {
        if ($_->{pivot_point}) {
            if ($_->{row_number} < 0) { # sic
                $self->ctx->{forward_pivot} = $_->{pivot_point};
            } else {
                $self->ctx->{back_pivot} = $_->{pivot_point};
            }
        }
    }

    return [ grep { not defined $_->{pivot_point} } @$results ];
}

sub leading_article_test {
    my ($self, $qtype, $bterm) = @_;

    my $flag_name = "opac.browse.warnable_regexp_per_class";
    my $flag = $self->ctx->{get_cgf}->($flag_name);

    return unless $flag->enabled eq 't';

    my $map;

    eval { $map = OpenSRF::Utils::JSON->JSON2perl($flag->value); };
    if ($@) {
        $logger->warn("cgf '$flag_name' enabled but value is invalid JSON? $@");
        return;
    }

    # Don't crash over any of the things that could go wrong in here:
    eval {
        if ($map->{$qtype}) {
            if ($bterm =~ qr/$map->{$qtype}/i) {
                $self->ctx->{browse_leading_article_warning} = 1;
                ($self->ctx->{browse_leading_article_alternative} = $bterm) =~
                    s/$map->{$qtype}//;
            }
        }
    };
    if ($@) {
        $logger->warn("cgf '$flag_name' has valid JSON in value, but: $@");
    }
}

sub load_browse {
    my ($self) = @_;

    _init_browse_cache();

    # If there's a user logged in, flesh extended user info so we can get
    # her opac.hits_per_page setting, if any.
    if ($self->ctx->{user}) {
        $self->prepare_extended_user_info('settings');
        if (my $setting = first { $_->name eq 'opac.hits_per_page' }
            @{$self->ctx->{user}->settings}) {

            $self->ctx->{opac_hits_per_page} =
                int(OpenSRF::Utils::JSON->JSON2perl($setting->value));
        }
    }

    my $pager_shortcuts = $self->ctx->{get_org_setting}->(
        $self->ctx->{physical_loc} || $self->ctx->{search_ou} ||
            $self->ctx->{aou_tree}->id, 'opac.browse.pager_shortcuts'
    );
    if ($pager_shortcuts) {
        my @pager_shortcuts;
        while ($pager_shortcuts =~ s/(\*(.+?)\*)//) {
            push @pager_shortcuts, [substr($2, 0, 1), $2];
        }
        push @pager_shortcuts, map { [$_, $_] } split //, $pager_shortcuts;
        $self->ctx->{pager_shortcuts} = \@pager_shortcuts;
    }

    if ($self->cgi->param('qtype') and defined $self->cgi->param('bterm')) {

        $self->leading_article_test(
            $self->cgi->param('qtype'),
            $self->cgi->param('bterm')
        );

        my ($cache_key, @params) = $self->prepare_browse_parameters;

        my $results = $browse_cache->get_cache($cache_key);
        if (not $results) {
            $results = $self->load_browse_impl(@params);
            if ($results) {
                $browse_cache->put_cache($cache_key, $results, $browse_timeout);
            }
        }

        if ($results) {
            $self->ctx->{browse_results} = $self->infer_browse_paging($results);
        }

        # We don't need an else clause to send the user a 5XX error or
        # anything. Errors will have been logged, and $ctx will be
        # prepared so a template can show a nicer error to the user.
    }

    return Apache2::Const::OK;
}

1;
