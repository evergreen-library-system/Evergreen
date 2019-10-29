package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_GONE HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST HTTP_NOT_FOUND);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use Net::HTTP::NB;
use IO::Select;
my $U = 'OpenILS::Application::AppUtils';

our $ac_types = ['toc',  'anotes', 'excerpt', 'summary', 'reviews'];

# context additions: 
#   record : bre object
sub load_record {
    my $self = shift;
    my %kwargs = @_;
    my $ctx = $self->ctx;
    $ctx->{page} = 'record';  
    $ctx->{readonly} = $self->cgi->param('readonly');

    $self->timelog("load_record() began");

    my $rec_id = $ctx->{page_args}->[0];

    return Apache2::Const::HTTP_BAD_REQUEST 
        unless $rec_id and $rec_id =~ /^\d+$/;

    $self->added_content_stage1($rec_id);
    $self->timelog("past added content stage 1");

    my $org = $self->_get_search_lib();
    my $org_name = $ctx->{get_aou}->($org)->shortname;
    my $pref_ou = $self->_get_pref_lib();
    my $depth = $self->cgi->param('depth');
    $depth = $ctx->{get_aou}->($org)->ou_type->depth 
        unless defined $depth; # can be 0

    my $copy_depth = $self->cgi->param('copy_depth');
    $copy_depth = $depth unless defined $copy_depth; # can be 0
    $self->ctx->{copy_depth} = $copy_depth;

    my $copy_limit = int($self->cgi->param('copy_limit') || 10);
    my $copy_offset = int($self->cgi->param('copy_offset') || 0);

    $self->get_staff_search_settings;
    if ($ctx->{staff_saved_search_size}) {
        $ctx->{saved_searches} = ($self->staff_load_searches)[1];
    }
    $self->timelog("past staff saved searches");

    $self->fetch_related_search_info($rec_id) unless $kwargs{no_search};
    $self->timelog("past related search info");

    # Check for user and load lists and prefs
    if ($self->ctx->{user}) {
        $self->_load_lists_and_settings;
        $self->timelog("load user lists and settings");
    }

    # run copy retrieval in parallel to bib retrieval
    # XXX unapi
    my $cstore = OpenSRF::AppSession->create('open-ils.cstore');
    my $copy_rec = $cstore->request(
        'open-ils.cstore.json_query.atomic', 
        $self->mk_copy_query($rec_id, $org, $copy_depth, $copy_limit, $copy_offset, $pref_ou)
    );

    if ($self->cgi->param('badges')) {
        my $badges = $self->cgi->param('badges');
        $badges = $badges ? [split(',', $badges)] : [];
        $badges = [grep { /^\d+$/ } @$badges];
        if (@$badges) {
            $self->ctx->{badge_scores} = $cstore->request(
                'open-ils.cstore.direct.rating.record_badge_score.search.atomic',
                { record => $rec_id, badge => $badges },
                { flesh => 1, flesh_fields => { rrbs => ['badge'] } }
            )->gather(1);
        }
    } else {
        $self->ctx->{badge_scores} = [];
    }

    # find foreign copy data
    my $peer_rec = $U->simplereq(
        'open-ils.search',
        'open-ils.search.peer_bibs', $rec_id );

    $ctx->{foreign_copies} = $peer_rec;

    my (undef, @rec_data) = $self->get_records_and_facets([$rec_id], undef, {
        flesh => '{holdings_xml,bmp,mra,acp,acnp,acns}',
        site => $org_name,
        depth => $depth,
        pref_lib => $pref_ou
    });

    $self->timelog("past get_records_and_facets()");
    $ctx->{bre_id} = $rec_data[0]->{id};
    $ctx->{marc_xml} = $rec_data[0]->{marc_xml};

    $ctx->{copies} = $copy_rec->gather(1);

    # Add public copy notes to each copy - and while we're in there, grab peer bib records
    # and copy tags
    my %cached_bibs = ();
    foreach my $copy (@{$ctx->{copies}}) {
        $copy->{notes} = $U->simplereq(
            'open-ils.circ',
            'open-ils.circ.copy_note.retrieve.all',
            {itemid => $copy->{id}, pub => 1 }
        );
        $self->timelog("past copy note retrieval call");
        my $meth = 'open-ils.circ.copy_tags.retrieve';
        $meth .= ".staff" if $ctx->{is_staff};
        $copy->{tags} = $U->simplereq(
            'open-ils.circ',
            $meth,
            {
                ($ctx->{is_staff} ? (authtoken => $ctx->{authtoken}) : ()),
                copy_id  => $copy->{id},
                scope    => $org,
                depth    => $copy_depth,
            }
        );
        $self->timelog("past copy tag retrieval call");
        $copy->{peer_bibs} = $U->simplereq(
            'open-ils.search',
            'open-ils.search.multi_home.bib_ids.by_barcode',
            $copy->{barcode}
        );
        $self->timelog("past peer bib id retrieval");
        my @peer_marc;
        foreach my $bib (@{$copy->{peer_bibs}}) {
            next if $bib eq $ctx->{bre_id};
            next if $cached_bibs{$bib};
            my (undef, @peer_data) = $self->get_records_and_facets(
                [$bib], undef, {
                    flesh => '{}',
                    site => $org_name,
                    depth => $depth,
                    pref_lib => $pref_ou
            });
            $cached_bibs{$bib} = 1;
            #$copy->{peer_bib_marc} = $peer_data[0]->{marc_xml};
            push @peer_marc, $peer_data[0]->{marc_xml};
            $self->timelog("fetched peer bib record $bib");
        }
        $copy->{peer_bib_marc} = \@peer_marc;
    }

    $self->timelog("past store copy retrieval call");
    $ctx->{copy_limit} = $copy_limit;
    $ctx->{copy_offset} = $copy_offset;

    $ctx->{have_holdings_to_show} = 0;
    $ctx->{have_mfhd_to_show} = 0;

    $self->get_hold_copy_summary($rec_id, $org);

    $self->timelog("past get_hold_copy_summary()");
    $self->ctx->{bib_is_dead} = OpenILS::Application::AppUtils->is_true(
        OpenILS::Utils::CStoreEditor->new->json_query({
            select => { bre => [ 'deleted' ] },
            from => 'bre',
            where => { 'id' => $rec_id }
        })->[0]->{deleted}
    );

    $cstore->kill_me;

    # Shortcut and help the machines with a 410 Gone status code
    if ($self->ctx->{bib_is_dead}) {
        return Apache2::Const::HTTP_GONE;
    }

    # Shortcut and help the machines with a 404 Not Found status code
    if (!$ctx->{bre_id}) {
        return Apache2::Const::HTTP_NOT_FOUND;
    }

    $ctx->{mfhd_summaries} =
        $self->get_mfhd_summaries($rec_id, $org, $copy_depth);

    if (
        $ctx->{get_org_setting}->
            ($org, "opac.fully_compressed_serial_holdings")
    ) {
        # We're loading this data here? Are we therefore assuming that we
        # *are* going to display something in the "issues" expandy?
        $self->load_serial_holding_summaries($rec_id, $org, $copy_depth);
    } else {
        if ($ctx->{mfhd_summaries} && scalar(@{$ctx->{mfhd_summaries}})
        ) {
            $ctx->{have_mfhd_to_show} = 1;
        };
    }

    $self->timelog("past serials holding stuff");

    my %expandies = (
        marchtml => sub {
            $ctx->{marchtml} = $self->mk_marc_html($rec_id);
        },
        issues => sub {
            return;
            # XXX this needed?
        },
        cnbrowse => sub {
            $self->prepare_browse_call_numbers();
        }
    );

    my @expand = $self->cgi->param('expand');
    if (grep {$_ eq 'all'} @expand) {
        $ctx->{expand_all} = 1;
        $expandies{$_}->() for keys %expandies;

    } else {
        for my $exp (@expand) {
            $ctx->{"expand_$exp"} = 1;
            $expandies{$exp}->() if exists $expandies{$exp};
        }
    }

    $self->timelog("past expandies");

    $self->added_content_stage2($rec_id);

    $self->timelog("past added content stage 2");

    # Gather up metarecord info for display
    # Let's start by getting the metarecord ID
    my $mmr_id = OpenILS::Utils::CStoreEditor->new->json_query({
        select   => { mmrsm => [ 'metarecord' ] },
        from     => 'mmrsm',
        where    => { 'source' => $rec_id }
    })->[0]->{metarecord};
    # If this record is apart of a meta group, I want to know more
    if ( $mmr_id ) {
        my (undef, @metarecord_data) = $self->get_records_and_facets([$mmr_id], undef, {
            flesh => '{holdings_xml,mra}',
            metarecord => 1,
            site => $org_name,
            depth => $depth,
            pref_lib => $pref_ou
        });
        my ($rec) = grep { $_->{mmr_id} == $mmr_id } @metarecord_data;
        $ctx->{mmr_id} = $mmr_id;
        $ctx->{mmr_data} = $rec;
    }
    return Apache2::Const::OK;
}

