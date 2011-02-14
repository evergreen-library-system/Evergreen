package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use CGI;
use XML::LibXML;
use URI::Escape;
use Digest::MD5 qw(md5_hex);
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use DateTime::Format::ISO8601;
my $U = 'OpenILS::Application::AppUtils';

sub new {
    my($class, $apache, $ctx) = @_;

    my $self = bless({}, ref($class) || $class);

    $self->apache($apache);
    $self->ctx($ctx);
    $self->cgi(CGI->new);

    OpenILS::Utils::CStoreEditor->init; # just in case
    $self->editor(new_editor());

    return $self;
}


# current Apache2::RequestRec;
sub apache {
    my($self, $apache) = @_;
    $self->{apache} = $apache if $apache;
    return $self->{apache};
}

# runtime / template context
sub ctx {
    my($self, $ctx) = @_;
    $self->{ctx} = $ctx if $ctx;
    return $self->{ctx};
}

# cstore editor
sub editor {
    my($self, $editor) = @_;
    $self->{editor} = $editor if $editor;
    return $self->{editor};
}

# CGI handle
sub cgi {
    my($self, $cgi) = @_;
    $self->{cgi} = $cgi if $cgi;
    return $self->{cgi};
}


# load common data, then load page data
sub load {
    my $self = shift;

    $self->load_helpers;
    my $stat = $self->load_common;
    return $stat unless $stat == Apache2::Const::OK;

    my $path = $self->apache->path_info;

    return $self->load_simple("home") if $path =~ /opac\/home/;
    return $self->load_simple("advanced") if $path =~ /opac\/advanced/;
    return $self->load_login if $path =~ /opac\/login/;
    return $self->load_logout if $path =~ /opac\/logout/;
    return $self->load_rresults if $path =~ /opac\/results/;
    return $self->load_record if $path =~ /opac\/record/;

    # ----------------------------------------------------------------
    # These pages require authentication
    # ----------------------------------------------------------------
    unless($self->cgi->https and $self->editor->requestor) {
        # If a secure resource is requested insecurely, redirect to the login page
        my $url = 'https://' . $self->apache->hostname . $self->ctx->{opac_root} . "/login";
        $self->apache->print($self->cgi->redirect(-url => $url));
        return Apache2::Const::REDIRECT;
    }

    return $self->load_place_hold if $path =~ /opac\/place_hold/;
    return $self->load_myopac_holds if $path =~ /opac\/myopac\/holds/;
    return $self->load_myopac_circs if $path =~ /opac\/myopac\/circs/;
    return $self->load_myopac_fines if $path =~ /opac\/myopac\/fines/;
    return $self->load_myopac_update_email if $path =~ /opac\/myopac\/update_email/;
    return $self->load_myopac_bookbags if $path =~ /opac\/myopac\/bookbags/;
    return $self->load_myopac if $path =~ /opac\/myopac/;
    # ----------------------------------------------------------------

    return Apache2::Const::OK;
}

# general purpose utility functions added to the environment

my %cache = (
    map => {aou => {}}, # others added dynamically as needed
    list => {},
    org_settings => {}
);

