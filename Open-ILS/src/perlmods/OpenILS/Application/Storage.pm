package OpenILS::Application::Storage;
use OpenSRF::Application;
use base qw/OpenSRF::Application/;

use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw/:level/;

# Pull this in so we can adjust it's @ISA
use OpenILS::Application::Storage::CDBI;

use OpenILS::Application::Storage::FTS;

# Suck in the method publishing modules
use OpenILS::Application::Storage::Publisher;

# the easy way to get to the logger...
my $log = "OpenSRF::Utils::Logger";

sub DESTROY {};

sub initialize {

	my $conf = OpenSRF::Utils::SettingsClient->new;

	$log->debug('Initializing ' . __PACKAGE__ . '...', DEBUG);

	my $driver = "OpenILS::Application::Storage::Driver::".
		$conf->config_value( apps => 'open-ils.storage' => app_settings => databases => 'driver');


	$log->debug("Attempting to load $driver ...", DEBUG);

	eval "use $driver;";
	throw OpenILS::EX::PANIC ( "Can't load $driver!  :  $@" ) if ($@);

	$log->debug("$driver loaded successfully", DEBUG);

	@OpenILS::Application::Storage::CDBI::ISA = ( $driver );
}

sub child_init {

	my $conf = OpenSRF::Utils::SettingsClient->new;

	$log->debug('Running child_init for ' . __PACKAGE__ . '...', DEBUG);

	OpenILS::Application::Storage::CDBI->child_init(
		$conf->config_value( apps => 'open-ils.storage' => app_settings => databases => 'database')
	);
	
	return 1 if (OpenILS::Application::Storage::CDBI->db_Main());
	return 0;
}


sub _cdbi2Hash {
	my $self = shift;
	my $obj = shift;
	return { map { ( $_ => $obj->$_ ) } ($obj->columns('All')) };
}

sub _cdbi_list2AoH {
	my $self = shift;
	my @objs = @_;
	return [ map { $self->_cdbi2Hash($_) } @objs ];
}

1;
