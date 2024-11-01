package OpenILS::WWW::EGKPacLoader;
use base 'OpenILS::WWW::EGCatLoader';
use strict; use warnings;
use XML::Simple;
use Apache2::Const -compile => qw(OK HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
my $U = 'OpenILS::Application::AppUtils';
my %kpac_config;

# -----------------------------------------------------------------------------
# Override our parent's load() sub so we can do kpac-specific path routing.
# -----------------------------------------------------------------------------
sub load {
    my $self = shift;

    $self->init_ro_object_cache; 

    my $stat = $self->load_common; 
    return $stat unless $stat == Apache2::Const::OK;

    $self->load_kpac_config;
    $self->load_kpac_categories;

    my $path = $self->apache->path_info;
    ($self->ctx->{page} = $path) =~ s#.*/(.*)#$1#g;

    return $self->load_simple("home") if $path =~ m|kpac/home|;
    return $self->load_simple("css") if $path =~ m|kpac/css|;
    return $self->load_simple("category") if $path =~ m|kpac/category|;
    return $self->load_simple("dewey") if $path =~ m|kpac/dewey|;
    return $self->load_kpac_rresults if $path =~ m|kpac/results|;
    return $self->load_record(no_search => 1) if $path =~ m|kpac/record|; 
    return $self->load_library if $path =~ m|kpac/library|;

    # ----------------------------------------------------------------
    #  Everything below here requires SSL
    # ----------------------------------------------------------------
    return $self->redirect_ssl unless $self->cgi->https;

    #logic added to resolve path-matching conflict
    if ($path =~ m|kpac/getit_results|) {
        return $self->load_getit_results;
    } elsif ($path =~ m|kpac/getit|) {
        return $self->load_getit;
    }
    
    if ($path =~ m|kpac/list_results|) {
        return $self->load_getit_results;
    } elsif ($path =~ m|kpac/list|) {
        return $self->load_getit;
    }

    # ----------------------------------------------------------------
    #  Everything below here requires authentication
    # ----------------------------------------------------------------
    return $self->redirect_auth unless $self->editor->requestor;

    # AUTH pages

    return Apache2::Const::OK;
}

sub load_kpac_rresults {
    my $self = shift;

    # The redirect-to-record-details-on-single-hit logic
    # leverages the opac_root to determine the record detail
    # page.  Replace it temporarily for our purposes.
    my $tpac_root = $self->ctx->{opac_root};
    $self->ctx->{opac_root} = $self->ctx->{kpac_root};

    my $stat = $self->load_rresults;
    $self->ctx->{opac_root} = $tpac_root;

    return $stat;
}

sub load_getit {
    my $self = shift;
    my $ctx = $self->ctx;
    my $rec_id = $ctx->{page_args}->[0];
    my $bbag_id = $self->cgi->param('bookbag');
    my $action = $self->cgi->param('action') || '';
    my $path = $self->apache->path_info;
  
    # first load the record
    my $stat = $self->load_record(no_search => 1);
    return $stat unless $stat == Apache2::Const::OK;
  
    # repair the page
    if ($path =~ m|kpac/getit|) {
        $self->ctx->{page} = 'getit';
    } elsif ($path =~ m|kpac/list|) {
        $self->ctx->{page} = 'list';
    }

    return $self->save_item_to_bookbag($rec_id, $bbag_id) if $action eq 'save';
    return $self->login_and_place_hold($rec_id) if $action eq 'hold';

    # if the user is logged in, fetch his bookbags
    if ($ctx->{user}) {
        $ctx->{bookbags} = $self->editor->search_container_biblio_record_entry_bucket([
            {   owner => $ctx->{user}->id, 
                btype => 'bookbag' 
            }, 
            {   order_by => {cbreb => 'name'},
                limit => $self->cgi->param('bbag_limit') || 100 
            }
        ]);
    }

    # If user is logged in, get default hold pickup and notification info 
    if ($ctx->{user}) {
        my $set_map = $self->ctx->{user_setting_map};
        if ($$set_map{'opac.default_pickup_location'}) {
            $ctx->{default_pickup_lib} = $$set_map{'opac.default_pickup_location'};
        }
        if ($$set_map{'opac.default_phone'}) {
            $ctx->{default_phone} = $$set_map{'opac.default_phone'};
        }
        if ($$set_map{'opac.hold_notify'}) {
            $ctx->{notify_method} = $$set_map{'opac.hold_notify'};
        }
    }

    # $self->ctx->{page} = 'getit'; # repair the page
    return Apache2::Const::OK;
}
    
sub login_and_place_hold {
    my $self = shift;
    my $bre_id = shift;
    my $ctx = $self->ctx;
    my $username = $self->cgi->param('username');
    my $password = $self->cgi->param('password');
    my $pickup_lib = $self->cgi->param('pickup_lib');

    return Apache2::Const::HTTP_BAD_REQUEST 
        unless $pickup_lib =~ /^\d+$/;

    #If a pickup library hasn't been selected, reload page
    if ($pickup_lib == '0') {
        return $self->load_login;
    }

    my $new_uri = $self->apache->unparsed_uri;
    my $sep = ($new_uri =~ /\?/) ? '&' : '?';

    if (!$ctx->{user}) {
        # First, log the user in and return to 
        $self->apache->log->info("kpac: logging in $username");

        # TODO: let user know username/password is required..
        return Apache2::Const::OK unless $username and $password;

        $new_uri .= "${sep}pickup_lib=$pickup_lib&action=hold";
        $self->cgi->param('redirect_to', $new_uri);
        return $self->load_login;

    } else {

        $self->apache->log->info("kpac: placing hold for $bre_id");

        $new_uri =~ s/getit/getit_results/g;
        $self->cgi->param('hold_target', $bre_id);
        $self->cgi->param('hold_type', 'T');
        $self->cgi->param('part', ''); # needed even if unused

        my $stat = $self->load_place_hold;

        $self->apache->log->info("kpac: place hold returned $stat");

        return $stat unless $stat == Apache2::Const::OK;

        my $hdata = $ctx->{hold_data}->[0]; # only 1 hold placed
        if (my $hold_id = $hdata ? $hdata->{hold_success} : undef) {

            $self->apache->log->info("kpac: place hold succeeded");
            $new_uri .= "${sep}hold=$hold_id";

        } else {
            $self->apache->log->info("kpac: place hold failed : " . $ctx->{hold_failed_event});
            $new_uri .= "${sep}hold_failed=1";
        }
    }

    $self->apache->log->info("kpac: place hold redirecting to: $new_uri");
    return $self->generic_redirect($new_uri);
}

sub save_item_to_bookbag {
    my $self = shift;
    my $ctx = $self->ctx;
    my $username = $self->cgi->param('username');
    my $password = $self->cgi->param('password');
    my $rec_id = shift;
    my $bookbag_id = shift;
    
    if (!$ctx->{user}) {
        return Apache2::Const::OK unless $username and $password;
        return $self->load_login;
    }

    if ($bookbag_id) { 
        # save to existing bookbag
        $self->cgi->param('record', $rec_id);
        my $stat = $self->load_myopac_bookbag_update('add_rec', $bookbag_id);
        # TODO: check for failure
        (my $new_uri = $self->apache->unparsed_uri) =~ s/list/list_results/g;
        $new_uri .= ($new_uri =~ /\?/) ? "&list=$bookbag_id&listsuccess=1" : "?list=$bookbag_id&listsuccess=1";
        return $self->generic_redirect($new_uri);

    } else { 
        # save to anonymous list
       
        # set some params assumed to exist for load_mylist_add
        $self->cgi->param('record', $rec_id);
        (my $new_uri = $self->apache->unparsed_uri) =~ s/list/list_results/g;
        $new_uri .= ($new_uri =~ /\?/) ? '&list=anon&listsuccess=1' : '?list=anon&listsuccess=1';
        $self->cgi->param('redirect_to', $new_uri);

        return $self->load_mylist_add;
    }

    return Apache2::Const::HTTP_BAD_REQUEST;
}


sub load_getit_results {
    my $self = shift;
    my $ctx = $self->ctx;
    my $e = $self->editor;
    my $list = $self->cgi->param('list');
    my $hold_id = $self->cgi->param('hold');
    my $rec_id = $ctx->{page_args}->[0];

    my (undef, @rec_data) = $self->get_records_and_facets([$rec_id], undef, 
                {flesh => '{mra,holdings_xml,acp,exclude_invisible_acn}'});
    $ctx->{bre_id} = $rec_data[0]->{id};
    $ctx->{marc_xml} = $rec_data[0]->{marc_xml};

    if ($list) {
        if ($list eq 'anon') {
            $ctx->{added_to_anon} = 1;
        } else {
            $ctx->{added_to_list} = $e->retrieve_container_biblio_record_entry_bucket($list);
        }
    } else { 
        $e->xact_begin;
        $ctx->{hold} = $e->retrieve_action_hold_request($hold_id);
        $e->rollback;
    }

    return Apache2::Const::OK;
}

sub load_kpac_config {
    my $self = shift;
    my $ctx = $self->ctx;

    my $path = $self->apache->dir_config('KPacConfigFile');

    if (!$path) {
        $self->apache->log->error("KPacConfigFile required!");
        return;
    }

    if (!$kpac_config{$path}) {
    
        $kpac_config{$path} = XMLin(
            $path,
            KeyAttr => ['id'],
            ForceArray => ['layout', 'page', 'cell'],
            NormaliseSpace => 2
        );
    }

    my $ou = $ctx->{physical_loc} || $self->_get_search_lib;
    my $layout;

    # Search up the org tree to find the nearest config for the context org unit
    while (my $org = $ctx->{get_aou}->($ou)) {
        ($layout) = grep {$_->{owner} eq $org->id} @{$kpac_config{$path}->{layout}};
        last if $layout;
        $ou = $org->parent_ou;
    }

    $ctx->{kpac_layout} = $layout;
    $ctx->{kpac_config} = $kpac_config{$path};
    $ctx->{kpac_root} = $ctx->{base_path} . "/kpac"; 
    $ctx->{home_page} = $ctx->{proto} . '://' . $ctx->{hostname} . $ctx->{kpac_root} . "/home";

    #Replace audn config from kpac.xml.example to new org unit setting
    #$ctx->{global_search_filter} = $kpac_config{$path}->{global_filter};
    my $audn_filter = $ctx->{get_org_setting}->($ou, 'opac.kpac_audn_filter') || 'a,b,c,j';
    $ctx->{global_search_filter} = "audience(" . $audn_filter . ")";
}

sub load_kpac_categories {
    my $self = shift;
    my $ctx = $self->ctx;

    my $categories = $self->editor->search_config_kpac_topics([
        {active => t},
        {order_by => {kt => 'topic_order'}}
    ]);

    $ctx->{categories} = $categories;

    return Apache2::Const::OK;
} 

1;
