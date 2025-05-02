package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::Cache;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::JSON;
use Data::Dumper;
$Data::Dumper::Indent = 0;
my $U = 'OpenILS::Application::AppUtils';

my @_qtype_list;

sub _prepare_biblio_search_basics {
    my ($cgi) = @_;

    return scalar($cgi->param('query')) unless scalar($cgi->param('qtype'));

    # fetch, once per mod_perl backend, the list of valid classes and aliases
    unless (@_qtype_list) {
        my $editor = new_editor();
        my $classes = $editor->retrieve_all_config_metabib_class();
        my $aliases = $editor->retrieve_all_config_metabib_search_alias();

        push @_qtype_list, map { $_->name } @$classes;
        push @_qtype_list, map { $_->alias } @$aliases;
    }

    my %parts;
    my @part_names = qw/qtype contains query bool/;
    $parts{$_} = [ $cgi->param($_) ] for (@part_names);

    my $full_query = '';
    my @bookplate_queries = ();
    for (my $i = 0; $i < scalar @{$parts{'qtype'}}; $i++) {
        my ($qtype, $contains, $query, $bool) = map { $parts{$_}->[$i] } @part_names;

        next unless $query =~ /\S/;

        # Hack for bookplates; "bookplate" is not a real search
        # class, so grabbing them out of the advanced search query
        # params to convert to a copy_tag(*,...) filter later
        if ($qtype eq 'bookplate') {
            $query =~ s/[)(]/ /g; # don't break on 'foo(bar)baz'
            push @bookplate_queries, $query;
            next;
        }
 
        # Hack for journal title
        my $jtitle = 0;
        if ($qtype eq 'jtitle') {
            $qtype = 'title';
            $jtitle = 1;
        }

        # This restricts qtype to classes, aliases, and field lists (approximately)
        next unless grep { $qtype =~ /^$_(?:\|\w+)*$/ } @_qtype_list;

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
        } elsif ($contains eq 'starts') {
            $query =~ s/"//g;
            $query =~ s/[\^\$]//g;
            $query = '^' . $query;
            $query = ('"' . $query . '"') if index $query, ' ';
        }

        # Journal title hackery complete
        if ($jtitle) {
            $query = "bib_level(s) $query";
        }

        $query = "$qtype:$query" unless ($query =~ /^$qtype:/ or ($qtype eq 'keyword' and $i == 0));

        $bool = ($bool and $bool eq 'or') ? '||' : '&&';
        $full_query = $full_query ? "($full_query $bool $query)" : $query;
    }

    return $full_query, \@bookplate_queries;
}

