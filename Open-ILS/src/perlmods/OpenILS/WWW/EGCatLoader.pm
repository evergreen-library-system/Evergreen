package OpenILS::WWW::EGCatLoader;
use strict; use warnings;
use CGI;
use XML::LibXML;
use Digest::MD5 qw(md5_hex);
use Apache2::Const -compile => qw(OK DECLINED HTTP_INTERNAL_SERVER_ERROR REDIRECT);
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
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

# runtime context
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

    my $path = $self->apache->path_info;
    $self->load_helpers;

    my $stat = $self->load_common;
    return $stat unless $stat == Apache2::Const::OK;

    return $self->load_home if $path =~ /opac\/home/;
    return $self->load_login if $path =~ /opac\/login/;
    return $self->load_logout if $path =~ /opac\/logout/;
    return $self->load_rresults if $path =~ /opac\/results/;
    return $self->load_rdetail if $path =~ /opac\/rdetail/;
    return $self->load_myopac if $path =~ /opac\/myopac/;
    return $self->load_place_hold if $path =~ /opac\/place_hold/;

    return Apache2::Const::OK;
}

# general purpose utility functions added to the environment
# context additions: 
#   find_org_unit : function(id) => aou object
#   org_tree : function(id) => aou object, top of tree, fleshed
sub load_helpers {
    my $self = shift;
    $cache{org_unit_map} = {};

    # pull the org unit from the cached org tree
    $self->ctx->{find_org_unit} = sub {
        my $org_id = shift;
        return undef unless defined $org_id;
        return $cache{org_unit_map}{$org_id} if defined $cache{org_unit_map}{$org_id};
        my $tree = shift || $self->ctx->{org_tree}->();
        return $cache{org_unit_map}{$org_id} = $tree if $tree->id == $org_id;
        for my $child (@{$tree->children}) {
            my $node = $self->ctx->{find_org_unit}->($org_id, $child);
            return $node if $node;
        }
        return undef;
    };

    $self->ctx->{org_tree} = sub {
        unless($cache{org_tree}) {
            $cache{org_tree} = $self->editor->search_actor_org_unit([
			    {   parent_ou => undef},
			    {   flesh            => -1,
				    flesh_fields    => {aou =>  ['children', 'ou_type']},
				    order_by        => {aou => 'name'}
			    }
		    ])->[0];
        }
        return $cache{org_tree};
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

    my $path = $self->apache->uri;
    $path =~ s/(\/[^\/]+$)/\/home/;
    my $url = 'http://' . $self->apache->hostname . "$path";

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
    my $query = $cgi->param('query');
    my $limit = $cgi->param('limit') || 10; # XXX user settings
    my $args = {limit => $limit, offset => $page * $limit}; 
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
        $cache{cmc} = $e->search_config_metabib_class({name => {'!=' => undef}});
        $ctx->{metabib_field} = $cache{cmf};
        $ctx->{metabib_class} = $cache{cmc};
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
        $facets->{$cmf->label} = $facets->{$cmf_id};
        delete $facets->{$cmf_id};
    }
    $ctx->{search_facets} = $facets;

    return Apache2::Const::OK;
}

# context additions: 
#   record : bre object
sub load_rdetail {
    my $self = shift;

    $self->ctx->{record} = $self->editor->retrieve_biblio_record_entry([
        $self->cgi->param('record'),
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

# context additions: 
sub load_place_hold {
    my $self = shift;
    my $ctx = $self->ctx;
    my $e = $self->editor;

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

1;
