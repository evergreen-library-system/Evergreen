package OpenILS::Application::Storage;
use OpenSRF::Application;
use base qw/OpenSRF::Application/;

use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::Logger qw/:level/;

# Pull this in so we can adjust it's @ISA
use OpenILS::Application::Storage::CDBI (1);
use OpenILS::Application::Storage::FTS;


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
	if ($@) {
		$log->debug( "Can't load $driver!  :  $@", ERROR );
		$log->error( "Can't load $driver!  :  $@");
		throw OpenILS::EX::PANIC ( "Can't load $driver!  :  $@" );
	}

	$log->debug("$driver loaded successfully", DEBUG);

	# Suck in the method publishing modules
	@OpenILS::Application::Storage::CDBI::ISA = ( $driver );

	eval 'use OpenILS::Application::Storage::Publisher;';
	if ($@) {
		$log->debug("FAILURE LOADING Publisher!  $@", ERROR);
	}
	eval 'use OpenILS::Application::Storage::WORM;';
	if ($@) {
		$log->debug("FAILURE LOADING WORM!  $@", ERROR);
	}
}

sub child_init {

	$log->debug('Running child_init for ' . __PACKAGE__ . '...', DEBUG);

	my $conf = OpenSRF::Utils::SettingsClient->new;

	$log->debug('Calling the Driver child_init', DEBUG);
	OpenILS::Application::Storage::CDBI->child_init(
		$conf->config_value( apps => 'open-ils.storage' => app_settings => databases => 'database')
	);

	if (OpenILS::Application::Storage::CDBI->db_Main()) {
		OpenILS::Application::Storage::WORM->child_init();
		$log->debug("Success initializing driver!", DEBUG);
		return 1;
	}
	$log->debug("FAILURE initializing driver!", ERROR);
	return 0;
}

sub begin_xaction {
	my $self = shift;
	my $client = shift;

	$log->debug(" XACT --> 'BEGIN'ing transaction for session ".$client->session->session_id,DEBUG);
	try {
		OpenILS::Application::Storage::CDBI->db_Main->begin_work;
		$client->session->session_data( xact_id => $client->session->session_id );
	} catch Error with {
		throw OpenSRF::DomainObject::oilsException->new(
			statusCode => 500,
			status => "Could not BEGIN transaction!",
		);
	};
	return 1;

}
__PACKAGE__->register_method(
	method		=> 'begin_xaction',
	api_name	=> 'open-ils.storage.transaction.begin',
	api_level	=> 1,
	argc		=> 0,
);

sub commit_xaction {
	my $self = shift;
	my $client = shift;

	try {
		OpenILS::Application::Storage::CDBI->db_Main->commit;
		$client->session->session_data( xact_id => '' );
	} catch Error with {
		throw OpenSRF::DomainObject::oilsException->new(
			statusCode => 500,
			status => "Could not COMMIT  transaction!",
		);
	};
	return 1;
}
__PACKAGE__->register_method(
	method		=> 'commit_xaction',
	api_name	=> 'open-ils.storage.transaction.commit',
	api_level	=> 1,
	argc		=> 0,
);


sub current_xact {
	my $self = shift;
	my $client = shift;

	return $client->session->session_data( 'xact_id' );
}
__PACKAGE__->register_method(
	method		=> 'current_xact',
	api_name	=> 'open-ils.storage.transaction.current',
	api_level	=> 1,
	argc		=> 0,
);

sub rollback_xaction {
	my $self = shift;
	my $client = shift;

	$log->debug(" XACT --> 'ROLLBACK'ing transaction for session ".$client->session->session_id,DEBUG);
	$client->session->session_data( xact_id => '' );
	return OpenILS::Application::Storage::CDBI->db_Main->rollback;
}
__PACKAGE__->register_method(
	method		=> 'rollback_xaction',
	api_name	=> 'open-ils.storage.transaction.rollback',
	api_level	=> 1,
	argc		=> 0,
);


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