sub load_helpers {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    # fetch-on-demand-and-cache subs for commonly used public data
    my @public_classes = qw/ccs aout cifm citm clm cmf/;

    for my $hint (@public_classes) {

        my ($class) = grep {
            $Fieldmapper::fieldmap->{$_}->{hint} eq $hint
        } keys %{ $Fieldmapper::fieldmap };

        my $ident_field =  $Fieldmapper::fieldmap->{$class}->{identity};

	    $class =~ s/Fieldmapper:://o;
	    $class =~ s/::/_/g;

        # copy statuses
        my $list_key = $hint . '_list';
        my $find_key = "find_$hint";

        $ctx->{$list_key} = sub {
            my $method = "retrieve_all_$class";
            $cache{list}{$hint} = $e->$method() unless $cache{list}{$hint};
            return $cache{list}{$hint};
        };
    
        $cache{map}{$hint} = {} unless $cache{map}{$hint};

        $ctx->{$find_key} = sub {
            my $id = shift;
            return $cache{map}{$hint}{$id} if $cache{map}{$hint}{$id}; 
            ($cache{map}{$hint}{$id}) = grep { $_->$ident_field eq $id } @{$ctx->{$list_key}->()};
            return $cache{map}{$hint}{$id};
        };

    }

    $ctx->{aou_tree} = sub {

        # fetch the org unit tree
        unless($cache{aou_tree}) {
            my $tree = $e->search_actor_org_unit([
			    {   parent_ou => undef},
			    {   flesh            => -1,
				    flesh_fields    => {aou =>  ['children']},
				    order_by        => {aou => 'name'}
			    }
		    ])->[0];

            # flesh the org unit type for each org unit
            # and simultaneously set the id => aou map cache
            sub flesh_aout {
                my $node = shift;
                my $ctx = shift;
                $node->ou_type( $ctx->{find_aout}->($node->ou_type) );
                $cache{map}{aou}{$node->id} = $node;
                flesh_aout($_, $ctx) foreach @{$node->children};
            };
            flesh_aout($tree, $ctx);

            $cache{aou_tree} = $tree;
        }

        return $cache{aou_tree};
    };

    # Add a special handler for the tree-shaped org unit cache
    $ctx->{find_aou} = sub {
        my $org_id = shift;
        $ctx->{aou_tree}->(); # force the org tree to load
        return $cache{map}{aou}{$org_id};
    };

    # turns an ISO date into something TT can understand
    $ctx->{parse_datetime} = sub {
        my $date = shift;
        $date = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($date));
        return sprintf(
            "%0.2d:%0.2d:%0.2d %0.2d-%0.2d-%0.4d",
            $date->hour,
            $date->minute,
            $date->second,
            $date->day,
            $date->month,
            $date->year
        );
    };

    # retrieve and cache org unit setting values
    $ctx->{get_org_setting} = sub {
        my($org_id, $setting) = @_;
        $cache{org_settings}{$org_id} = {} unless $cache{org_settings}{$org_id};
        $cache{org_settings}{$org_id}{$setting} = $U->ou_ancestor_setting_value($org_id, $setting)
            unless exists $cache{org_settings}{$org_id}{$setting};
        return $cache{org_settings}{$org_id}{$setting};
    };
}

# context additions: 
#   authtoken : string
#   user : au object
#   user_status : hash of user circ numbers
sub load_common {
    my $self = shift;

    my $e = $self->editor;
    my $ctx = $self->ctx;

    $ctx->{referer} = $self->cgi->referer;
    $ctx->{path_info} = $self->cgi->path_info;
    $ctx->{opac_root} = $ctx->{base_path} . "/opac"; # absolute base url
    $ctx->{is_staff} = ($self->apache->headers_in->get('User-Agent') =~ 'oils_xulrunner');

    if($e->authtoken($self->cgi->cookie('ses'))) {

        if($e->checkauth) {

            $ctx->{authtoken} = $e->authtoken;
            $ctx->{user} = $e->requestor;
            $ctx->{user_stats} = $U->simplereq(
                'open-ils.actor', 
                'open-ils.actor.user.opac.vital_stats', 
                $e->authtoken, $e->requestor->id);

        } else {

            return $self->load_logout;
        }
    }

    return Apache2::Const::OK;
}

sub load_simple {
    my ($self, $page) = @_;
    $self->ctx->{page} = $page;
    return Apache2::Const::OK;
}


sub load_login {
    my $self = shift;
    my $cgi = $self->cgi;
    my $ctx = $self->ctx;

    $ctx->{page} = 'login';

    my $username = $cgi->param('username');
    my $password = $cgi->param('password');
    my $org_unit = $cgi->param('loc') || $ctx->{aou_tree}->()->id;
    my $persist = $cgi->param('persist');

    # initial log form only
    return Apache2::Const::OK unless $username and $password;

	my $seed = $U->simplereq(
        'open-ils.auth', 
		'open-ils.auth.authenticate.init', $username);

    my $args = {	
        username => $username, 
        password => md5_hex($seed . md5_hex($password)), 
        type => ($persist) ? 'persist' : 'opac' 
    };

    my $bc_regex = $ctx->{get_org_setting}->($org_unit, 'opac.barcode_regex');

    $args->{barcode} = delete $args->{username} 
        if $bc_regex and $username =~ /$bc_regex/;

	my $response = $U->simplereq(
        'open-ils.auth', 'open-ils.auth.authenticate.complete', $args);

    if($U->event_code($response)) { 
        # login failed, report the reason to the template
        $ctx->{login_failed_event} = $response;
        return Apache2::Const::OK;
    }

    # login succeeded, redirect as necessary

    my $home = $self->apache->unparsed_uri;
    $home =~ s/\/login/\/home/;

    $self->apache->print(
        $cgi->redirect(
            -url => $cgi->param('redirect_to') || $home,
            -cookie => $cgi->cookie(
                -name => 'ses',
                -path => '/',
                -secure => 1,
                -value => $response->{payload}->{authtoken},
                -expires => ($persist) ? CORE::time + $response->{payload}->{authtime} : undef
            )
        )
    );

    return Apache2::Const::REDIRECT;
}