sub _prepare_biblio_search {
    my ($cgi, $ctx) = @_;

    # XXX This will still contain the jtitle hack...
    my ($user_query, $bookplate_queries) = _prepare_biblio_search_basics($cgi);
    $user_query //= '';
    $bookplate_queries //= [];
    my $query = $user_query;
    if (@$bookplate_queries) {
        $query .= " " . join(" ", map { "copy_tag(*,$_)" } @$bookplate_queries);
        # hack to handle the case where a bookplate comes from the
        # simple search box
        $user_query = $bookplate_queries->[0] if $user_query eq '';
    }

    $query .= ' ' . $ctx->{global_search_filter} if $ctx->{global_search_filter};

    foreach ($cgi->multi_param('modifier')) {
        # The unless bit is to avoid stacking modifiers.
        $query = ('#' . $_ . ' ' . $query) unless 
            $query =~ qr/\#\Q$_/ or $_ eq 'metabib';
    }

    # filters
    foreach (grep /^fi:/, $cgi->multi_param) {
        /:(-?\w+)$/ or next;
        my $term = join(",", $cgi->multi_param($_));
        $query .= " $1($term)" if length $term;
    }

    # filter group entries.  Entries from like filters are grouped into a single 
    # filter_group_entry() filter (ORed).  Each collection is ANDed together.
    # fg:foo_group=foo_entry_id
    foreach (grep /^fg:/, $cgi->multi_param) {
        /:(-?\w+)$/ or next;
        my $term = join(",", $cgi->multi_param($_));
        $query = "filter_group_entry($term) $query" if length $term;
    }

    if ($cgi->param("bookbag")) {
        $query = "container(bre,bookbag," . int($cgi->param("bookbag")) . ") $query";
    }

    if ($cgi->param('pubdate') && $cgi->param('date1')) {
        if ($cgi->param('pubdate') eq 'between') {
            my $btw = 'between(' . $cgi->param('date1');
            $btw .= ',' .  $cgi->param('date2') if $cgi->param('date2');
            $btw .= ')';
            $query = "$btw $query";
        } elsif ($cgi->param('pubdate') eq 'is') {
            $query = 'date1(' . $cgi->param('date1') . ") $query";
        } else {
            $query = $cgi->param('pubdate') .
                '(' . $cgi->param('date1') . ") $query";
        }
    }

    # ---------------------------------------------------------------------
    # Nothing below here constitutes a query by itself.  If the query value 
    # is still empty up to this point, there is no query.  abandon ship.
    return () unless $query;

    # The search_scope param comes from a mixed-use dropdown containing depth,
    # lasso, and location_groups filters.
    $query .= ' ' . $cgi->param('search_scope') if defined $cgi->param('search_scope');

    # The search_lasso context param comes from the locg dropdown, like the copy location.
    $query .= ' lasso(' . $ctx->{search_lasso} .')' if $ctx->{search_lasso};

    # sort is treated specially, even though it's actually a filter
    if (defined($cgi->param('sort'))) {
        $query =~ s/sort\([^\)]*\)//g;  # override existing sort(). no stacking.
        my ($axis, $desc) = split /\./, $cgi->param('sort');
        $query = "sort($axis) $query" if $axis;
        if ($desc and not $query =~ /\#descending/) {
            $query = "#descending $query";
        } elsif (not $desc) {
            $query =~ s/\#descending//;
        }
        # tidy up
        $query =~ s/^\s+//;
        $query =~ s/\s+$//;
    }

    my (@naive_query_re, $site);

    my $org = $ctx->{search_ou};
    if (defined($org) and $org ne '' and ($org ne $ctx->{aou_tree}->()->id) and not $query =~ /site\(\S+\)/) {
        my $thing = " site(" . $ctx->{get_aou}->($org)->shortname . ")";

        $query .= $thing;
        push @naive_query_re, $thing;
    }

    my $pref_ou = $ctx->{pref_ou};
    if (defined($pref_ou) and $pref_ou ne '' and $pref_ou != $org and ($pref_ou ne $ctx->{aou_tree}->()->id) and not $query =~ / pref_ou\(\S+\)/) {
        my $plib = $ctx->{get_aou}->($pref_ou)->shortname;
        $query = "pref_ou($plib) $query";
    }

    if (my $grp = $ctx->{copy_location_group}) {
        $query = "location_groups($grp) $query";
    }

    if(!$site) {
        ($site) = ($query =~ /site\(([^\)]+)\)/);
        $site ||= $ctx->{aou_tree}->()->shortname;
    }

    # Course on_reserves filter, handles specially since the UI includes
    # an option to negate the filter, and it relies on the org unit
    # calculations
    if ($cgi->param('course_filter')) {
        my $course_lib = $org || 'all';
        if ($cgi->param('course_filter') eq 'true') {
            $query = "on_reserve($course_lib) $query";
        } elsif ($cgi->param('course_filter') eq 'negated') {
            $query = "-on_reserve($course_lib) $query";
        }
    }

    my $depth;
    if ($query =~ /depth\(\d+\)/) {

        # depth is encoded in the search query
        ($depth) = ($query =~ /depth\((\d+)\)/);

    } else {

        if (defined $cgi->param('depth')) {
            $depth = $cgi->param('depth');
        } else {
            # no depth specified.  match the depth to the search org
            my ($org) = grep { $_->shortname eq $site } @{$ctx->{aou_list}->()};
            $depth = $org->ou_type->depth;
        }
        my $thing = " depth($depth)";

        $query .= $thing;
        push @naive_query_re, $thing;
    }

    # This gives templates a way to take site() and depth() back out of
    # query strings when they shouldn't be there (because they're controllable
    # with other widgets).
    $ctx->{naive_query_scrub} = sub {
        my ($query) = @_;
        $query =~ s/\Q$_\E// foreach (@naive_query_re);
        return $query;
    };

    $logger->info("tpac: site=$site, depth=$depth, user_query=$user_query, query=$query");

    return ($user_query, $query, $site, $depth);
}

