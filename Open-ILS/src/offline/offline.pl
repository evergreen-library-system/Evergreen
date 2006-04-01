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
my $SCRIPT = "OpenILS::Utils::OfflineStore::Script";

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

	my $s = "";
	$s .= "$_=" . $cgi->param($_) . "\n" for $cgi->param;
	warn '-'x60 ."\n$s\n" . '-'x60 ."\n";

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
		$org = $wsobj->owning_lib if $wsobj;
		$org = $requestor->ws_ou unless $org;
		ol_handle_result(OpenILS::Event->new('OFFLINE_NO_ORG')) unless $org;
	}
}


# --------------------------------------------------------------------
# Runs the requested action
# --------------------------------------------------------------------
sub ol_do_action {

	my $payload;

	if( $action eq 'create' ) {
		
		$evt = $U->check_perms($requestor->id, $org, 'OFFLINE_UPLOAD');
		ol_handle_result($evt) if $evt;
		$payload = ol_create_session();

	} elsif( $action eq 'load' ) {

		$evt = $U->check_perms($requestor->id, $org, 'OFFLINE_UPLOAD');
		ol_handle_result($evt) if $evt;
		$payload = ol_load();

	} elsif( $action eq 'execute' ) {

		$evt = $U->check_perms($requestor->id, $org, 'OFFLINE_EXECUTE');
		ol_handle_result($evt) if $evt;
		$payload = ol_execute();

	} elsif( $action eq 'status' ) {

		$evt = $U->check_perms($requestor->id, $org, 'OFFLINE_VIEW');
		ol_handle_result($evt) if $evt;
		$payload = ol_status();
	}

	ol_handle_event('SUCCESS', payload => $payload );
}


# --------------------------------------------------------------------
# Creates a new session
# --------------------------------------------------------------------
sub ol_create_session {

	my $desc = $cgi->param('desc') || "";
	$seskey ||=  time . "_${$}_" . int(rand() * 100);

	$logger->debug("offline: user ".$requestor->id.
		" creating new session with key $seskey and description $desc");

	$SES->create(
		{	
			key			=> $seskey,
			org			=> $org,
			description => $desc,
			creator		=> $requestor->id,
			create_time => CORE::time(), 
		} 
	);

	return $seskey;
}


# --------------------------------------------------------------------
# Holds the meta-info for a script file
# --------------------------------------------------------------------
sub ol_create_script {
	my $count = shift;

	my $session = ol_find_session($seskey);
	my $delta = $cgi->param('delta') || 0;

	my $script = $session->add_to_scripts( 
		{
			requestor	=> $requestor->id,
			create_time	=> CORE::time,
			workstation	=> $wsname,
			logfile		=> "$basedir/pending/$org/$seskey/$wsname.log",
			time_delta	=> $delta,
			count			=> $count,
		}
	);
}

# --------------------------------------------------------------------
# Finds the current session in the db
# --------------------------------------------------------------------
sub ol_find_session {
	my $ses = $SES->retrieve($seskey);
	ol_handle_event('OFFLINE_INVALID_SESSION', payload => $seskey) unless $ses;
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
	my $outdir = "$basedir/pending/$org/$seskey";
	my $outfile = "$outdir/$wsname.log";

	ol_handl_event('OFFLINE_SESSION_FILE_EXISTS') if ol_find_script();
	ol_handle_event('OFFLINE_SESSION_ACTIVE') if $session->in_process;

	qx/mkdir -p $outdir/;
	my $x = 0;
	open(FILE, ">>$outfile") or ol_handle_event('OFFLINE_FILE_ERROR');
	while( <$handle> ) { print FILE; $x++;}
	close(FILE);

	ol_create_script($x);

	return undef;
}


# --------------------------------------------------------------------
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

# --------------------------------------------------------------------
sub ol_handle_event {
	my( $evt, @args ) = @_;
	ol_handle_result(OpenILS::Event->new($evt, @args));
}


