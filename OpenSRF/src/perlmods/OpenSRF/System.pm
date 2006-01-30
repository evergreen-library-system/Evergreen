package OpenSRF::System;
use strict; use warnings;
use OpenSRF;
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
use OpenSRF::Utils::SettingsParser;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Application;
use Net::Server::PreFork;
use strict;

my $bootstrap_config_file;
sub import {
	my( $self, $config ) = @_;
	$bootstrap_config_file = $config;
}

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

sub DESTROY {}

# ----------------------------------------------

$SIG{INT} = sub { instance()->killall(); };

$SIG{HUP} = sub{ instance()->hupall(); };

#$SIG{CHLD} = \&process_automation;


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
	return "OpenSRF::UnixServer->new( '$app')->serve()";
}

sub _listener {
	my( $app ) = @_;
	return "OpenSRF::Transport::Listener->new( '$app' )->initialize()->listen()";
}


# ----------------------------------------------
# Boot up the system

sub load_bootstrap_config {

	if(OpenSRF::Utils::Config->current) {
		return;
	}

	if(!$bootstrap_config_file) {
		die "Please provide a bootstrap config file to OpenSRF::System!\n" . 
			"use OpenSRF::System qw(/path/to/bootstrap_config);";
	}

	OpenSRF::Utils::Config->load( config_file => $bootstrap_config_file );

	JSON->register_class_hint( name => "OpenSRF::Application", hint => "method", type => "hash" );

	OpenSRF::Transport->message_envelope(  "OpenSRF::Transport::SlimJabber::MessageWrapper" );
	OpenSRF::Transport::PeerHandle->set_peer_client(  "OpenSRF::Transport::SlimJabber::PeerConnection" );
	OpenSRF::Transport::Listener->set_listener( "OpenSRF::Transport::SlimJabber::Inbound" );
	OpenSRF::Application->server_class('client');
}

sub bootstrap {

	my $self = __PACKAGE__->instance();
	load_bootstrap_config();
	OpenSRF::Utils::Logger::set_config();
	my $bsconfig = OpenSRF::Utils::Config->current;

	# Start a process group and make me the captain
	setpgrp( 0, 0 ); 
	$0 = "OpenSRF System";

	# -----------------------------------------------
	# Launch the settings sever if necessary...
	my $are_settings_server = 0;
	if( (my $cfile = $bsconfig->bootstrap->settings_config) ) {
		my $parser = OpenSRF::Utils::SettingsParser->new();

		# since we're (probably) the settings server, we can go ahead and load the real config file
		$parser->initialize( $cfile );
		$OpenSRF::Utils::SettingsClient::host_config = 
			$parser->get_server_config($bsconfig->env->hostname);

		my $client = OpenSRF::Utils::SettingsClient->new();
		my $apps = $client->config_value("activeapps", "appname");
		if(ref($apps) ne "ARRAY") { $apps = [$apps]; }

		if(!defined($apps) || @$apps == 0) {
			print "No apps to load, exiting...";
			return;
		}

		for my $app (@$apps) {
			# verify we are a settings server and launch 
			if( $app eq "opensrf.settings" and 
				$client->config_value("apps","opensrf.settings", "language") =~ /perl/i ) {

				$are_settings_server = 1;
				$self->launch_settings();
				sleep 1;
				$self->launch_settings_listener();
				last;
			} 
		}
	}

	# Launch everything else
	OpenSRF::System->bootstrap_client(client_name => "system_client");
	my $client = OpenSRF::Utils::SettingsClient->new();
	my $apps = $client->config_value("activeapps", "appname" );
	if(!ref($apps)) { $apps = [$apps]; }

	if(!defined($apps) || @$apps == 0) {
		print "No apps to load, exiting...";
		return;
	}

	my $server_type = $client->config_value("server_type");
	$server_type ||= "basic";

	my $con = OpenSRF::Transport::PeerHandle->retrieve;
	if($con) {
		$con->disconnect;
	}



	if(  $server_type eq "prefork" ) { 
		$server_type = "Net::Server::PreFork"; 
	} else { 
		$server_type = "Net::Server::Single"; 
	}

	_log( " * Server type: $server_type", INTERNAL );

	$server_type->use;

	if( $@ ) {
		throw OpenSRF::EX::PANIC ("Cannot set $server_type: $@" );
	}

	push @OpenSRF::UnixServer::ISA, $server_type;

	_log( " * System boostrap" );
	
	# --- Boot the Unix servers
	$self->launch_unix($apps);


	_sleep();
	sleep 2;

	# --- Boot the listeners
	$self->launch_listener($apps);

	_sleep();

	_log( " * System is ready..." );

	sleep 1;
	my $ps = `ps ax | grep " Open" | grep -v grep | sort -r -k5`;

	print "\n --- PS --- \n$ps --- PS ---\n\n";

	while( 1 ) { sleep; }
	exit;
}
	
	

