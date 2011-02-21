package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';


sub _prepare_biblio_search_basics {
    my ($cgi) = @_;

    my %parts;
    my @part_names = qw/class contains query/;
    $parts{$_} = [ $cgi->param($_) ] for (@part_names);

    my @chunks = ();
    for (my $i = 0; $i < scalar @{$parts{'class'}}; $i++) {
        my ($class, $contains, $query) = map { $parts{$_}->[$i] } @part_names;

        push(@chunks, $class . ':') unless $class eq 'keyword' and $i == 0;

        # This stuff probably will need refined or rethought to better handle
        # the weird things Real Users will surely type in.
        if ($contains eq 'nocontains') {
            $query =~ s/"//g;
            $query = ('"' . $query . '"') if index $query, ' ';
            $query = '-' . $query;
        } elsif ($contains eq 'exact') {
            $query =~ s/"//g;
            $query = ('"' . $query . '"') if index $query, ' ';
        }
        push @chunks, $query;
    }

    return join(' ', @chunks);
}

sub _prepare_biblio_search {
    my ($cgi, $ctx) = @_;

    my $query = _prepare_biblio_search_basics($cgi);
    my $args = {};

    $args->{'org_unit'} = $cgi->param('loc') || $ctx->{aou_tree}->()->id;
    $args->{'depth'} = defined $cgi->param('depth') ?
        $cgi->param('depth') :
        $ctx->{find_aou}->($args->{'org_unit'})->ou_type->depth;

    if ($cgi->param('available')) {
        $query = '#available ' . $query;
    }

    if ($cgi->param('format')) {
        $args->{'format'} = join('', $cgi->param('format'));
    }

    if ($cgi->param('lang')) {
        # XXX TODO find out how to build query with multiple langs, if that
        # even needs to be a feature of adv search.
        $query .= ' lang:' . $cgi->param('lang');
    }

    if ($cgi->param('audience')) {
        $query .= ' audience(' . $cgi->param('audience') . ')';
    }

    if (defined $cgi->param('sort')) {
        my $sort = $cgi->param('sort');
        my $sort_order = $cgi->param('sort_order');
        $query .= " sort($sort)";
        $query .= '#' . $sort_order if $sort_order and $sort ne 'rel';
    }

    if ($cgi->param('pubyear_how') && $cgi->param('pubyear1')) {
        if ($cgi->param('pubyear_how') eq 'between') {
            $query .= ' between(' . $cgi->param('pubyear1');
            $query .= ',' .  $cgi->param('pubyear2') if $cgi->param('pubyear2');
            $query .= ')';
        } else {
            $query .= ' ' . $cgi->param('pubyear_how') .
                '(' . $cgi->param('pubyear1') . ')';
        }
    }

    return ($args, $query);
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
    my $limit = $cgi->param('limit') || 10; # TODO user settings

    my ($args, $query) = _prepare_biblio_search($cgi, $ctx);

    # Stuff these into the TT context so that templates can use them in redrawing forms
    $ctx->{processed_search_query} = $query;
    $ctx->{processed_search_args} = $args;

    $args->{'limit'} = $limit;
    $args->{'offset'} = $page * $limit;

    $query = "$query $facet" if $facet; # TODO

    my $results;

    try {

        my $method = 'open-ils.search.biblio.multiclass.query';
        $method .= '.staff' if $ctx->{is_staff};
        $results = $U->simplereq('open-ils.search', $method, $args, $query, 1);

    } catch Error with {
        my $err = shift;
        $logger->error("multiclass search error: $err");
        $results = {count => 0, ids => []};
    };

    my $rec_ids = [map { $_->[0] } @{$results->{ids}}];

    $ctx->{records} = [];
    $ctx->{search_facets} = {};
    $ctx->{page_size} = $limit;
    $ctx->{hit_count} = $results->{count};

    return Apache2::Const::OK if @$rec_ids == 0;

    my $cstore1 = OpenSRF::AppSession->create('open-ils.cstore');
    my $bre_req = $cstore1->request(
        'open-ils.cstore.direct.biblio.record_entry.search', {id => $rec_ids});

    my $search = OpenSRF::AppSession->create('open-ils.search');
    my $facet_req = $search->request('open-ils.search.facet_cache.retrieve', $results->{facet_key}, 10);

    my @data;
    while(my $resp = $bre_req->recv) {
        my $bre = $resp->content; 

        # XXX farm out to multiple cstore sessions before loop, then collect after
        my $copy_counts = $e->json_query(
            {from => ['asset.record_copy_count', 1, $bre->id, 0]})->[0];

        push(@data,
            {
                bre => $bre,
                marc_xml => XML::LibXML->new->parse_string($bre->marc),
                copy_counts => $copy_counts
            }
        );
    }

    $cstore1->kill_me;

    # shove recs into context in search results order
    for my $rec_id (@$rec_ids) { 
        push(
            @{$ctx->{records}},
            grep { $_->{bre}->id == $rec_id } @data
        );
    }

    my $facets = $facet_req->gather(1);

    $facets->{$_} = {cmf => $ctx->{find_cmf}->($_), data => $facets->{$_}} for keys %$facets;  # quick-n-dirty
    $ctx->{search_facets} = $facets;

    return Apache2::Const::OK;
}

1;
