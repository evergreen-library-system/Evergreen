package OpenSRF::System;
use strict; use warnings;
use base 'OpenSRF';
use OpenSRF::Utils::Logger qw(:level);
use OpenSRF::Transport::Listener;
use OpenSRF::Transport;
use OpenSRF::UnixServer;
use OpenSRF::Utils;
use OpenSRF::Utils::LogServer;
use OpenSRF::DOM;
use OpenSRF::EX qw/:try/;
use POSIX ":sys_wait_h";
use OpenSRF::Utils::Config; 
use strict;

=head2 Name/Description

OpenSRF::System

To start the system: OpenSRF::System->bootstrap();

Simple system process management and automation.  After instantiating the class, simply call
bootstrap() to launch the system.  Each launched process is stored as a process-id/method-name
pair in a local hash.  When we receive a SIG{CHILD}, we loop through this hash and relaunch
any child processes that may have terminated.  

Currently automated processes include launching the internal Unix Servers, launching the inbound 
connections for each application, and starting the system shell.


Note: There should be only one instance of this class
alive at any given time.  It is designed as a globel process handler and, hence, will cause much
oddness if you call the bootstrap() method twice or attempt to create two of these by trickery.
There is a single instance of the class created on the first call to new().  This same instance is 
returned on subsequent calls to new().

=cut

$| = 1;

sub APPS { return qw( opac ); } #circ cat storage ); }

sub DESTROY {}

# ----------------------------------------------

$SIG{INT} = sub { instance()->killall(); };

$SIG{HUP} = sub{ instance()->hupall(); };

#$SIG{CHLD} = \&process_automation;


# Go ahead and set the config

set_config();

# ----------------------------------------------
# Set config options
sub set_config {

	my $config = OpenSRF::Utils::Config->load( 
		config_file => "/pines/conf/opensrf.conf" );

	if( ! $config ) { throw OpenSRF::EX::Config "System could not load config"; }

	my $tran = $config->transport->implementation;

	eval "use $tran;";
	if( $@ ) {
		throw OpenSRF::EX::PANIC ("Cannot find transport implementation: $@" );
	}

	OpenSRF::Transport->message_envelope( $tran->get_msg_envelope );
	OpenSRF::Transport::PeerHandle->set_peer_client( $tran->get_peer_client );
	OpenSRF::Transport::Listener->set_listener( $tran->get_listener );


}


# ----------------------------------------------

{ 
	# --- 
	# put $instance in a closure and return it for requests to new()
	# since there should only be one System instance running
	# ----- 
	my $instance;
	sub instance { return __PACKAGE__->new(); }
	sub new {
		my( $class ) = @_;

		if( ! $instance ) {
			$class = ref( $class ) || $class;
			my $self = {};
			$self->{'pid_hash'} = {};
			bless( $self, $class );
			$instance = $self;
		}
		return $instance;
	}
}

# ----------------------------------------------
# Commands to execute at system launch

sub _unixserver {
	my( $app ) = @_;
	return "OpenSRF::UnixServer->new( '$app' )->serve()";
}

sub _listener {
	my( $app ) = @_;
	return "OpenSRF::Transport::Listener->new( '$app' )->initialize()->listen()";
}

#sub _shell { return "OpenSRF::Shell->listen()"; }


# ----------------------------------------------
# Boot up the system

sub bootstrap {

	my $self = __PACKAGE__->instance();

	my $config = OpenSRF::Utils::Config->current;

	my $apps = $config->system->apps;
	my $server_type = $config->system->server_type;
	$server_type ||= "basic";

	if(  $server_type eq "prefork" ) { 
		$server_type = "Net::Server::PreForkSimple"; 
	} else { 
		$server_type = "Net::Server::Single"; 
	}

	_log( " * Server type: $server_type", INTERNAL );

	eval "use $server_type";

	if( $@ ) {
		throw OpenSRF::EX::PANIC ("Cannot set $server_type: $@" );
	}

	push @OpenSRF::UnixServer::ISA, $server_type;

	_log( " * System boostrap" );

	# Start a process group and make me the captain
	setpgrp( 0, 0 ); 

	$0 = "System";
	
	# --- Boot the Unix servers
	$self->launch_unix($apps);

	_sleep();

	# --- Boot the listeners
	$self->launch_listener($apps);

	_sleep();

	# --- Start the system shell
#if ($config->system->shell) {
#		eval " 
#			use OpenSRF::Shell;
#			$self->launch_shell() if ($config->system->shell);
#		";
#
#		if ($@) {
#			warn "ARRRGGG! Can't start the shell...";
#		}
#	}

	# --- Now we wait for our brood to perish
	_log( " * System is ready..." );
	while( 1 ) { sleep; }
	exit;
}