# --------------------------------------------------------------------
sub ol_flesh_session {
	my $session = shift;
	my %data;

	map { $data{$_} = $session->$_ } $session->columns;
	$data{scripts} = [];

	for my $script ($session->scripts) {
		my %sdata;
		map { $sdata{$_} = $script->$_ } $script->columns;

		# the client doesn't need this info
		delete $sdata{session};
		delete $sdata{id};
		delete $sdata{logfile};

		push( @{$data{scripts}}, \%sdata );
	}

	return \%data;
}


# --------------------------------------------------------------------
# Returns various information on the sessions and scripts
# --------------------------------------------------------------------
sub ol_status {

	my $type = $cgi->param('status_type') || "scripts";

	if( $type eq 'scripts' ) {
		my $session = ol_find_session();
		ol_handle_result(ol_flesh_session($session));

	} elsif( $type eq 'sessions' ) {
		my @sessions = $SES->search( org => $org );

		# can I do this in the DB without raw SQL?
		@sessions = sort { $a->create_time <=> $b->create_time } @sessions; 
		my @data;
		push( @data, ol_flesh_session($_) ) for @sessions;
		ol_handle_result(\@data);
	}
}


sub ol_fetch_workstation {
	my $name = shift;
	$logger->debug("offline: Fetching workstation $name");
	my $ws = $U->storagereq(
		'open-ils.storage.direct.actor.workstation.search.name', $name);
	ol_handle_result(OpenILS::Event->new('WORKSTATION_NOT_FOUND')) unless $ws;
	return $ws;
}




# --------------------------------------------------------------------
# Sorts the script commands then forks a child to executes them.
# --------------------------------------------------------------------
sub ol_execute {

	my $commands = ol_collect_commands();
	
	# --------------------------------------------------------------------
	# Note that we must disconnect from opensrf before forking or the 
	# connection will be borked...
	# --------------------------------------------------------------------
	my $con = OpenSRF::Transport::PeerHandle->retrieve;
	$con->disconnect if $con;


	if( safe_fork() ) {

		# --------------------------------------------------------------------
		# Tell the client all is well
		# --------------------------------------------------------------------
		ol_handle_event('SUCCESS'); # - this exits

	} else {

		# --------------------------------------------------------------------
		# close stdout/stderr or apache will wait on the child to finish
		# --------------------------------------------------------------------
		close(STDOUT);
		close(STDERR);

		$logger->debug("offline: child $$ processing data...");

		# --------------------------------------------------------------------
		# The child re-connects to the opensrf network and processes
		# the script requests 
		# --------------------------------------------------------------------
		OpenSRF::System->bootstrap_client(config_file => $config{bootstrap});
	
		try {
			ol_process_commands( $commands );
			ol_archive_files();

		} catch Error with {
			my $e = shift;
			$logger->error("offline: child process error $e");
		};
	}
}

sub ol_file_to_perl {
	my $fname = shift;
	open(F, "$fname") or ol_handle_event('OFFLINE_FILE_ERROR');
	my @d = <F>;
	my @p;
	push(@p, JSON->JSON2perl($_)) for @d;
	close(F);
	return \@p;
}

# collects the commands and sorts them on timestamp+delta
sub ol_collect_commands {
	my $ses = ol_find_session();
	my @commands;

	# cycle through every script loaded to this session
	for my $script ($ses->scripts) {
		my $coms = ol_file_to_perl($script->logfile);

		# cycle through all of the commands for this script
		for my $com (@$coms) {
			$$com{_worksation} = $script->workstation;
			$$com{_realtime} = $script->time_delta + $com->{timestamp};
			push( @commands, $com );
		}
	}

	# sort on realtime
	@commands = sort { $a->{_realtime} <=> $b->{_realtime} } @commands;
	return \@commands;
}

sub ol_process_commands {
	my $commands = shift;
	$logger->debug("offline: command = " . JSON->perl2JSON($_)) for @$commands;
}

sub ol_archive_files {
}