sub _get_search_limit {
    my $self = shift;

    # param takes precedence
    my $limit = $self->cgi->param('limit');
    return $limit if $limit;

    if($self->editor->requestor) {
        $self->timelog("Checking for opac.hits_per_page preference");
        # See if the user has a hit count preference
        my $lset = $self->editor->search_actor_user_setting({
            usr => $self->editor->requestor->id, 
            name => 'opac.hits_per_page'
        })->[0];
        $self->timelog("Got opac.hits_per_page preference");
        return OpenSRF::Utils::JSON->JSON2perl($lset->value) if $lset;
    }

    return 10; # default
}

sub tag_circed_items {
    my $self = shift;
    my $e = $self->editor;

    $self->timelog("Tag circed items?");
    return 0 unless $e->requestor;
    $self->timelog("Checking for opac.search.tag_circulated_items");
    return 0 unless $self->ctx->{get_org_setting}->(
        $e->requestor->home_ou, 
        'opac.search.tag_circulated_items');

    # user has to be opted-in to circ history in some capacity
    $self->timelog("Checking for history.circ.retention_*");
    my $sets = $e->search_actor_user_setting({
        usr => $e->requestor->id, 
        name => [
            'history.circ.retention_age', 
            'history.circ.retention_start'
        ]
    });

    $self->timelog("Return from checking for history.circ.retention_*");

    return 0 unless @$sets;
    return 1;

}

# This only loads the bookbag itself (in support of a record results page)
# if a "bookbag" CGI parameter is specified and if the bookbag is public
# or owned by the logged-in user (if any).  Bookbag notes are fetched
# later if applicable.
sub load_rresults_bookbag {
    my ($self) = @_;

    my $bookbag_id = int($self->cgi->param("bookbag") || 0);
    return if $bookbag_id < 1;

    my %authz = $self->ctx->{"user"} ?
        ("-or" => {"pub" => "t", "owner" => $self->ctx->{"user"}->id}) :
        ("pub" => "t");

    $self->timelog("Load results bookbag");
    my $bbag = $self->editor->search_container_biblio_record_entry_bucket(
        {"id" => $bookbag_id, "btype" => "bookbag", %authz}
    );
    $self->timelog("Got results bookbag");

    if (!$bbag) {
        $self->apache->log->warn(
            "error from cstore retrieving bookbag $bookbag_id!"
        );
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    } elsif (@$bbag) {
        $self->ctx->{"bookbag"} = shift @$bbag;
    }

    return;
}

