#!/usr/bin/perl
use strict; use warnings;
use DBI;
use CGI;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
use OpenSRF::EX qw/:try/;
use JSON;
use Data::Dumper;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::Utils qw/:daemon/;
use OpenILS::Utils::OfflineStore;
$DBI::trace = 1;

my $U = "OpenILS::Application::AppUtils";
my $DB = "OpenILS::Utils::OfflineStore";
my $SES = "${DB}::Session";
my $SCRIPT = "${SES}::Scrtip";

our %config;

# --------------------------------------------------------------------
# Load the config
# --------------------------------------------------------------------
#do '##CONFIG##/upload-server.pl';
do 'offline-config.pl';


my $cgi			= new CGI;
my $basedir		= $config{base_dir};
my $wsname		= $cgi->param('ws');
my $org			= $cgi->param('org');
my $authtoken	= $cgi->param('ses') || "";
my $seskey		= $cgi->param('seskey');
my $action		= $cgi->param('action'); # - create, load, execute, status
my $requestor; 
my $wsobj;
my $orgobj;
my $evt;


&ol_init;
&ol_runtime_init;
&ol_do_action;


# --------------------------------------------------------------------
# Set it all up
# This function should behave as a child_init might behave in case 
# this is moved to mod_perl
# --------------------------------------------------------------------
sub ol_init {

	$DB->DBFile($config{db});
	OpenSRF::System->bootstrap_client(config_file => $config{bootstrap} ); 
}


# --------------------------------------------------------------------
# Finds the requestor and other info specific to this request
# --------------------------------------------------------------------
sub ol_runtime_init {

	# fetch the requestor object
	($requestor, $evt) = $U->checkses($authtoken);
	ol_handle_result($evt) if $evt;


	# try the param, the workstation, and finally the user's ws org
	if(!$org) { 
		$wsobj = ol_fetch_workstation($wsname);
		$org = $wsobj->ws_ou if $wsobj;
		$org = $requestor->ws_ou unless $org;
		ol_handle_result(OpenILS::Event->new('OFFLINE_NO_ORG')) unless $org;
	}
}


# --------------------------------------------------------------------
# Runs the requested action
# --------------------------------------------------------------------
sub ol_do_action {

	if( $action eq 'create' ) {
		
		$evt = $U->check_perms($requestor, $org, 'OFFLINE_UPLOAD');
		ol_handle_result($evt) if $evt;
		ol_create_session();

	} elsif( $action eq 'load' ) {

		$evt = $U->check_perms($requestor, $org, 'OFFLINE_UPLOAD');
		ol_handle_result($evt) if $evt;
		ol_load();

	} elsif( $action eq 'execute' ) {

		$evt = $U->check_perms($requestor, $org, 'OFFLINE_EXECUTE');
		ol_handle_result($evt) if $evt;
		ol_execute();

	} elsif( $action eq 'status' ) {

		$evt = $U->check_perms($requestor, $org, 'OFFLINE_VIEW');
		ol_handle_result($evt) if $evt;
		ol_status();
	}
}


# --------------------------------------------------------------------
# Creates a new session
# --------------------------------------------------------------------
sub ol_create_session {

	my $desc = $cgi->param('desc') || "";
	$seskey ||=  time . "_${$}_" . rand();

	$logger->offline("offline: user ".$requestor->id.
		" creating new session with key $seskey and description $desc");

	$SES->create(
		{	
			key			=> $seskey,
			org			=> $org,
			description => $desc,
			creator		=> $requestor->id,
			create_time => CORE::time(), 
			complete		=> 0,
		} 
	);
	ol_handle_event('SUCCESS', payload => $seskey );
}


# --------------------------------------------------------------------
# Holds the meta-info for a script file
# --------------------------------------------------------------------
sub ol_create_script {
	my $ws = shift || $wsname;
	my $sk = shift || $seskey;

	my $session = ol_find_sesion($sk);
	my $delta = $cgi->param('delta') || 0;

	my $script = $session->add_to_scripts(
		session		=> $sk,
		requestor	=> $requestor->id,
		timestamp	=> CORE::time,
		workstation	=> $ws,
		logfile		=> "$basedir/pending/$sk/$ws.log",
		time_delta	=> $delta,
	);
}

# --------------------------------------------------------------------
# Finds the current session in the db
# --------------------------------------------------------------------
sub ol_find_session {
	my $sk = shift || $seskey;
	my $ses = $SES->retrieve($seskey);
	ol_handle_event('OFFLINE_INVALID_SESSION', $seskey) unless $ses;
	return $ses;
}

# --------------------------------------------------------------------
# Finds a script object in the DB based on workstation and seskey
# --------------------------------------------------------------------
sub ol_find_script {
	my $ws = shift || $wsname;
	my $sk = shift || $seskey;
	my ($script) = $SCRIPT->search( session => $seskey, workstation => $ws );
	return $script;
}


# --------------------------------------------------------------------
# Creates a new script in the database and loads the new script file
# --------------------------------------------------------------------
sub ol_load {
	my $session = ol_find_session;
	my $handle	= $cgi->upload('file');
	my $outfile = "$basedir/pending/$seskey/$wsname.log";

	ol_handl_event('OFFLINE_SESSION_FILE_EXISTS') if ol_find_script();
	ol_handle_event('OFFLINE_SESSION_ACTIVE') if $session->in_process;

	open(FILE, ">>$outfile") or ol_handle_event('OFFLINE_FILE_ERROR');
	while( <$handle> ) { print FILE; }
	close(FILE);

	ol_create_script();
}


sub ol_handle_result {
	my $obj = shift;
	my $json = JSON->perl2JSON($obj);

	if( $cgi->param('html')) {
		my $html = "<html><body onload='xulG.handle_event($json)></body></html>";
		print "content-type: text/html\n\n";
		print "$html\n";

	} else {

		print "content-type: text/plain\n\n";
		print "$json\n";
	}

	exit(0);
}

sub ol_handle_event {
	my( $evt, @args ) = @_;
	ol_handle_result(OpenILS::Event->new($evt, @args));
}

sub ol_status {
	my $session = ol_find_session();
	my $scripts = $session->retrieve_all;

	my %data;

	map { $data{$_} = $session->$_ } $session->columns;
	$data{scripts} = [];

	for my $script ($scripts->columns) {
		my %sdata;
		map { $sdata{$_} = $script->$_ } $script->columns;
		push( @{$data{scripts}}, \%sdata );
	}

	my $type = $cgi->param('status_type');

	ol_handle_result(\%data) if( ! $type || $type eq 'scripts' ) 
}


sub ol_fetch_workstation {
	my $name = shift;
	$logger->debug("offline: Fetching workstation $name");
	my $ws = $U->storagereq(
		'open-ils.storage.direct.actor.workstation.search.name', $name);
	ol_handle_result(OpenILS::Event->new('WORKSTATION_NOT_FOUND')) unless $ws;
	return $ws;
}