# collect IDs and info on the search that lead to this details page
# If no search query, etc is present, we leave ctx.search_result_index == -1
sub fetch_related_search_info {
    my $self = shift;
    my $rec_id = shift;
    my $ctx = $self->ctx;
    $ctx->{search_result_index} = -1;

    $self->load_rresults(internal => 1);

    my @search_ids = @{$ctx->{ids}};
    return unless @search_ids;

    for my $idx (0..$#search_ids) {
        if ($search_ids[$idx] == $rec_id) {
            $ctx->{prev_search_record} = $search_ids[$idx - 1] if $idx > 0;
            $ctx->{next_search_record} = $search_ids[$idx + 1];
            $ctx->{search_result_index} = $idx;
            last;
        }
    }

    $ctx->{first_search_record} = $search_ids[0];
    $ctx->{last_search_record} = $search_ids[-1];
}


sub mk_copy_query {
    my $self = shift;
    my $rec_id = shift;
    my $org = shift;
    my $depth = shift;
    my $copy_limit = shift;
    my $copy_offset = shift;
    my $pref_ou = shift;

    my $query = $U->basic_opac_copy_query(
        $rec_id, undef, undef, $copy_limit, $copy_offset, $self->ctx->{is_staff}
    );

    if($org != $self->ctx->{aou_tree}->()->id) { 
        # no need to add the org join filter if we're not actually filtering
        $query->{from}->{acp}->[1] = { aou => {
            fkey => 'circ_lib',
            field => 'id',
            filter => {
                id => {
                    in => {
                        select => {aou => [{
                            column => 'id', 
                            transform => 'actor.org_unit_descendants',
                            result_field => 'id', 
                            params => [$depth]
                        }]},
                        from => 'aou',
                        where => {id => $org}
                    }
                }
            }
        }};
    };

    # Unsure if we want these in the shared function, leaving here for now
    unshift(@{$query->{order_by}},
        { class => "aou", field => 'id',
          transform => 'evergreen.rank_ou', params => [$org, $pref_ou]
        }
    );
    push(@{$query->{order_by}},
        { class => "acp", field => 'id',
          transform => 'evergreen.rank_cp'
        }
    );

    return $query;
}

