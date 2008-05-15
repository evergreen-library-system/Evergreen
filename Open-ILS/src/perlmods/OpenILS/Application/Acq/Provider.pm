package OpenILS::Application::Acq::Provider;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenILS::Event;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;

my $U = 'OpenILS::Application::AppUtils';

__PACKAGE__->register_method(
	method => 'create_provider',
	api_name	=> 'open-ils.acq.provider.create',
	signature => {
        desc => 'Creates a new provider',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'provider object to create', type => 'object'}
        ],
        return => {desc => 'The ID of the new provider'}
    }
);

sub create_provider {
    my($self, $conn, $auth, $provider) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('ADMIN_PROVIDER', $provider->owner);
    $e->create_acq_provider($provider) or return $e->die_event;
    $e->commit;
    return $provider->id;
}



__PACKAGE__->register_method(
	method => 'retrieve_provider',
	api_name	=> 'open-ils.acq.provider.retrieve',
	signature => {
        desc => 'Retrieves a new provider',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'provider ID', type => 'number'}
        ],
        return => {desc => 'The provider object on success, Event on failure'}
    }
);

sub retrieve_provider {
    my($self, $conn, $auth, $provider_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $provider = $e->retrieve_acq_provider($provider_id) or return $e->event;
    return $e->event unless $e->allowed(
        ['ADMIN_PROVIDER', 'MANAGE_PROVIDER', 'VIEW_PROVIDER'], $provider->owner, $provider);
    return $provider;
}


__PACKAGE__->register_method(
	method => 'retrieve_org_providers',
	api_name	=> 'open-ils.acq.provider.org.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves all the providers associated with an org unit that the requestor has access to see',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'List of org Unit IDs.  If no IDs are provided, this method returns the 
                full set of funding sources this user has permission to view', type => 'number'},
            {desc => q/Limiting permission.  this permission is used find the work-org tree from which  
                the list of orgs is generated if no org ids are provided.  
                The default is ADMIN_PROVIDER/, type => 'string'},
        ],
        return => {desc => 'The provider objects on success, empty array otherwise'}
    }
);

sub retrieve_org_providers {
    my($self, $conn, $auth, $org_id_list, $options) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    my $limit_perm = ($$options{limit_perm}) ? $$options{limit_perm} : 'ADMIN_PROVIDER';

    return OpenILS::Event->new('BAD_PARAMS')
        unless $limit_perm =~ /(ADMIN|MANAGE|VIEW)_PROVIDER/;

    my $org_ids = ($org_id_list and @$org_id_list) ? $org_id_list :
        $U->find_highest_work_orgs($e, $limit_perm, {descendants =>1});

    return [] unless @$org_ids;
    $conn->respond($_) for @{$e->search_acq_provider({owner => $org_ids})};

    return undef;
}

__PACKAGE__->register_method(
	method => 'retrieve_provider_attr_def',
	api_name	=> 'open-ils.acq.lineitem_provider_attr_definition.provider.retrieve',
    stream => 1,
	signature => {
        desc => 'Retrieves all of the lineitem_provider_attr_definition for a given provider',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Provider ID', type => 'number'}
        ],
        return => {desc => 'Streams a of lineitem_provider_attr_definition objects'}
    }
);

sub retrieve_provider_attr_def {
    my($self, $conn, $auth, $prov_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $provider = $e->retrieve_acq_provider($prov_id)
        or return $e->event;
    return $e->event unless $e->allowed('ADMIN_PROVIDER', $provider->owner);
    for my $id (@{$e->search_acq_lineitem_provider_attr_definition({provider=>$prov_id},{idlist=>1})}) {
        $conn->respond($e->retrieve_acq_lineitem_provider_attr_definition($id));
    }

    return undef;
}

__PACKAGE__->register_method(
	method => 'create_provider_attr_def',
	api_name	=> 'open-ils.acq.lineitem_provider_attr_definition.create',
	signature => {
        desc => 'Retrieves all of the lineitem_provider_attr_definition for a given provider',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Provider ID', type => 'number'}
        ],
        return => {desc => 'Streams a of lineitem_provider_attr_definition objects'}
    }
);

sub create_provider_attr_def {
    my($self, $conn, $auth, $attr_def) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    my $provider = $e->retrieve_acq_provider($attr_def->provider)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('ADMIN_PROVIDER', $provider->owner);
    $e->create_acq_lineitem_provider_attr_definition($attr_def)
        or return $e->die_event;
    $e->commit;
    return $attr_def->id;
}

__PACKAGE__->register_method(
	method => 'delete_provider_attr_def',
	api_name	=> 'open-ils.acq.lineitem_provider_attr_definition.delete',
	signature => {
        desc => 'Deletes a lineitem_provider_attr_definition',
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'ID', type => 'number'}
        ],
        return => {desc => '1 on success, event on failure'}
    }
);

sub delete_provider_attr_def {
    my($self, $conn, $auth, $id) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    my $attr_def = $e->retrieve_acq_lineitem_provider_attr_definition($id)
        or return $e->die_event;
    my $provider = $e->retrieve_acq_provider($attr_def->provider)
        or return $e->die_event;
    return $e->die_event unless $e->allowed('ADMIN_PROVIDER', $provider->owner);
    $e->delete_acq_lineitem_provider_attr_definition($attr_def)
        or return $e->die_event;
    $e->commit;
    return 1;
}

1;
