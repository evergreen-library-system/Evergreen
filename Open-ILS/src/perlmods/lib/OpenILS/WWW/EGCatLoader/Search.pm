package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::JSON;
my $U = 'OpenILS::Application::AppUtils';


sub _prepare_biblio_search_basics {
    my ($cgi) = @_;

    return $cgi->param('query') unless $cgi->param('qtype');

    my %parts;
    my @part_names = qw/qtype contains query/;
    $parts{$_} = [ $cgi->param($_) ] for (@part_names);

    my @chunks = ();
    for (my $i = 0; $i < scalar @{$parts{'qtype'}}; $i++) {
        my ($qtype, $contains, $query) = map { $parts{$_}->[$i] } @part_names;

        next unless $query =~ /\S/;
        push(@chunks, $qtype . ':') unless $qtype eq 'keyword' and $i == 0;

        # This stuff probably will need refined or rethought to better handle
        # the weird things Real Users will surely type in.
        $contains = "" unless defined $contains; # silence warning
        if ($contains eq 'nocontains') {
            $query =~ s/"//g;
            $query = ('"' . $query . '"') if index $query, ' ';
            $query = '-' . $query;
        } elsif ($contains eq 'phrase') {
            $query =~ s/"//g;
            $query = ('"' . $query . '"') if index $query, ' ';
        } elsif ($contains eq 'exact') {
            $query =~ s/[\^\$]//g;
            $query = '^' . $query . '$';
        }
        push @chunks, $query;
    }

    return join(' ', @chunks);
}

sub _prepare_biblio_search {
    my ($cgi, $ctx) = @_;

    my $query = _prepare_biblio_search_basics($cgi) || '';

    $query = ('#' . $_ . ' ' . $query) foreach ($cgi->param('modifier'));

    # filters
    foreach (grep /^fi:/, $cgi->param) {
        /:(-?\w+)$/ or next;
        my $term = join(",", $cgi->param($_));
        $query .= " $1($term)" if length $term;
    }

    if ($cgi->param('sort')) {
        my ($axis, $desc) = split /\./, $cgi->param('sort');
        $query .= " sort($axis)";
        $query .= '#descending' if $desc;
    }

    if ($cgi->param('pubdate') && $cgi->param('date1')) {
        if ($cgi->param('pubdate') eq 'between') {
            $query .= ' between(' . $cgi->param('date1');
            $query .= ',' .  $cgi->param('date2') if $cgi->param('date2');
            $query .= ')';
        } elsif ($cgi->param('pubdate') eq 'is') {
            $query .= ' between(' . $cgi->param('date1') .
                ',' .  $cgi->param('date1') . ')';  # sic, date1 twice
        } else {
            $query .= ' ' . $cgi->param('pubdate') .
                '(' . $cgi->param('date1') . ')';
        }
    }

    my $site;
    my $org = $cgi->param('loc');
    if (defined($org) and $org ne '' and ($org ne $ctx->{aou_tree}->()->id) and not $query =~ /site\(\S+\)/) {
        $site = $ctx->{get_aou}->($org)->shortname;
        $query .= " site($site)";
    }

    if(!$site) {
        ($site) = ($query =~ /site\(([^\)]+)\)/);
        $site ||= $ctx->{aou_tree}->()->shortname;
    }


    my $depth;
    if (defined($cgi->param('depth')) and not $query =~ /depth\(\d+\)/) {
        $depth = defined $cgi->param('depth') ?
            $cgi->param('depth') : $ctx->{get_aou}->($site)->ou_type->depth;
        $query .= " depth($depth)";
    }

    return ($query, $site, $depth);
}

sub _get_search_limit {
    my $self = shift;

    # param takes precedence
    my $limit = $self->cgi->param('limit');
    return $limit if $limit;

    if($self->editor->requestor) {
        # See if the user has a hit count preference
        my $lset = $self->editor->search_actor_user_setting({
            usr => $self->editor->requestor->id, 
            name => 'opac.hits_per_page'
        })->[0];
        return OpenSRF::Utils::JSON->JSON2perl($lset->value) if $lset;
    }

    return 10; # default
}

# context additions: 
#   page_size
#   hit_count
#   records : list of bre's and copy-count objects
sub load_rresults {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;
    my $e = $self->editor;

    $ctx->{page} = 'rresult';
    my $page = $cgi->param('page') || 0;
    my $facet = $cgi->param('facet');
    my $limit = $self->_get_search_limit;
    my $loc = $cgi->param('loc') || $ctx->{aou_tree}->()->id;
    my $offset = $page * $limit;
    my $metarecord = $cgi->param('metarecord');
    my $results; 

    my ($query, $site, $depth) = _prepare_biblio_search($cgi, $ctx);

    if ($metarecord) {

        # TODO: other limits, like SVF/format, etc.
        $results = $U->simplereq(
            'open-ils.search', 
            'open-ils.search.biblio.metarecord_to_records',
            $metarecord, {org => $loc, depth => $depth}
        );

        # force the metarecord result blob to match the format of regular search results
        $results->{ids} = [map { [$_] } @{$results->{ids}}]; 

    } else {

        return $self->generic_redirect unless $query;

        # Limit and offset will stay here. Everything else should be part of
        # the query string, not special args.
        my $args = {'limit' => $limit, 'offset' => $offset};

        # Stuff these into the TT context so that templates can use them in redrawing forms
        $ctx->{processed_search_query} = $query;

        $query = "$query $facet" if $facet; # TODO

        $logger->activity("EGWeb: [search] $query");

        try {

            my $method = 'open-ils.search.biblio.multiclass.query';
            $method .= '.staff' if $ctx->{is_staff};
            $results = $U->simplereq('open-ils.search', $method, $args, $query, 1);

        } catch Error with {
            my $err = shift;
            $logger->error("multiclass search error: $err");
            $results = {count => 0, ids => []};
        };
    }

    my $rec_ids = [map { $_->[0] } @{$results->{ids}}];

    $ctx->{records} = [];
    $ctx->{search_facets} = {};
    $ctx->{page_size} = $limit;
    $ctx->{hit_count} = $results->{count};

    return Apache2::Const::OK if @$rec_ids == 0;

    my ($facets, @data) = $self->get_records_and_facets(
        $rec_ids, $results->{facet_key}, 
        {
            flesh => '{holdings_xml,mra}',
            site => $site,
            depth => $depth
        }
    );

    # shove recs into context in search results order
    for my $rec_id (@$rec_ids) {
        push(
            @{$ctx->{records}},
            grep { $_->{id} == $rec_id } @data
        );
    }

    $ctx->{search_facets} = $facets;

    return Apache2::Const::OK;
}

1;
