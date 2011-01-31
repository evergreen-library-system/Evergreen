package OpenILS::Perm;
use strict; use warnings;
use Template;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::EX qw(:try);
use OpenSRF::AppSession;
use OpenSRF::Utils::Logger;

# ----------------------------------------------------------------------------------
# These permission strings
# ----------------------------------------------------------------------------------

# returns a new fieldmapper::perm_ex
my $logger = 'OpenSRF::Utils::Logger';

sub new {
	my($class, $type) = @_;
	$logger->warn("Returning permission error: $type");
	return bless( { ilsevent => 5000, ilsperm => $type }, 'OpenILS::Perm');
}

1;
