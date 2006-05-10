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

our $WRITE = 0;
our $IGNORE_XACT_ID_FAILURE = 1;

sub DESTROY {};

sub initialize {

	my $conf = OpenSRF::Utils::SettingsClient->new;

	$log->debug('Initializing ' . __PACKAGE__ . '...', DEBUG);

	my $driver = "OpenILS::Application::Storage::Driver::".
		$conf->config_value( apps => 'open-ils.storage' => app_settings => databases => 'driver');


	$log->debug("Attempting to load $driver ...", DEBUG);

	$driver->use;
	if ($@) {
		$log->debug( "Can't load $driver!  :  $@", ERROR );
		$log->error( "Can't load $driver!  :  $@");
		throw OpenSRF::EX::PANIC ( "Can't load $driver!  :  $@" );
	}

	$log->debug("$driver loaded successfully", DEBUG);

	# Suck in the method publishing modules
	@OpenILS::Application::Storage::CDBI::ISA = ( $driver );

	OpenILS::Application::Storage::Publisher->use;
	if ($@) {
		$log->debug("FAILURE LOADING Publisher!  $@", ERROR);
		throw OpenSRF::EX::PANIC ( "FAILURE LOADING Publisher!  :  $@" );
	}

	OpenILS::Application::WoRM->use;
	if ($@) {
		$log->debug("FAILURE LOADING WORM!  $@", ERROR);
		throw OpenSRF::EX::PANIC ( "FAILURE LOADING WoRM!  :  $@" );
	}

	$log->debug("We seem to be OK...",DEBUG);
}

sub child_init {

	$log->debug('Running child_init for ' . __PACKAGE__ . '...', DEBUG);

	my $conf = OpenSRF::Utils::SettingsClient->new;

	$log->debug('Calling the Driver child_init', DEBUG);
	OpenILS::Application::Storage::CDBI->child_init(
		$conf->config_value( apps => 'open-ils.storage' => app_settings => databases => 'database')
	);

	if (OpenILS::Application::Storage::CDBI->db_Main()) {
		#OpenILS::Application::Storage::WORM->child_init();
		OpenILS::Application::WoRM->child_init();
		$log->debug("Success initializing driver!", DEBUG);
		return 1;
	}
	$log->debug("FAILURE initializing driver!", ERROR);
	return 0;
}

sub begin_xaction {
	my $self = shift;
	my $client = shift;

	local $WRITE = 1;

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

sub savepoint_placeholder {
	return 1;
}
__PACKAGE__->register_method(
	method		=> 'savepoint_placeholder',
	api_name	=> 'open-ils.storage.savepoint.set',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'savepoint_placeholder',
	api_name	=> 'open-ils.storage.savepoint.release',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'savepoint_placeholder',
	api_name	=> 'open-ils.storage.savepoint.rollback',
	api_level	=> 1,
	argc		=> 1,
);

sub commit_xaction {
	my $self = shift;
	my $client = shift;

	local $WRITE = 1;

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

	local $WRITE = 1;

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