sub load_logout {
    my $self = shift;

    my $url = 'http://' . $self->apache->hostname . $self->ctx->{opac_root} . "/home";

    $self->apache->print(
        $self->cgi->redirect(
            -url => $url,
            -cookie => $self->cgi->cookie(
                -name => 'ses',
                -path => '/',
                -value => '',
                -expires => '-1h'
            )
        )
    );

    return Apache2::Const::REDIRECT;
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
    my $query = $cgi->param('query');
    my $limit = $cgi->param('limit') || 10; # TODO user settings

    my $loc = $cgi->param('loc') || $ctx->{aou_tree}->()->id;
    my $depth = defined $cgi->param('depth') ? 
        $cgi->param('depth') : $ctx->{find_aou}->($loc)->ou_type->depth;

    my $args = {limit => $limit, offset => $page * $limit, org_unit => $loc, depth => $depth}; 

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

# context additions: 
#   record : bre object
sub load_record {
    my $self = shift;
    $self->ctx->{page} = 'record';

    my $rec_id = $self->ctx->{page_args}->[0]
        or return Apache2::Const::HTTP_BAD_REQUEST;

    $self->ctx->{record} = $self->editor->retrieve_biblio_record_entry([
        $rec_id,
        {
            flesh => 2, 
            flesh_fields => {
                bre => ['call_numbers'],
                acn => ['copies'] # limit, paging, etc.
            }
        }
    ]);

    $self->ctx->{marc_xml} = XML::LibXML->new->parse_string($self->ctx->{record}->marc);

    return Apache2::Const::OK;
}

# context additions: 
#   user : au object, fleshed
sub load_myopac {
    my $self = shift;
    $self->ctx->{page} = 'myopac';

    $self->ctx->{user} = $self->editor->retrieve_actor_user([
        $self->ctx->{user}->id,
        {
            flesh => 1,
            flesh_fields => {
                au => ['card']
                # ...
            }
        }
    ]);

    return Apache2::Const::OK;
}


sub fetch_user_holds {
    my $self = shift;
    my $hold_ids = shift;
    my $ids_only = shift;
    my $flesh = shift;
    my $limit = shift;
    my $offset = shift;

    my $e = $self->editor;

    my $circ = OpenSRF::AppSession->create('open-ils.circ');

    if(!$hold_ids) {

        $hold_ids = $circ->request(
            'open-ils.circ.holds.id_list.retrieve.authoritative', 
            $e->authtoken, 
            $e->requestor->id
        )->gather(1);
    
        $hold_ids = [ grep { defined $_ } @$hold_ids[$offset..($offset + $limit - 1)] ] if $limit or $offset;
    }


    return $hold_ids if $ids_only or @$hold_ids == 0;

    my $args = {
        suppress_notices => 1,
        suppress_transits => 1,
        suppress_mvr => 1,
        suppress_patron_details => 1,
        include_bre => $flesh ? 1 : 0
    };

    # ----------------------------------------------------------------
    # batch version for testing;  initial test show 40% speed 
    # savings on larger sets (>20) of holds.
    # ----------------------------------------------------------------
    my $batch_size = 8;
    my $batch_idx = 0;
    my $mk_req_batch = sub {
        my @ses;
        my $top_idx = $batch_idx + $batch_size;
        while($batch_idx < $top_idx) {
            my $hold_id = $hold_ids->[$batch_idx++];
            last unless $hold_id;
            my $ses = OpenSRF::AppSession->create('open-ils.circ');
            my $req = $ses->request(
                'open-ils.circ.hold.details.retrieve', 
                $e->authtoken, $hold_id, $args);
            push(@ses, {ses => $ses, req => $req});
        }
        return @ses;
    };

    my $first = 1;
    my @collected;
    my @holds;
    my @ses;
    while(1) {
        @ses = $mk_req_batch->() if $first;
        last if $first and not @ses;
        if(@collected) {
            while(my $blob = pop(@collected)) {
                $blob->{marc_xml} = XML::LibXML->new->parse_string($blob->{hold}->{bre}->marc) if $flesh;
                push(@holds, $blob);
            }
        }
        for my $req_data (@ses) {
            push(@collected, {hold => $req_data->{req}->gather(1)});
            $req_data->{ses}->kill_me;
        }
        @ses = $mk_req_batch->();
        last unless @collected or @ses;
        $first = 0;
    }
    # ----------------------------------------------------------------

=head
    my $req = $circ->request(
        # TODO .authoritative version is chewing up cstores
        # 'open-ils.circ.hold.details.batch.retrieve.authoritative', 
        'open-ils.circ.hold.details.batch.retrieve', 
        $e->authtoken, $hold_ids, $args
    );

    my @holds;
    while(my $resp = $req->recv) {
        my $hold = $resp->content;
        push(@holds, {
            hold => $hold,
            marc_xml => ($flesh) ? XML::LibXML->new->parse_string($hold->{bre}->marc) : undef
        });
    }

    $circ->kill_me;
=cut

    return \@holds;
}

sub handle_hold_update {
    my $self = shift;
    my $action = shift;
    my $e = $self->editor;


    my @hold_ids = $self->cgi->param('hold_id'); # for non-_all actions
    @hold_ids = @{$self->fetch_user_holds(undef, 1)} if $action =~ /_all/;

    my $circ = OpenSRF::AppSession->create('open-ils.circ');

    if($action =~ /cancel/) {

        for my $hold_id (@hold_ids) {
            my $resp = $circ->request(
                'open-ils.circ.hold.cancel', $e->authtoken, $hold_id, 6 )->gather(1); # 6 == patron-cancelled-via-opac
        }

    } else {
        
        my $vlist = [];
        for my $hold_id (@hold_ids) {
            my $vals = {id => $hold_id};

            if($action =~ /activate/) {
                $vals->{frozen} = 'f';
                $vals->{thaw_date} = undef;

            } elsif($action =~ /suspend/) {
                $vals->{frozen} = 't';
                # $vals->{thaw_date} = TODO;
            }
            push(@$vlist, $vals);
        }

        $circ->request('open-ils.circ.hold.update.batch.atomic', $e->authtoken, undef, $vlist)->gather(1);
    }

    $circ->kill_me;
    return undef;
}

sub load_myopac_holds {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    

    my $limit = $self->cgi->param('limit') || 0;
    my $offset = $self->cgi->param('offset') || 0;
    my $action = $self->cgi->param('action') || '';

    $self->handle_hold_update($action) if $action;

    $ctx->{holds} = $self->fetch_user_holds(undef, 0, 1, $limit, $offset);

    return Apache2::Const::OK;
}

sub load_place_hold {
    my $self = shift;
    my $ctx = $self->ctx;
    my $e = $self->editor;
    my $cgi = $self->cgi;
    $self->ctx->{page} = 'place_hold';

    $ctx->{hold_target} = $cgi->param('hold_target');
    $ctx->{hold_type} = $cgi->param('hold_type');
    $ctx->{default_pickup_lib} = $e->requestor->home_ou; # XXX staff

    if($ctx->{hold_type} eq 'T') {
        $ctx->{record} = $e->retrieve_biblio_record_entry($ctx->{hold_target});
    }
    # ...

    $ctx->{marc_xml} = XML::LibXML->new->parse_string($ctx->{record}->marc);

    if(my $pickup_lib = $cgi->param('pickup_lib')) {

        my $args = {
            patronid => $e->requestor->id,
            titleid => $ctx->{hold_target}, # XXX
            pickup_lib => $pickup_lib,
            depth => 0, # XXX
        };

        my $allowed = $U->simplereq(
            'open-ils.circ',
            'open-ils.circ.title_hold.is_possible',
            $e->authtoken, $args
        );

        if($allowed->{success} == 1) {
            my $hold = Fieldmapper::action::hold_request->new;

            $hold->pickup_lib($pickup_lib);
            $hold->requestor($e->requestor->id);
            $hold->usr($e->requestor->id); # XXX staff
            $hold->target($ctx->{hold_target});
            $hold->hold_type($ctx->{hold_type});
            # frozen, expired, etc..

            my $stat = $U->simplereq(
                'open-ils.circ',
                'open-ils.circ.holds.create',
                $e->authtoken, $hold
            );

            if($stat and $stat > 0) {
                # if successful, return the user to the requesting page
                $self->apache->log->info("Redirecting back to " . $cgi->param('redirect_to'));
                $self->apache->print($cgi->redirect(-url => $cgi->param('redirect_to')));
                return Apache2::Const::REDIRECT;

            } else {
                $ctx->{hold_failed} = 1;
            }
        } else { # hold *check* failed
            $ctx->{hold_failed} = 1; # XXX process the events, etc
            $ctx->{hold_failed_event} = $allowed->{last_event};
        }

        # hold permit failed
        $logger->info('hold permit result ' . OpenSRF::Utils::JSON->perl2JSON($allowed));
    }

    return Apache2::Const::OK;
}


sub fetch_user_circs {
    my $self = shift;
    my $flesh = shift; # flesh bib data, etc.
    my $circ_ids = shift;
    my $limit = shift;
    my $offset = shift;

    my $e = $self->editor;

    my @circ_ids;

    if($circ_ids) {
        @circ_ids = @$circ_ids;

    } else {

        my $circ_data = $U->simplereq(
            'open-ils.actor', 
            'open-ils.actor.user.checked_out',
            $e->authtoken, 
            $e->requestor->id
        );

        @circ_ids =  ( @{$circ_data->{overdue}}, @{$circ_data->{out}} );

        if($limit or $offset) {
            @circ_ids = grep { defined $_ } @circ_ids[0..($offset + $limit - 1)];
        }
    }

    return [] unless @circ_ids;

    my $cstore = OpenSRF::AppSession->create('open-ils.cstore');

    my $qflesh = {
        flesh => 3,
        flesh_fields => {
            circ => ['target_copy'],
            acp => ['call_number'],
            acn => ['record']
        }
    };

    $e->xact_begin;
    my $circs = $e->search_action_circulation(
        [{id => \@circ_ids}, ($flesh) ? $qflesh : {}], {substream => 1});

    my @circs;
    for my $circ (@$circs) {
        push(@circs, {
            circ => $circ, 
            marc_xml => ($flesh and $circ->target_copy->call_number->id != -1) ? 
                XML::LibXML->new->parse_string($circ->target_copy->call_number->record->marc) : 
                undef  # pre-cat copy, use the dummy title/author instead
        });
    }
    $e->xact_rollback;

    # make sure the final list is in the correct order
    my @sorted_circs;
    for my $id (@circ_ids) {
        push(
            @sorted_circs,
            (grep { $_->{circ}->id == $id } @circs)
        );
    }

    return \@sorted_circs;
}


sub handle_circ_renew {
    my $self = shift;
    my $action = shift;
    my $ctx = $self->ctx;

    my @renew_ids = $self->cgi->param('circ');

    my $circs = $self->fetch_user_circs(0, ($action eq 'renew') ? [@renew_ids] : undef);

    # TODO: fire off renewal calls in batches to speed things up
    my @responses;
    for my $circ (@$circs) {

        my $evt = $U->simplereq(
            'open-ils.circ', 
            'open-ils.circ.renew',
            $self->editor->authtoken,
            {
                patron_id => $self->editor->requestor->id,
                copy_id => $circ->{circ}->target_copy,
                opac_renewal => 1
            }
        );

        # TODO return these, then insert them into the circ data 
        # blob that is shoved into the template for each circ
        # so the template won't have to match them
        push(@responses, {copy => $circ->{circ}->target_copy, evt => $evt});
    }

    return @responses;
}


sub load_myopac_circs {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    $ctx->{circs} = [];
    my $limit = $self->cgi->param('limit') || 0; # 0 == unlimited
    my $offset = $self->cgi->param('offset') || 0;
    my $action = $self->cgi->param('action') || '';

    # perform the renewal first if necessary
    my @results = $self->handle_circ_renew($action) if $action =~ /renew/;

    $ctx->{circs} = $self->fetch_user_circs(1, undef, $limit, $offset);

    my $success_renewals = 0;
    my $failed_renewals = 0;
    for my $data (@{$ctx->{circs}}) {
        my ($resp) = grep { $_->{copy} == $data->{circ}->target_copy->id } @results;

        if($resp) {
            my $evt = ref($resp->{evt}) eq 'ARRAY' ? $resp->{evt}->[0] : $resp->{evt};
            $data->{renewal_response} = $evt;
            $success_renewals++ if $evt->{textcode} eq 'SUCCESS';
            $failed_renewals++ if $evt->{textcode} ne 'SUCCESS';
        }
    }

    $ctx->{success_renewals} = $success_renewals;
    $ctx->{failed_renewals} = $failed_renewals;

    return Apache2::Const::OK;
}

sub load_myopac_fines {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    $ctx->{"fines"} = {
        "circulation" => [],
        "grocery" => [],
        "total_paid" => 0,
        "total_owed" => 0,
        "balance_owed" => 0
    };

    my $limit = $self->cgi->param('limit') || 0;
    my $offset = $self->cgi->param('offset') || 0;

    my $cstore = OpenSRF::AppSession->create('open-ils.cstore');

    # TODO: This should really be a ML call, but the existing calls 
    # return an excessive amount of data and don't offer streaming

    my %paging = ($limit or $offset) ? (limit => $limit, offset => $offset) : ();

    my $req = $cstore->request(
        'open-ils.cstore.direct.money.open_billable_transaction_summary.search',
        {
            usr => $e->requestor->id,
            balance_owed => {'!=' => 0}
        },
        {
            flesh => 4,
            flesh_fields => {
                mobts => ['circulation', 'grocery'],
                mg => ['billings'],
                mb => ['btype'],
                circ => ['target_copy'],
                acp => ['call_number'],
                acn => ['record']
            },
            order_by => { mobts => 'xact_start' },
            %paging
        }
    );

    while(my $resp = $req->recv) {
        my $mobts = $resp->content;
        my $circ = $mobts->circulation;

        my $last_billing;
        if($mobts->grocery) {
            my @billings = sort { $a->billing_ts cmp $b->billing_ts } @{$mobts->grocery->billings};
            $last_billing = pop(@billings);
        }

        # XXX TODO switch to some money-safe non-fp library for math
        $ctx->{"fines"}->{$_} += $mobts->$_ for (
            qw/total_paid total_owed balance_owed/
        );

        push(
            @{$ctx->{"fines"}->{$mobts->grocery ? "grocery" : "circulation"}},
            {
                xact => $mobts,
                last_grocery_billing => $last_billing,
                marc_xml => ($mobts->xact_type ne 'circulation' or $circ->target_copy->call_number->id == -1) ?
                    undef :
                    XML::LibXML->new->parse_string($circ->target_copy->call_number->record->marc),
            } 
        );
    }

     return Apache2::Const::OK;
}       

sub load_myopac_update_email {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $email = $self->cgi->param('email') || '';

    unless($email =~ /.+\@.+\..+/) { # TODO better regex?
        $ctx->{invalid_email} = $email;
        return Apache2::Const::OK;
    }

    my $stat = $U->simplereq(
        'open-ils.actor', 
        'open-ils.actor.user.email.update', 
        $e->authtoken, $email);

    my $url = $self->apache->unparsed_uri;
    $url =~ s/update_email/main/;
    $self->apache->print($self->cgi->redirect(-url => $url));

    return Apache2::Const::REDIRECT;
}

sub load_myopac_bookbags {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    my $limit = $self->cgi->param('limit') || 0;
    my $offset = $self->cgi->param('offset') || 0;

    my $args = {order_by => {cbreb => 'name'}};
    $args->{limit} = $limit if $limit;
    $args->{offset} = $limit if $limit;

    $ctx->{bookbags} = $e->search_container_biblio_record_entry_bucket([
        {owner => $self->editor->requestor->id, btype => 'bookbag'},
        $args
    ]);

    return Apache2::Const::OK;
}


1;