sub mk_marc_html {
    my($self, $rec_id) = @_;

    # could be optimized considerably by performing the xslt on the already fetched record
    return $U->simplereq(
        'open-ils.search', 
        'open-ils.search.biblio.record.html', $rec_id, 1);
}

sub load_serial_holding_summaries {
    my ($self, $rec_id, $org, $depth) = @_;

    my $limit = $self->cgi->param("slimit") || 10;
    my $offset = $self->cgi->param("soffset") || 0;

    my $serial = create OpenSRF::AppSession("open-ils.serial");

    # First, get the tree of /summaries/ of holdings.
    my $tree = $serial->request(
        "open-ils.serial.holding_summary_tree.by_bib",
        $rec_id, $org, $depth, $limit, $offset
    )->gather(1);

    return if $self->apache_log_if_event(
        $tree, "getting holding summary tree for record $rec_id"
    );

    # Next, if requested, get a list of individual holdings under a
    # particular summary.
    my $holdings;
    my $summary_id = int($self->cgi->param("sid") || 0);
    my $summary_type = $self->cgi->param("stype");

    if ($summary_id and $summary_type) {
        my $expand_path = [ $self->cgi->param("sepath") ],
        my $expand_limit = $self->cgi->param("selimit");
        my $expand_offsets = [ $self->cgi->param("seoffset") ];
        my $auto_expand_first = 0;

        if (not @$expand_offsets) {
            $expand_offsets = undef;
            $auto_expand_first = 1;
        }

        $holdings = $serial->request(
            "open-ils.serial.holdings.grouped_by_summary",
            $summary_type, $summary_id,
            $expand_path, $expand_limit, $expand_offsets,
            $auto_expand_first,
            1 + ($self->ctx->{is_staff} ? 1 : 0)
        )->gather(1);

        if ($holdings and ref $holdings eq "ARRAY") {
            $self->place_holdings_with_summary(
                    $tree, $holdings, $summary_id, $summary_type
            ) or $self->apache->log->warn(
                "could not place holdings within summary tree"
            );
        } else {
            $self->apache_log_if_event(
                $holdings, "getting holdings grouped by summary $summary_id"
            );
        }
    }

    $serial->kill_me;

    # The presence of any keys in the tree hash other than 'more' means that we
    # must have /something/ we could show.
    $self->ctx->{have_holdings_to_show} = grep { $_ ne 'more' } (keys %$tree);

    $self->ctx->{holding_summary_tree} = $tree;
}