# ----------------------------------------------
# Bootstraps a single client connection.  

sub bootstrap_client {

	my $self = __PACKAGE__->instance();
	my $config = OpenSRF::Utils::Config->current;

	my $client_type = shift;
	my $app;

	if( defined($client_type) and $client_type ) {
		$app = $client_type;
	} else {
		$app = "client";
	}

	OpenSRF::Transport::PeerHandle->construct( $app );

}

sub bootstrap_logger {

	$0 = "Log Server";
	OpenSRF::Utils::LogServer->serve();

}


# ----------------------------------------------
# Cycle through the known processes, reap the dead child 
# and put a new child in its place. (MMWWAHAHHAHAAAA!)

sub process_automation {

	my $self = __PACKAGE__->instance();

	foreach my $pid ( keys %{$self->pid_hash} ) {

		if( waitpid( $pid, WNOHANG ) == $pid ) {

			my $method = $self->pid_hash->{$pid};
			delete $self->pid_hash->{$pid};

			my $newpid =  OpenSRF::Utils::safe_fork();
			_log( "Relaunching => $method" );

			if( $newpid ) {
				$self->pid_hash( $newpid, $method );
			}
			else { $0 = $method; eval $method; exit; }
		}
	}

	$SIG{CHLD} = \&process_automation;
}


# ----------------------------------------------
# Launch the Unix Servers

sub launch_unix {
	my( $self, $apps ) = @_;

	foreach my $app ( @$apps ) {

		_log( " * Starting UnixServer for $app..." );

		my $pid = OpenSRF::Utils::safe_fork();
		if( $pid ) {
			$self->pid_hash( $pid , _unixserver( $app ) );
		}
		else {
			my $apname = $app;
			$apname =~ tr/[a-z]/[A-Z]/;
			$0 = "Unix Server ($apname)";
			eval _unixserver( $app );
			exit;
		}
	}
}

# ----------------------------------------------
# Launch the inbound clients

sub launch_listener {

	my( $self, $apps ) = @_;

	foreach my $app ( @$apps ) {

		_log( " * Starting Listener for $app..." );

		my $pid = OpenSRF::Utils::safe_fork();
		if ( $pid ) {
			$self->pid_hash( $pid , _listener( $app ) );
		}
		else {
			my $apname = $app;
			$apname =~ tr/[a-z]/[A-Z]/;
			$0 = "Listener ($apname)";
			eval _listener( $app );
			exit;
		}
	}
}

# ----------------------------------------------

=head comment
sub launch_shell {

	my $self = shift;

	my $pid = OpenSRF::Utils::safe_fork();

	if( $pid ) { $self->pid_hash( $pid , _shell() ); }
	else {
		$0 = "System Shell";
		for( my $x = 0; $x != 10; $x++ ) {
			eval _shell();
			if( ! $@ ) { last; }
		}
		exit;
	}
}
=cut


# ----------------------------------------------

sub pid_hash {
	my( $self, $pid, $method ) = @_;
	$self->{'pid_hash'}->{$pid} = $method
		if( $pid and $method );
	return $self->{'pid_hash'};
}

# ----------------------------------------------
# If requested, the System can shut down.

sub killall {

	$SIG{CHLD} = 'IGNORE';
	$SIG{INT} = 'IGNORE';
	kill( 'INT', -$$ ); #kill all in process group
	exit;

}

# ----------------------------------------------
# Handle $SIG{HUP}
sub hupall {

	_log( "HUPping brood" );
	$SIG{CHLD} = 'IGNORE';
	$SIG{HUP} = 'IGNORE';
	set_config(); # reload config
	kill( 'HUP', -$$ );
#	$SIG{CHLD} = \&process_automation;
	$SIG{HUP} = sub{ instance()->hupall(); };
}


# ----------------------------------------------
# Log to debug, and stdout

sub _log {
	my $string = shift;
	OpenSRF::Utils::Logger->debug( $string );
	print $string . "\n";
}

# ----------------------------------------------

sub _sleep {
	select( undef, undef, undef, 0.3 );
}

1;