# assumes context has a bookbag we're already authorized to look at, and
# a list of rec_ids, reasonably sized (from paged search).
sub load_rresults_bookbag_item_notes {
    my ($self, $rec_ids) = @_;

    $self->timelog("Load results bookbag item notes");
    my $items_with_notes =
        $self->editor->search_container_biblio_record_entry_bucket_item([
            {"target_biblio_record_entry" => $rec_ids,
                "bucket" => $self->ctx->{"bookbag"}->id},
            {"flesh" => 1, "flesh_fields" => {"cbrebi" => ["notes"]},
                "order_by" => {"cbrebi" => ["id"]}}
        ]);
    $self->timelog("Got results bookbag item notes");

    if (!$items_with_notes) {
        $self->apache->log->warn("error from cstore retrieving cbrebi objects");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    $self->ctx->{"bookbag_items_by_bre_id"} = +{
        map { $_->target_biblio_record_entry => $_ } @$items_with_notes
    };

    return;
}

# $filter -- CCVM filter expression (see also composite attr def)
sub recs_from_metarecord {
    my ($self, $mr_id, $org, $depth, $filter) = @_;
    $self->timelog("Getting metarecords to records");

    # in the context of searching, we include all records which
    # have an opac-visible copy.
    my $bre_ids = $U->simplereq(
        'open-ils.circ',
        'open-ils.circ.holds.metarecord.filtered_records',
        $mr_id, $filter, $org, $depth, 1);

    $self->timelog("Got metarecords to records");
    return $bre_ids;
}



# context additions: 
#   page_size
#   hit_count
#   records : list of bre's and copy-count objects
my $max_concurrent_search;
sub load_rresults {
    my $self = shift;
    my %args = @_;
    my $internal = $args{internal};
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;
    my $e = $self->editor;

    my $mc = OpenSRF::Utils::Cache->new('global');
    my $client_ip = $self->apache->headers_in->get('X-Forwarded-For') ||
        $self->apache->useragent_ip;
    ($client_ip) = split(/,\s*/, $client_ip);
    $logger->activity("Client IP: $client_ip");


    # 1. param->metarecord : view constituent bib records for a metarecord
    # 2. param->modifier=metabib : perform a metarecord search
    my $metarecord = $ctx->{metarecord} = $cgi->param('metarecord');
    my @mods = $cgi->multi_param('modifier');
    my $is_meta = (@mods and grep {$_ eq 'metabib'} @mods and !$metarecord);
    my $id_key = $is_meta ? 'mmr_id' : 'bre_id';

    # find the last record in the set, then redirect
    my $find_last = $cgi->param('find_last');

    $self->timelog("Loading results");
    # load bookbag metadata, if requested.
    if (my $bbag_err = $self->load_rresults_bookbag) {
        return $bbag_err;
    }

    $ctx->{page} = 'rresult' unless $internal;
    $ctx->{ids} = [];
    $ctx->{records} = [];
    $ctx->{search_facets} = {};
    $ctx->{hit_count} = 0;
    $ctx->{is_meta} = $is_meta;

    # Special alternative searches here.  This could all stand to be cleaner.
    if ($cgi->param("_special")) {
        $self->timelog("Calling MARC expert search");
        return $self->marc_expert_search(%args) if (scalar($cgi->param("tag")) and
            (!defined $cgi->param("query") or $cgi->param("query") =~ /^\s*$/));
        $self->timelog("Calling item barcode search");
        return $self->item_barcode_shortcut if (
            $cgi->param("qtype") and ($cgi->param("qtype") eq "item_barcode") and not $internal
        );
        $self->timelog("Calling call number browse");
        return $self->call_number_browse_standalone if (
            $cgi->param("qtype") and ($cgi->param("qtype") eq "cnbrowse")
        );
    }

    $self->timelog("Getting search parameters");
    my $page = $cgi->param('page') || 0;
    my @facets = $cgi->multi_param('facet');
    my $limit = $self->_get_search_limit;
    $ctx->{search_ou} = $self->_get_search_lib();
    $ctx->{pref_ou} = $self->_get_pref_lib() || $ctx->{search_ou};
    my $offset = $page * $limit;
    my $results; 
    my $tag_circs = $self->tag_circed_items;
    $self->timelog("Got search parameters");

    $ctx->{page_size} = $limit;
    $ctx->{search_page} = $page;

    # fetch this page plus the first hit from the next page
    if ($internal) {
        $limit = $offset + $limit + 1;
        $offset = 0;
    }

    my ($user_query, $query, $site, $depth) = _prepare_biblio_search($cgi, $ctx);

    $self->get_staff_search_settings;

    if (!$find_last and $ctx->{staff_saved_search_size}) {
        my ($key, $list) = $self->staff_save_search($query);
        if ($key) {
            $self->apache->headers_out->add(
                "Set-Cookie" => $self->cgi->cookie(
                    -name => (ref $self)->COOKIE_ANON_CACHE,
                    -path => "/",
                    -value => ($key || ''),
                    -expires => ($key ? undef : "-1h")
                )
            );
            $ctx->{saved_searches} = $list;
        }
    }
    # Limit and offset will stay here. Everything else should be part of
    # the query string, not special args.
    my $args = {'limit' => $limit, 'offset' => $offset};

    return Apache2::Const::OK unless $query;

    if ($tag_circs) {
        $args->{tag_circulated_records} = 1;
        $args->{authtoken} = $self->editor->authtoken;
    }
    $args->{from_metarecord} = $metarecord if $metarecord;

    # Stuff these into the TT context so that templates can use them in redrawing forms
    $ctx->{user_query} = $user_query;
    $ctx->{processed_search_query} = $query;

    $query = "$_ $query" for @facets;

    my $ltag = $is_meta ? '[mmr search]' : '[bre search]';
    $logger->activity("EGWeb: $ltag $query");

    # Fetch the global flag, defaults to "never too many".
    unless (defined $max_concurrent_search) {
        my $mcs = $e->retrieve_config_global_flag('opac.max_concurrent_search.ip');
        $max_concurrent_search = ($mcs and $mcs->enabled eq 't') ? $mcs->value : 0;
    }

    if ($max_concurrent_search > 0) {
        # Right up front, we will limit concurrent searches coming from the same client IP, if configured to do so.
        $mc->get_cache('EGWEB-MAX-SEARCH-IP:'.$client_ip) || $mc->{memcache}->add('EGWEB-MAX-SEARCH-IP:'.$client_ip, 0);
        my $concurrent_searches = $mc->{memcache}->incr('EGWEB-MAX-SEARCH-IP:'.$client_ip);
        $logger->activity("Concurrent searches from client IP $client_ip: $concurrent_searches");

        if ($concurrent_searches > $max_concurrent_search) {
            $self->apache->log->warn("Too many concurrent searches from IP $client_ip");
            $mc->{memcache}->decr('EGWEB-MAX-SEARCH-IP:'.$client_ip);
            return 429; # Apache2::Const does not have a symbol for 429 too many requests
        }
    }

    my $method = 'open-ils.search.biblio.multiclass.query';
    try {
        $method .= '.staff' if $ctx->{is_staff};
        $method =~ s/biblio/metabib/ if $is_meta;

        my $ses = OpenSRF::AppSession->create('open-ils.search');

        $self->timelog("Firing off the multiclass query");
        my $req = $ses->request($method, $args, $query, 1, $ctx->{physical_loc});
        $results = $req->gather(1);
        $self->timelog("Returned from the multiclass query");

    } catch Error with {
        my $err = shift;
        $logger->error("multiclass search error: $err");
        $results = {count => 0, ids => []};
    };

    $mc->{memcache}->decr('EGWEB-MAX-SEARCH-IP:'.$client_ip) if ($max_concurrent_search);

    # INFO: an OpenILS::Event only means "go away" for now.
    if (defined $U->event_code($results)) {
        $logger->activity("$method returned event: " . $U->event_code($results));
        $self->apache->log->warn( "$method returned event: " . $U->event_code($results));
        return 429; # Apache2::Const does not have a symbol for 429 too many requests
    }

    my $rec_ids = [map { $_->[0] } @{$results->{ids}}];

    $ctx->{ids} = $rec_ids;
    $ctx->{hit_count} = $results->{count};
    $ctx->{superpage} = $results->{superpage};
    $ctx->{superpage_size} = $results->{superpage_size};
    $ctx->{pagable_limit} = $results->{core_limit};
    $ctx->{query_struct} = $results->{global_summary}{query_struct};
    $logger->debug('query struct: '. Dumper($ctx->{query_struct}));
    $ctx->{canonicalized_query} = $results->{global_summary}{canonicalized_query};
    $ctx->{search_summary} = $results->{global_summary};

    if ($find_last) {
        # redirect to the record detail page for the last record in the results
        my $rec_id = pop @$rec_ids;
        $cgi->delete('find_last');
        my $url = $cgi->url(-full => 1, -path => 1, -query => 1);
        # TODO: metarecord => /rresults?metarecord=$mmr_id
        $url =~ s|/results|/record/$rec_id|;
        return $self->generic_redirect($url);
    }

    return Apache2::Const::OK if @$rec_ids == 0 or $internal;

    $self->load_rresults_bookbag_item_notes($rec_ids) if $ctx->{bookbag};

    my $fetch_recs = $rec_ids;

    $self->timelog("Calling get_records_and_facets()");
    my ($facets, @data) = $self->get_records_and_facets(
        $fetch_recs, $results->{facet_key}, 
        {
            flesh => '{holdings_xml,mra,acp,acnp,acns,bmp,cbs}',
            site => $site,
            metarecord => $is_meta,
            depth => $depth,
            pref_lib => $ctx->{pref_ou},
            library_group => $ctx->{search_lasso},
        }
    );
    $self->timelog("Returned from get_records_and_facets()");

    if ($page == 0 and @$rec_ids == 1) {
        my $stat = 0;
        if ($is_meta) {
            # if the MR has a single constituent record, it will
            # be in array position 4 of the result blob.
            # otherwise, we don't want to redirect anyway.
            my $bre_id = $results->{ids}->[0]->[4];
            $stat = $self->check_1hit_redirect([$bre_id]) if $bre_id;
        } else {
            my $stat = $self->check_1hit_redirect($rec_ids);
        }
        return $stat if $stat;
    }

    # load temporary_list settings for user and ou:
    $self->_load_lists_and_settings if ($ctx->{user});

    my %mr_contents;
    # shove recs into context in search results order
    for my $rec_id (@$rec_ids) {
        my ($rec) = grep { $_->{$id_key} == $rec_id } @data;
        push(@{$ctx->{records}}, $rec);

        if ($is_meta) {
            try {
                my $method = 'open-ils.search.biblio.multiclass.query';
                $method .= '.staff' if $ctx->{is_staff};
                my $ses = OpenSRF::AppSession->create('open-ils.search');
                $self->timelog("Firing off the multiclass query: ". $rec_id);
                $args->{from_metarecord} = $rec_id;
                # offset of main search does not apply to the MR
                # constituents query
                my $save_offset = $args->{offset};
                $args->{offset} = 0;
                $mr_contents{$rec_id} = $ses->request($method, $args, $query, 1, $ctx->{physical_loc});
                $args->{offset} = $save_offset;
            } catch Error with {
                my $err = shift;
                $logger->error("multiclass search error: $err");
            };
        }
    }

    # above we fire all searches in parallel, now we collect the results
    if ($is_meta) {
        for my $rec_id (@$rec_ids) {
            my ($rec) = grep { $_->{$id_key} == $rec_id } @data;
            my $meta_results;
            if ($mr_contents{$rec_id}) {
                $meta_results = $mr_contents{$rec_id}->gather(1);
                $self->timelog("Returned from the multiclass query: ". $rec_id);
            } else {
                $meta_results = {count => 0, ids => []};
            }
            my $meta_rec_ids = [map { $_->[0] } @{$meta_results->{ids}}];
            $rec->{mr_constituent_count} = $meta_results->{count};
            $rec->{mr_constituent_ids} = $meta_rec_ids;
        }
    }

    my $course_module_opt_in = 0;
    if ($ctx->{get_org_setting}->($self->_get_search_lib, "circ.course_materials_opt_in")) {
        $course_module_opt_in = 1;
    }

    for my $rec (@{$ctx->{records}}) {
        my ($res_rec) = grep { $_->[0] == $rec->{$id_key} } @{$results->{ids}};
        $rec->{badges} = [split(',', $res_rec->[1])] if $res_rec->[1];
        $rec->{popularity} = $res_rec->[2];
        if ($course_module_opt_in) {
            $rec->{course_materials} = $U->simplereq(
                'open-ils.courses',
                'open-ils.courses.course_materials.retrieve.atomic',
                {record => $rec->{id}}
            );
            my %course_ids;
            for my $material (@{$rec->{course_materials}}) {
                $course_ids{$material->course} = 1;
            }

            $rec->{courses} = $U->simplereq(
                'open-ils.courses',
                'open-ils.courses.courses.retrieve',
                keys %course_ids
            );
        }
        if ($tag_circs) {
            # index 3 (5 for MR) in the per-record result array is a boolean which
            # indicates whether the record in question is in the users
            # accessible circ history list
            my $index = $is_meta ? 5 : 3;
            $rec->{user_circulated} = 1 if $res_rec->[$index];
        }
    }
    

    $ctx->{search_facets} = $facets;

    return Apache2::Const::OK;
}

# If the calling search results in 1 record and the client
# is configured to do so, redirect the search results to 
# the record details page.
sub check_1hit_redirect {
    my ($self, $rec_ids) = @_;
    my $ctx = $self->ctx;

    return undef unless $rec_ids and @$rec_ids == 1;

    my ($sname, $org);

    $self->timelog("Checking whether to jump to details on a single hit");
    if ($ctx->{is_staff}) {
        $sname = 'opac.staff.jump_to_details_on_single_hit';
        $org = $ctx->{user}->ws_ou;

    } else {
        $sname = 'opac.patron.jump_to_details_on_single_hit';
        $org = $self->_get_search_lib();
    }

    $self->timelog("Return from checking whether to jump to details on a single hit");

    return undef unless 
        $self->ctx->{get_org_setting}->($org, $sname);

    my $base_url = sprintf(
        '%s://%s%s/record/%s',
        $self->ctx->{proto},
        $self->ctx->{hostname},
        $self->ctx->{opac_root},
        $$rec_ids[0],
    );
    
    # If we get here from the same record detail page to which we
    # now wish to redirect, do not perform the redirect.  This
    # approach seems to work well, with the rare exception of 
    # performing a new search directly from the detail page that 
    # happens to result in the same single hit.  In this case, the 
    # user will be left on the search results page.  This could be 
    # overcome w/ additional CGI, etc., but I'm not sure it's necessary.
    if (my $referer = $ctx->{referer}) {
        $referer =~ s/([^?]*).*/$1/g;
        return undef if $base_url eq $referer;
    }

    return $self->generic_redirect($base_url . '?' . $self->cgi->query_string);
}

# Searching by barcode is a special search that does /not/ respect any other
# of the usual search parameters, not even the ones for sorting and paging!
sub item_barcode_shortcut {
    my ($self) = @_;

    $self->timelog("Searching for item_barcode");
    my $method = "open-ils.search.multi_home.bib_ids.by_barcode";
    if (my $search = create OpenSRF::AppSession("open-ils.search")) {
        my $rec_ids = $search->request(
            $method, $self->cgi->param("query")
        )->gather(1);
        $search->kill_me;
        $self->timelog("Finished searching for item_barcode");

        if (ref $rec_ids ne 'ARRAY') {

            if($U->event_equals($rec_ids, 'ASSET_COPY_NOT_FOUND')) {
                $rec_ids = [];

            } else {
                if (defined $U->event_code($rec_ids)) {
                    $self->apache->log->warn(
                        "$method returned event: " . $U->event_code($rec_ids)
                    );
                } else {
                    $self->apache->log->warn(
                        "$method returned something unexpected: $rec_ids"
                    );
                }
                return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
            }
        }

        $self->timelog("Calling get_records_and_facets() for item_barcode");
        my ($facets, @data) = $self->get_records_and_facets(
            $rec_ids, undef, {flesh => "{holdings_xml,mra,acnp,acns,bmp,cbs}"}
        );
        $self->timelog("Returned from calling get_records_and_facets() for item_barcode");

        my $stat = $self->check_1hit_redirect($rec_ids);
        return $stat if $stat;

        $self->ctx->{records} = [@data];
        $self->ctx->{search_facets} = {};
        $self->ctx->{hit_count} = scalar @data;
        $self->ctx->{page_size} = $self->ctx->{hit_count};
        # load temporary_list settings for user and ou:
        $self->_load_lists_and_settings if ($self->ctx->{user});

        return Apache2::Const::OK;
    } {
        $self->apache->log->warn("couldn't connect to open-ils.search");
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }
}

# like item_barcode_search, this can't take all the usual search params, but
# this one will at least do site, limit and page
sub marc_expert_search {
    my ($self, %args) = @_;

    my @tags = $self->cgi->multi_param("tag");
    my @subfields = $self->cgi->multi_param("subfield");
    my @terms = $self->cgi->multi_param("term");

    my $query = [];
    for (my $i = 0; $i < scalar @tags; $i++) {
        next if ($tags[$i] eq "" || $terms[$i] eq "");
        $subfields[$i] = '_' unless $subfields[$i];
        push @$query, {
            "term" => $terms[$i],
            "restrict" => [{"tag" => $tags[$i], "subfield" => $subfields[$i]}]
        };
    }

    $logger->info("query for expert search: " . Dumper($query));

    $self->timelog("Getting search parameters");
    # loc, limit and offset
    my $page = $self->cgi->param("page") || 0;
    my $limit = $self->_get_search_limit;
    $self->ctx->{search_ou} = $self->_get_search_lib();
    $self->ctx->{pref_ou} = $self->_get_pref_lib();
    my $offset = $page * $limit;
    $self->timelog("Got search parameters");

    $self->ctx->{records} = [];
    $self->ctx->{search_facets} = {};
    $self->ctx->{page_size} = $limit;
    $self->ctx->{hit_count} = 0;
    $self->ctx->{ids} = [];
    $self->ctx->{search_page} = $page;
        
    # nothing to do
    return Apache2::Const::OK if @$query == 0;

    if ($args{internal}) {
        $limit = $offset + $limit + 1;
        $offset = 0;
    }

    $self->timelog("Searching for MARC expert");
    my $method = 'open-ils.search.biblio.marc';
    $method .= '.staff' if $self->ctx->{is_staff};
    my $timeout = 120;
    my $ses = OpenSRF::AppSession->create('open-ils.search');

    #when a sort variable is passed in we need to add its value to the arguments
    my $arghash = {searches => $query, org_unit => $self->ctx->{search_ou}};
    if (defined $self->cgi->param("sort")) {
        my ($sort, $sort_dir) = split /\./, $self->cgi->param('sort');
        $arghash = {%$arghash, sort => "$sort"};
        if (!defined $sort_dir) {
            $arghash = {%$arghash, sort_dir => "ASC"};
        }
    }

    #add the offset and limit to the argash, so we can go past 100 results
    #if offset and limit are not in the args then they default to 0 and 100
    #respectively in biblio_multi_search_full_rec, which limits the results to 100
    #records
    $arghash = {%$arghash, offset => $offset, limit => $limit}; 

    my $req = $ses->request(
        $method,
        $arghash,
        $timeout);

    my $resp = $req->recv($timeout);
    my $results = $resp ? $resp->content : undef;
    $ses->kill_me;
    $self->timelog("Got our MARC expert results");

    if (defined $U->event_code($results)) {
        $self->apache->log->warn(
            "open-ils.search.biblio.marc returned event: " .
            $U->event_code($results)
        );
        return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
    }

    $self->ctx->{ids} = [ grep { $_ } @{$results->{ids}} ];
    $self->ctx->{hit_count} = $results->{count};

    return Apache2::Const::OK if @{$self->ctx->{ids}} == 0 or $args{internal};

    if ($page == 0) {
        my $stat = $self->check_1hit_redirect($self->ctx->{ids});
        return $stat if $stat;
    }

    $self->timelog("Calling get_records_and_facets() for MARC expert");
    my ($facets, @data) = $self->get_records_and_facets(
        $self->ctx->{ids}, undef, {
            flesh => "{holdings_xml,mra,acnp,acns,cbs}",
            pref_lib => $self->ctx->{pref_ou},
        }
    );
    $self->timelog("Returned from calling get_records_and_facets() for MARC expert");

    # load temporary_list settings for user and ou:
    $self->_load_lists_and_settings if ($self->ctx->{user});

    $self->ctx->{records} = [@data];

    return Apache2::Const::OK;
}

sub call_number_browse_standalone {
    my ($self) = @_;

    if (my $cnfrag = $self->cgi->param("query")) {
        my $url = sprintf(
            '%s://%s%s/cnbrowse?cn=%s',
            $self->ctx->{proto},
            $self->ctx->{hostname},
            $self->ctx->{opac_root},
            $cnfrag # XXX some kind of escaping needed here?
        );
        $url .= '&locg=' . $self->_get_search_lib() if ($self->_get_search_lib());
        return $self->generic_redirect($url);
    } else {
        return $self->generic_redirect; # return to search page
    }
}

sub load_cnbrowse {
    my ($self) = @_;

    $self->prepare_browse_call_numbers();

    return Apache2::Const::OK;
}

sub get_staff_search_settings {
    my ($self) = @_;

    unless ($self->ctx->{is_staff}) {
        $self->ctx->{staff_saved_search_size} = 0;
        return;
    }

    $self->timelog("Getting staff search size");
    my $sss_size = $self->ctx->{get_org_setting}->(
        $self->ctx->{physical_loc} || $self->ctx->{aou_tree}->()->id,
        "opac.staff_saved_search.size",
    );
    $self->timelog("Got staff search size");

    # Sic: 0 is 0 (off), but undefined is 10.
    $sss_size = 10 unless defined $sss_size;

    $self->ctx->{staff_saved_search_size} = $sss_size;
}

sub staff_load_searches {
    my ($self) = @_;

    my $cache_key = $self->cgi->cookie((ref $self)->COOKIE_ANON_CACHE);

    my $list = [];
    if ($cache_key) {
        $self->timelog("Getting anon_cache value");
        $list = $U->simplereq(
            "open-ils.actor",
            "open-ils.actor.anon_cache.get_value",
            $cache_key, (ref $self)->ANON_CACHE_STAFF_SEARCH
        );
        $self->timelog("Got anon_cache value");

        unless ($list) {
            undef $cache_key;
            $list = [];
        }
    }

    return ($cache_key, $list);
}

sub staff_save_search {
    my ($self, $query) = @_;

    my $sss_size = $self->ctx->{staff_saved_search_size}; 
    return unless $sss_size > 0;

    my ($cache_key, $list) = $self->staff_load_searches;
    my %already = ( map { $_ => 1 } @$list );

    unshift @$list, $query unless $already{$query};

    splice @$list, $sss_size if scalar @$list > $sss_size;

    $self->timelog("Setting anon_cache value");
    $cache_key = $U->simplereq(
        "open-ils.actor",
        "open-ils.actor.anon_cache.set_value",
        $cache_key, (ref $self)->ANON_CACHE_STAFF_SEARCH, $list
    );
    $self->timelog("Set anon_cache value");

    return ($cache_key, $list);
}

1;