# This helper to load_serial_holding_summaries() recursively searches in
# $tree for a holding summary matching $sid and $stype, and places $holdings
# within the node for that summary. IOW, this is about showing expanded
# holdings under their "parent" summary.
sub place_holdings_with_summary {
    my ($self, $tree, $holdings, $sid, $stype) = @_;

    foreach my $sum (@{$tree->{holding_summaries}}) {
        if ($sum->{id} == $sid and $sum->{summary_type} eq $stype) {
            $sum->{holdings} = $holdings;
            return 1;
        }
    }

    foreach my $child (@{$tree->{children}}) {
        return 1 if $self->place_holdings_with_summary(
            $child, $holdings, $sid, $stype
        );
    }

    return;
}

sub get_mfhd_summaries {
    my ($self, $rec_id, $org, $depth) = @_;

    my $serial = create OpenSRF::AppSession("open-ils.search");
    my $result = $serial->request(
        "open-ils.search.serial.record.bib.retrieve",
        $rec_id, $org, $depth
    )->gather(1);

    $serial->kill_me;
    return $result;
}

sub any_call_number_label {
    my ($self) = @_;

    if ($self->ctx->{copies} and @{$self->ctx->{copies}}) {
        return $self->ctx->{copies}->[0]->{call_number_label};
    } else {
        return;
    }
}

sub prepare_browse_call_numbers {
    my ($self) = @_;

    my $cn = ($self->cgi->param("cn") || $self->any_call_number_label) or
        return [];

    my $org_unit = $self->ctx->{get_aou}->($self->_get_search_lib()) ||
        $self->ctx->{aou_tree}->();

    my $supercat = create OpenSRF::AppSession("open-ils.supercat");
    my $results = $supercat->request(
        "open-ils.supercat.call_number.browse", 
        $cn, $org_unit->shortname, 9, $self->cgi->param("cnoffset")
    )->gather(1) || [];

    $supercat->kill_me;

    $self->ctx->{browsed_call_numbers} = [
        map {
            $_->record->marc(
                (new XML::LibXML)->parse_string($_->record->marc)
            );
            $_;
        } @$results
    ];
    $self->ctx->{browsing_ou} = $org_unit;
}

sub get_hold_copy_summary {
    my ($self, $rec_id, $org) = @_;
    my $ctx = $self->ctx;
    
    my $search = OpenSRF::AppSession->create('open-ils.search');
    my $copy_count_meth = 'open-ils.search.biblio.record.copy_count';
    # We want to include OPAC-invisible copies in a staff context
    if ($ctx->{is_staff}) {
        $copy_count_meth .= '.staff';
    }
    my $req1 = $search->request($copy_count_meth, $org, $rec_id); 

    # if org unit hiding applies, limit the hold count to holds
    # whose pickup library is within our depth-scoped tree
    my $count_args = {};
    while ($org and $ctx->{org_within_hiding_scope}->($org)) {
        $count_args->{pickup_lib_descendant} = $org;
        $org = $ctx->{get_aou}->($org)->parent_ou;
    }

    $self->ctx->{record_hold_count} = $U->simplereq(
        'open-ils.circ', 'open-ils.circ.bre.holds.count', 
        $rec_id, $count_args);

    $self->ctx->{copy_summary} = $req1->recv->content;

    $search->kill_me;
}

sub load_print_record {
    my $self = shift;

    my $rec_or_list_id = $self->ctx->{page_args}->[0]
        or return Apache2::Const::HTTP_BAD_REQUEST;

    my $is_list = $self->cgi->param('is_list');
    my $list;
    if ($is_list) {

        $list = $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.anon_cache.get_value',
            $rec_or_list_id, (ref $self)->CART_CACHE_MYLIST);

        if(!$list) {
            $list = [];
        }

        {   # sanitize
            no warnings qw/numeric/;
            $list = [map { int $_ } @$list];
            $list = [grep { $_ > 0} @$list];
        };
    } else {
        $list = $rec_or_list_id;
        $self->{ctx}->{bre_id} = $rec_or_list_id;
    }

    $self->{ctx}->{printable_record} = $U->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.print', $list);

    if ($self->cgi->param('clear_cart')) {
        $self->clear_anon_cache;
    }
    $self->ctx->{'redirect_to'} = $self->cgi->param('redirect_to');

    return Apache2::Const::OK;
}

