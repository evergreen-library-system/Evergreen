package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use CGI;
use XML::LibXML;
use Digest::MD5 qw(md5_hex);
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use DateTime::Format::ISO8601;
my $U = 'OpenILS::Application::AppUtils';

my %cache; # proc-level cache

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

    return $self->load_home if $path =~ /opac\/home/;
    return $self->load_login if $path =~ /opac\/login/;
    return $self->load_logout if $path =~ /opac\/logout/;
    return $self->load_rresults if $path =~ /opac\/results/;
    return $self->load_record if $path =~ /opac\/record/;

    # ----------------------------------------------------------------
    # These pages require authentication
    # ----------------------------------------------------------------
    return Apache2::Const::FORBIDDEN unless $self->cgi->https;
    return $self->load_logout unless $self->editor->requestor;

    return $self->load_place_hold if $path =~ /opac\/place_hold/;
    return $self->load_myopac_holds if $path =~ /opac\/myopac\/holds/;
    return $self->load_myopac_circs if $path =~ /opac\/myopac\/circs/;
    return $self->load_myopac_fines if $path =~ /opac\/myopac\/fines/;
    return $self->load_myopac if $path =~ /opac\/myopac/;
    # ----------------------------------------------------------------

    return Apache2::Const::OK;
}

# general purpose utility functions added to the environment
sub load_helpers {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    $cache{map} = {}; # public object maps
    $cache{list} = {}; # public object lists

    # fetch-on-demand-and-cache subs for commonly used public data
    my @public_classes = qw/ccs aout/;

    for my $hint (@public_classes) {

        my ($class) = grep {
            $Fieldmapper::fieldmap->{$_}->{hint} eq $hint
        } keys %{ $Fieldmapper::fieldmap };

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
    
        $cache{map}{$hint} = {};

        $ctx->{$find_key} = sub {
            my $id = shift;
            return $cache{map}{$hint}{$id} if $cache{map}{$hint}{$id}; 
            ($cache{map}{$hint}{$id}) = grep { $_->id == $id } @{$ctx->{$list_key}->()};
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
    $cache{map}{aou} = {};
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
    }
}

# context additions: 
#   authtoken : string
#   user : au object
#   user_status : hash of user circ numbers
sub load_common {
    my $self = shift;

    my $e = $self->editor;
    my $ctx = $self->ctx;

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

sub load_home {
    my $self = shift;
    $self->ctx->{page} = 'home';
    return Apache2::Const::OK;
}


sub load_login {
    my $self = shift;
    my $cgi = $self->cgi;

    $self->ctx->{page} = 'login';

    my $username = $cgi->param('username');
    my $password = $cgi->param('password');

    return Apache2::Const::OK unless $username and $password;

	my $seed = $U->simplereq(
        'open-ils.auth', 
		'open-ils.auth.authenticate.init',
        $username);

	my $response = $U->simplereq(
        'open-ils.auth', 
		'open-ils.auth.authenticate.complete', 
		{	username => $username, 
			password => md5_hex($seed . md5_hex($password)), 
			type => 'opac' 
        }
    );

    # XXX check event, redirect as necessary

    my $home = $self->apache->unparsed_uri;
    $home =~ s/\/login/\/home/;

    $self->apache->print(
        $cgi->redirect(
            -url => $cgi->param('origin') || $home,
            -cookie => $cgi->cookie(
                -name => 'ses',
                -path => '/',
                -secure => 1,
                -value => $response->{payload}->{authtoken},
                -expires => CORE::time + $response->{payload}->{authtime}
            )
        )
    );

    return Apache2::Const::REDIRECT;
}

sub load_logout {
    my $self = shift;

    my $url = 'http://' . $self->apache->hostname . $self->ctx->{base_path} . "/opac/home";

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
    my $limit = $cgi->param('limit') || 10; # XXX user settings
    my $args = {limit => $limit, offset => $page * $limit}; 
    $query = "$query $facet" if $facet;
    my $results;

    try {
        $results = $U->simplereq(
            'open-ils.search',
            'open-ils.search.biblio.multiclass.query.staff', 
            $args, $query, 1);

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

    unless($cache{cmf}) {
        $cache{cmf} = $e->search_config_metabib_field({id => {'!=' => undef}});
        $ctx->{metabib_field} = $cache{cmf};
        #$cache{cmc} = $e->search_config_metabib_class({name => {'!=' => undef}});
        #$ctx->{metabib_class} = $cache{cmc};
    }

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

    for my $cmf_id (keys %$facets) {  # quick-n-dirty
        my ($cmf) = grep { $_->id eq $cmf_id } @{$cache{cmf}};
        $facets->{$cmf_id} = {cmf => $cmf, data => $facets->{$cmf_id}};
    }
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

sub load_myopac_holds {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;

    my $limit = $self->cgi->param('limit') || 10;
    my $offset = $self->cgi->param('offset') || 0;

    my $circ = OpenSRF::AppSession->create('open-ils.circ');
    my $hold_ids = $circ->request(
        'open-ils.circ.holds.id_list.retrieve', 
        $e->authtoken, 
        $e->requestor->id
    )->gather(1);

    $hold_ids = [ grep { defined $_ } @$hold_ids[$offset..($offset + $limit - 1)] ];

    my $req = $circ->request(
        'open-ils.circ.hold.details.batch.retrieve', 
        $e->authtoken, 
        $hold_ids,
        {
            suppress_notices => 1,
            suppress_transits => 1,
            suppress_mvr => 1,
            suppress_patron_details => 1,
            include_bre => 1
        }
    );

    # any requests we can fire off here?
    
    $ctx->{holds} = []; 
    while(my $resp = $req->recv) {
        my $hold = $resp->content;
        push(@{$ctx->{holds}}, {
            hold => $hold,
            marc_xml => XML::LibXML->new->parse_string($hold->{bre}->marc)
        });
    }

    $circ->kill_me;
    return Apache2::Const::OK;
}

sub load_place_hold {
    my $self = shift;
    my $ctx = $self->ctx;
    my $e = $self->editor;
    $self->ctx->{page} = 'place_hold';

    $ctx->{hold_target} = $self->cgi->param('hold_target');
    $ctx->{hold_type} = $self->cgi->param('hold_type');
    $ctx->{default_pickup_lib} = $e->requestor->home_ou; # XXX staff

    if($ctx->{hold_type} eq 'T') {
        $ctx->{record} = $e->retrieve_biblio_record_entry($ctx->{hold_target});
    }
    # ...

    $ctx->{marc_xml} = XML::LibXML->new->parse_string($ctx->{record}->marc);

    if(my $pickup_lib = $self->cgi->param('pickup_lib')) {

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
                $ctx->{hold_success} = 1;
            } else {
                $ctx->{hold_failed} = 1; # XXX process the events, etc
            }
        }

        # place the hold and deliver results
    }

    return Apache2::Const::OK;
}


sub load_myopac_circs {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    $ctx->{circs} = [];

    my $limit = $self->cgi->param('limit') || 10;
    my $offset = $self->cgi->param('offset') || 0;

    my $circ_data = $U->simplereq(
        'open-ils.actor', 
        'open-ils.actor.user.checked_out',
        $e->authtoken, 
        $e->requestor->id
    );

    my @circ_ids =  ( @{$circ_data->{overdue}}, @{$circ_data->{out}} );
    @circ_ids = grep { defined $_ } @circ_ids[0..($offset + $limit - 1)];

    return Apache2::Const::OK unless @circ_ids;

    my $cstore = OpenSRF::AppSession->create('open-ils.cstore');
    my $req = $cstore->request(
        'open-ils.cstore.direct.action.circulation.search', 
        {id => \@circ_ids},
        {
            flesh => 3,
            flesh_fields => {
                circ => ['target_copy'],
                acp => ['call_number'],
                acn => ['record']
            }
        }
    );

    my @circs;
    while(my $resp = $req->recv) {
        my $circ = $resp->content;
        push(@circs, {
            circ => $circ, 
            marc_xml => ($circ->target_copy->call_number->id == -1) ? 
                undef :  # pre-cat copy, use the dummy title/author instead
                XML::LibXML->new->parse_string($circ->target_copy->call_number->record->marc),
        });
    }

    # make sure the final list is in the correct order
    for my $id (@circ_ids) {
        push(
            @{$ctx->{circs}}, 
            (grep { $_->{circ}->id == $id } @circs)
        );
    }

    return Apache2::Const::OK;
}

sub load_myopac_fines {
    my $self = shift;
    my $e = $self->editor;
    my $ctx = $self->ctx;
    $ctx->{transactions} = [];

    my $limit = $self->cgi->param('limit') || 10;
    my $offset = $self->cgi->param('offset') || 0;

    my $cstore = OpenSRF::AppSession->create('open-ils.cstore');

    # TODO: This should really use a ML call, but the existing calls 
    # return an excessive amount of data and don't offer streaming

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
            limit => $limit,
            offset => $offset
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

        push(
            @{$ctx->{transactions}},
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


1;
