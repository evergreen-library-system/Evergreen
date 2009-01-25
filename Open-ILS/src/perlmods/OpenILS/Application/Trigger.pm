package OpenILS::Application::Trigger;
use OpenILS::Application;
use base qw/OpenILS::Application/;

use OpenSRF::EX qw/:try/;

use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:level/;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Trigger::Event;


my $log = 'OpenSRF::Utils::Logger';

sub initialize {}
sub child_init {}

1;
