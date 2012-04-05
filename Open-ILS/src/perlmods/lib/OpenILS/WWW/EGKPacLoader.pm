package OpenILS::WWW::EGKPacLoader;
use base 'OpenILS::WWW::EGCatLoader';
use strict; use warnings;
use XML::Simple;
use Apache2::Const -compile => qw(OK HTTP_BAD_REQUEST);
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
my $U = 'OpenILS::Application::AppUtils';
my $kpac_config;

# -----------------------------------------------------------------------------
# Override our parent's load() sub so we can do kpac-specific path routing.
# -----------------------------------------------------------------------------
sub load {
    my $self = shift;

    $self->init_ro_object_cache; 

    my $stat = $self->load_common; 
    return $stat unless $stat == Apache2::Const::OK;

    $self->load_kpac_config;

    my $path = $self->apache->path_info;
    ($self->ctx->{page} = $path) =~ s#.*/(.*)#$1#g;

    return $self->load_simple("home") if $path =~ m|kpac/home|;
    return $self->load_simple("category") if $path =~ m|kpac/category|;
    return $self->load_rresults if $path =~ m|kpac/results|;
    return $self->load_record(no_search => 1) if $path =~ m|kpac/record|; 

    # ----------------------------------------------------------------
    #  Everything below here requires SSL
    # ----------------------------------------------------------------
    return $self->redirect_ssl unless $self->cgi->https;

    return $self->load_getit_results if $path =~ m|kpac/getit_results|;
    return $self->load_getit if $path =~ m|kpac/getit|;

    # ----------------------------------------------------------------
    #  Everything below here requires authentication
    # ----------------------------------------------------------------
    return $self->redirect_auth unless $self->editor->requestor;

    # AUTH pages

    return Apache2::Const::OK;
}

sub load_getit {
    my $self = shift;
    my $ctx = $self->ctx;
    my $rec_id = $ctx->{page_args}->[0];
    my $bbag_id = $self->cgi->param('bookbag');
    my $action = $self->cgi->param('action') || '';

    # first load the record
    my $stat = $self->load_record(no_search => 1);
    return $stat unless $stat == Apache2::Const::OK;

    $self->ctx->{page} = 'getit'; # repair the page

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

    $self->ctx->{page} = 'getit'; # repair the page
    return Apache2::Const::OK;
}
    
sub login_and_place_hold {
    my $self = shift;
    my $bre_id = shift;
    my $ctx = $self->ctx;
    my $username = $self->cgi->param('username');
    my $password = $self->cgi->param('password');
    my $pickup_lib = $self->cgi->param('pickup_lib');

    if (!$ctx->{user}) {
        # First, log the user in and return to 
        # TODO: let user know username/password is required..
        return Apache2::Const::OK unless $username and $password;
        my $new_uri = $self->apache->unparsed_uri;
        my $sep = ($new_uri =~ /\?/) ? '&' : '?';
        $new_uri .= "${sep}pickup_lib=$pickup_lib&action=hold";
        $self->cgi->param('redirect_to', $new_uri);
        return $self->load_login;
    }

    # TODO: place hold

    my $hold_id = '';
#    (my $new_uri = $self->apache->unparsed_uri) =~ s/getit/getit_results/g;
#    $new_uri .= ($new_uri =~ /\?/) ? "&hold=$hold_id" : "?hold=$hold_id";
#    return $self->generic_redirect($new_uri);

    return Apache2::Const::OK;
}

sub save_item_to_bookbag {
    my $self = shift;
    my $rec_id = shift;
    my $bookbag_id = shift;

    if ($bookbag_id) { 
        # save to existing bookbag
        $self->cgi->param('record', $rec_id);
        my $stat = $self->load_myopac_bookbag_update('add_rec', $bookbag_id);
        # TODO: check for failure
        (my $new_uri = $self->apache->unparsed_uri) =~ s/getit/getit_results/g;
        $new_uri .= ($new_uri =~ /\?/) ? "&list=$bookbag_id" : "?list=$bookbag_id";
        return $self->generic_redirect($new_uri);

    } else { 
        # save to anonymous list
       
        # set some params assumed to exist for load_mylist_add
        $self->cgi->param('record', $rec_id);
        (my $new_uri = $self->apache->unparsed_uri) =~ s/getit/getit_results/g;
        $new_uri .= ($new_uri =~ /\?/) ? '&list=anon' : '?list=anon';
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

    my (undef, @rec_data) = $self->get_records_and_facets([$rec_id]);
    $ctx->{bre_id} = $rec_data[0]->{id};
    $ctx->{marc_xml} = $rec_data[0]->{marc_xml};

    if ($list) {
        if ($list eq 'anon') {
            $ctx->{anon_list} = 1;
        } else {
            $ctx->{list} = $e->retrieve_container_biblio_record_entry_bucket($list);
        }

    } elsif ($hold_id) {

        # new hold means potential for replication lag
        $e->xact_start; 
        # fetch the hold...
        $e->xact_rollback;
    }

    return Apache2::Const::OK;
}

sub load_kpac_config {
    my $self = shift;
    my $ctx = $self->ctx;

    if (!$kpac_config) {
        my $path = $self->apache->dir_config('KPacConfigFile');

        if (!$path) {
            $self->apache->log->error("KPacConfigFile required!");
            return;
        }
        
        $kpac_config = XMLin(
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
        ($layout) = grep {$_->{owner} eq $org->id} @{$kpac_config->{layout}};
        last if $layout;
        $ou = $org->parent_ou;
    }

    $ctx->{kpac_layout} = $layout;
    $ctx->{kpac_config} = $kpac_config;
    $ctx->{kpac_root} = $ctx->{base_path} . "/kpac"; 
    $ctx->{home_page} = 'http://' . $self->apache->hostname . $ctx->{kpac_root} . "/home";
}


1;
