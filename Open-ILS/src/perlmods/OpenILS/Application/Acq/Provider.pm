package OpenILS::Application::Acq::Provider;
use base qw/OpenILS::Application::Acq/;
use strict; use warnings;

use OpenILS::Event;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;

my $U = 'OpenILS::Application::AppUtils';
my $BAD_PARAMS = OpenILS::Event->new('BAD_PARAMS');


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
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('CREATE_PROVIDER', $provider->owner);
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
    return $e->event unless $e->allowed('VIEW_PROVIDER', $provider->owner);
    return $provider;
}