sub load_email_record {
    my $self = shift;

    my $rec_or_list_id = $self->ctx->{page_args}->[0]
        or return Apache2::Const::HTTP_BAD_REQUEST;

    my $is_list = $self->cgi->param('is_list');
    my $list;
    if ($is_list) {

        $list = $U->simplereq(
            'open-ils.actor',
            'open-ils.actor.anon_cache.get_value',
            $rec_or_list_id, (ref $self)->CART_CACHE_MYLIST);

        if(!$list) {
            $list = [];
        }

        {   # sanitize
            no warnings qw/numeric/;
            $list = [map { int $_ } @$list];
            $list = [grep { $_ > 0} @$list];
        };
    } else {
        $list = $rec_or_list_id;
        $self->{ctx}->{bre_id} = $rec_or_list_id;
    }

    $U->simplereq(
        'open-ils.search',
        'open-ils.search.biblio.record.email', 
        $self->ctx->{authtoken}, $list);

    if ($self->cgi->param('clear_cart')) {
        $self->clear_anon_cache;
    }
    $self->ctx->{'redirect_to'} = $self->cgi->param('redirect_to');

    return Apache2::Const::OK;
}

# for each type, fire off the reqeust to see if content is available
# ctx.added_content.$type.status:
#   1 == available
#   2 == not available
#   3 == unknown
sub added_content_stage1 {
    my $self = shift;
    my $rec_id = shift;
    my $ctx = $self->ctx;
    my $sel_type = $self->cgi->param('ac') || '';

    # Connect to this machine's IP address, using the same 
    # Host with which our caller used to connect to us.
    # This avoids us having to route out of the cluster 
    # and back in to reach the top-level virtualhost.
    my $ac_addr = $ENV{SERVER_ADDR};
    # Internal connections are HTTP-only (no HTTPS) and assume the
    # connection port is '80' unless otherwise specified in the Apache
    # configuration (e.g. for proxy setups)
    my $ac_port = $self->apache->dir_config('OILSWebInternalHTTPPort') || 80;
    my $ac_host = $self->apache->hostname;
    my $ac_failed = 0;

    $logger->info("tpac: added content connecting to $ac_addr:$ac_port / $ac_host");

    $ctx->{added_content} = {};
    for my $type (@$ac_types) {
        last if $ac_failed;
        $ctx->{added_content}->{$type} = {content => ''};
        $ctx->{added_content}->{$type}->{status} = 3;

        $logger->debug("tpac: starting added content request for $rec_id => $type");

        # Net::HTTP::NB is non-blocking /after/ the initial connect()
        # Passing Timeout=>1 ensures we wait no longer than 1 second to 
        # connect to the local Evergreen instance (i.e. ourself).  
        # Connecting to oneself should either be very fast (normal) 
        # or very slow (routing problems).

        my $req = Net::HTTP::NB->new(
            Host => $ac_addr, Timeout => 1, PeerPort => $ac_port);
        if (!$req) {
            $logger->warn("Unable to connect to $ac_addr:$ac_port / $ac_host".
                " for added content lookup for $rec_id: $@");
            $ac_failed = 1;
            next;
        }

        $req->host($self->apache->hostname);

        my $http_type = ($type eq $sel_type) ? 'GET' : 'HEAD';
        $req->write_request($http_type => "/opac/extras/ac/$type/html/r/" . $rec_id);
        $ctx->{added_content}->{$type}->{request} = $req;
    }
}

# check each outstanding request.  If it's ready, read the HTTP 
# status and use it to determine if content is available.  Otherwise,
# leave the status as unknown.
sub added_content_stage2 {
    my $self = shift;
    my $ctx = $self->ctx;
    my $sel_type = $self->cgi->param('ac') || '';

    for my $type (keys %{$ctx->{added_content}}) {
        my $content = $ctx->{added_content}->{$type};

        if ($content->{status} == 3) {
            $logger->debug("tpac: finishing added content request for $type");

            my $req = $content->{request};
            my $sel = IO::Select->new($req);

            # if we are requesting a specific type of content, give the 
            # backend code a little extra time to retrieve the content.
            my $wait = $type eq $sel_type ? 3 : 0; # TODO: config?

            if ($sel->can_read($wait)) {
                my ($code) = $req->read_response_headers;
                $content->{status} = $code eq '200' ? 1 : 2;
                $logger->debug("tpac: added content request for $type returned $code");

                if ($code eq '200' and $type eq $sel_type) {
                    while (1) {
                        my $buf;
                        my $n = $req->read_entity_body($buf, 1024);
                        last unless $n;
                        $content->{content} .= $buf;
                    }
                }
            }
        }
        # To avoid a lot of hanging connections.
        if ($content->{request}) {
            $content->{request}->shutdown(2);
            $content->{request}->close();
        } 
    }
}

1;
