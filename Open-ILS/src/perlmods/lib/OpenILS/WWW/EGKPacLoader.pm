package OpenILS::WWW::EGKPacLoader;
use base 'OpenILS::WWW::EGCatLoader';
use strict; use warnings;
use XML::Simple;
use Apache2::Const -compile => qw(OK DECLINED FORBIDDEN HTTP_INTERNAL_SERVER_ERROR REDIRECT HTTP_BAD_REQUEST);
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

    return $self->load_simple("getit_results") if $path =~ m|kpac/getit_results|;
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

    # if the user is logged in, fetch his bookbags
    if ($ctx->{user}) {
        $ctx->{bookbags} = $self->editor->search_container_biblio_record_entry_bucket(
            [{
                    owner => $ctx->{user}->id, 
                    btype => 'bookbag'
                }, {
                    order_by => {cbreb => 'name'},
                    limit => $self->cgi->param('bbag_limit') || 100,
            }],
        );
    }

    $self->ctx->{page} = 'getit'; # repair the page
    return Apache2::Const::OK;
}

sub save_item_to_bookbag {
    my $self = shift;
    my $rec_id = shift;
    my $bookbag_id = shift;

    if ($bookbag_id) { 
        # save to existing bookbag

    } else { 
        # save to anonymous list
       
        # set some params assumed to exist for load_mylist_add
        $self->cgi->param('record', $rec_id);
        (my $new_uri = $self->apache->unparsed_uri) =~ s/getit/getit_results/g;
        $self->cgi->param('redirect_to', $new_uri);

        $self->load_mylist_add;
    }

    return Apache2::Const::OK;
}

sub load_kpac_config {
    my $self = shift;

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

    my $ou = $self->ctx->{physical_loc} || $self->_get_search_lib;
    my $layout;

    # Search up the org tree to find the nearest config for the context org unit
    while (my $org = $self->ctx->{get_aou}->($ou)) {
        ($layout) = grep {$_->{owner} eq $org->id} @{$kpac_config->{layout}};
        last if $layout;
        $ou = $org->parent_ou;
    }

    $self->ctx->{kpac_layout} = $layout;
    $self->ctx->{kpac_config} = $kpac_config;
    $self->ctx->{kpac_root} = $self->ctx->{base_path} . "/kpac"; 
}


1;