# ----------------------------------------------
# Bootstraps a single client connection.  

# named params are 'config_file' and 'client_name'
#
sub bootstrap_client {
	my $self = shift;

	my $con = OpenSRF::Transport::PeerHandle->retrieve;
	if($con and $con->tcp_connected) {
		warn "PeerHandle is already connected in 'bootstrap_client'... returning\n";
		_log( "PeerHandle is already connected in 'bootstrap_client'... returning");
		return;
	}

	my %params = @_;

	$bootstrap_config_file = 
		$params{config_file} || $bootstrap_config_file;

	my $app = $params{client_name} || "client";


	load_bootstrap_config();
	OpenSRF::Utils::Logger::set_config();
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

			OpenSRF::Utils::Logger->debug( "Relaunching $method", ERROR );
			_log( "Relaunching => $method" );

			if( $newpid ) {
				$self->pid_hash( $newpid, $method );
			}
			else { eval $method; exit; }
		}
	}

	$SIG{CHLD} = \&process_automation;
}



sub launch_settings {

	#	XXX the $self like this and pid automation will not work with this setup....
	my($self) = @_;
	@OpenSRF::UnixServer::ISA = qw(OpenSRF Net::Server::PreFork);

	my $pid = OpenSRF::Utils::safe_fork();
	if( $pid ) {
		$self->pid_hash( $pid , "launch_settings()" );
	}
	else {
		my $apname = "opensrf.settings";
		#$0 = "OpenSRF App [$apname]";
		eval _unixserver( $apname );
		if($@) { die "$@\n"; }
		exit;
	}

	@OpenSRF::UnixServer::ISA = qw(OpenSRF);

}


sub launch_settings_listener {

	my $self = shift;
	my $app = "opensrf.settings";
	my $pid = OpenSRF::Utils::safe_fork();
	if ( $pid ) {
		$self->pid_hash( $pid , _listener( $app ) );
	}
	else {
		my $apname = $app;
		$0 = "OpenSRF listener [$apname]";
		eval _listener( $app );
		exit;
	}

}

# ----------------------------------------------
# Launch the Unix Servers

sub launch_unix {
	my( $self, $apps ) = @_;

	my $client = OpenSRF::Utils::SettingsClient->new();

	foreach my $app ( @$apps ) {

		next unless $app;
		my $lang = $client->config_value( "apps", $app, "language");
		next unless $lang =~ /perl/i;
		next if $app eq "opensrf.settings";

		_log( " * Starting UnixServer for $app..." );

		my $pid = OpenSRF::Utils::safe_fork();
		if( $pid ) {
			$self->pid_hash( $pid , _unixserver( $app ) );
		}
		else {
			my $apname = $app;
			$0 = "OpenSRF App ($apname)";
			eval _unixserver( $app );
			exit;
		}
	}
}

# ----------------------------------------------
# Launch the inbound clients

sub launch_listener {

	my( $self, $apps ) = @_;
	my $client = OpenSRF::Utils::SettingsClient->new();

	foreach my $app ( @$apps ) {

		next unless $app;
		my $lang = $client->config_value( "apps", $app, "language");
		next unless $lang =~ /perl/i;
		next if $app eq "opensrf.settings";

		_log( " * Starting Listener for $app..." );

		my $pid = OpenSRF::Utils::safe_fork();
		if ( $pid ) {
			$self->pid_hash( $pid , _listener( $app ) );
		}
		else {
			my $apname = $app;
			$0 = "OpenSRF listener [$apname]";
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
	OpenSRF::Utils::Logger->debug( $string, INFO );
	#print $string . "\n";
}

# ----------------------------------------------

sub _sleep {
	select( undef, undef, undef, 0.3 );
}

1;


