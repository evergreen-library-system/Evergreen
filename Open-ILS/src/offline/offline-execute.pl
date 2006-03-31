#!/usr/bin/perl
use strict; use warnings;
use Time::HiRes;
use OpenSRF::Transport::PeerHandle;
use OpenSRF::System;
use OpenSRF::EX qw/:try/;

our $U;
our $logger;

require 'offline-lib.pl';

$SIG{CHLD} = 'IGNORE'; # - we don't care what happens to our child process

&execute();


# --------------------------------------------------------------------
# Loads the offline script files for a given org, sorts and runs the 
# scripts, and returns the exception list
# --------------------------------------------------------------------
sub execute {

	# --------------------------------------------------------------------
	# Make sure the caller has the right permissions
	# --------------------------------------------------------------------
	my $evt = $U->check_perms(&offline_requestor->id, &offline_org, 'OFFLINE_EXECUTE');
	handle_event($evt) if $evt;
	
	
	# --------------------------------------------------------------------
	# First make sure the data is there and in a good state
	# --------------------------------------------------------------------
	my $data = &sort_data( &collect_data );
	
	
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
		handle_event(OpenILS::Event->new('SUCCESS')); # - this exits

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
		my %config = &offline_config;
		OpenSRF::System->bootstrap_client(config_file => $config{bootstrap});
	
		try {
			&process_data( $data );
			&archive_files;
		} catch Error with {
			my $e = shift;
			$logger->error("offline: child process error $e");
		}
	}
}



# --------------------------------------------------------------------
# Collects all of the script logs into an in-memory structure that
# can be sorted, etc.
# Returns a blob like -> { $ws1 => [ commands... ], $ws2 => [ commands... ] }
# --------------------------------------------------------------------
sub collect_data {

	my $dir	= &offline_pending_dir;
	my $lock = &offline_lock_file;

	handle_event(OpenILS::Event->new('OFFLINE_SESSION_NOT_FOUND')) unless  -e $dir;
	handle_event(OpenILS::Event->new('OFFLINE_PARAM_ERROR')) unless &offline_org;
	handle_event(OpenILS::Event->new('OFFLINE_SESSION_ACTIVE')) if ( -e $lock );

	# - create the lock file
	qx/touch $lock/;

	my $file;
	my %data;

	# Load the data from the list of files
	while( ($file = <$dir/*.log>) ) {
		$logger->debug("offline: Loading script file $file");
		open(F, $file) or handle_event(
			OpenILS::Event->new('OFFLINE_FILE_ERROR'));
		my $ws = log_to_wsname($file);
		$data{$ws} = [];
		push(@{$data{$ws}}, , <F>);
	}

	return \%data;
}


# --------------------------------------------------------------------
# Sorts the commands
# --------------------------------------------------------------------
sub sort_data {
	my $data = shift;
	my @parsed;

	$logger->debug("offline: Sorting data");
	my $meta = &offline_read_meta;
	shift @$meta;
	
	# cycle through the workstations
	for my $ws (keys %$data) {

		# find the meta line for this ws.
		my ($m) = grep { $_->{workstation} eq $ws } @$meta;
		
		$logger->debug("offline: Sorting workstations $ws with a time delta of ".$m->{delta});

		my @scripts = @{$$data{$ws}};

		# cycle through the scripts for the current workstation
		for my $s (@scripts) {
			my $command = JSON->JSON2perl($s);
			$command->{_workstation} = $ws;
			$command->{_realtime} = $command->{timestamp} + $m->{delta};
			$logger->debug("offline: setting realtime to ".
				$command->{_realtime} . " from timestamp " . $command->{timestamp});
			push( @parsed, $command );

		}
	}

	@parsed = sort { $a->{_realtime} <=> $b->{_realtime} } @parsed;
	return \@parsed;
}


# --------------------------------------------------------------------
# Runs the commands and returns the list of errors
# --------------------------------------------------------------------
sub process_data {
	my $data = shift;

	for my $d (@$data) {

		my $t = $d->{type};
		next unless $t;

		append_result( {command => $d, event => handle_checkin($d)})	if $t eq 'checkin';
		append_result( {command => $d, event => handle_inhouse($d)})	if $t eq 'in_house_use';
		append_result( {command => $d, event => handle_checkout($d)})	if $t eq 'checkout';
		append_result( {command => $d, event => handle_renew($d)})		if $t eq 'renew';
		append_result( {command => $d, event => handle_register($d)})	if $t eq 'register';

	}
}



# --------------------------------------------------------------------
# Runs an in_house_use action
# --------------------------------------------------------------------
sub handle_inhouse {

	my $command		= shift;
	my $realtime	= $command->{_realtime};
	my $ws			= $command->{_workstation};
	my $barcode		= $command->{barcode};
	my $count		= $command->{count} || 1;
	my $use_time	= $command->{use_time} || "";

	$logger->activity("offline: in_house_use : requestor=". &offline_requestor->id.", realtime=$realtime, ".  
		"workstation=$ws, barcode=$barcode, count=$count, use_time=$use_time");

	my $ids = $U->simplereq(
		'open-ils.circ', 
		'open-ils.circ.in_house_use.create', &offline_authtoken, 
		{ barcode => $barcode, count => $count, location => &offline_org, use_time => $use_time } );
	
	return OpenILS::Event->new('SUCCESS', payload => $ids) if( ref($ids) eq 'ARRAY' );
	return $ids;
}



# --------------------------------------------------------------------
# Pulls the relevant circ args from the command, fetches data where 
# necessary
# --------------------------------------------------------------------
sub circ_args_from_command {
	my $command = shift;

	my $type			= $command->{type};
	my $realtime	= $command->{_realtime};
	my $ws			= $command->{_workstation};
	my $barcode		= $command->{barcode} || "";
	my $cotime		= $command->{checkout_time} || "";
	my $pbc			= $command->{patron_barcode};
	my $due_date	= $command->{due_date} || "";
	my $noncat		= ($command->{noncat}) ? "yes" : "no"; # for logging

	$logger->activity("offline: $type : requestor=". &offline_requestor->id.
		", realtime=$realtime, workstation=$ws, checkout_time=$cotime, ".
		"patron=$pbc, due_date=$due_date, noncat=$noncat");

	my $args = { 
		permit_override	=> 1, 
		barcode				=> $barcode,		
		checkout_time		=> $cotime, 
		patron_barcode		=> $pbc,
		due_date				=> $due_date };

	if( $command->{noncat} ) {
		$args->{noncat} = 1;
		$args->{noncat_type} = $command->{noncat_type};
		$args->{noncat_count} = $command->{noncat_count};
	}

	return $args;
}



# --------------------------------------------------------------------
# Performs a checkout action
# --------------------------------------------------------------------
sub handle_checkout {
	my $command	= shift;
	my $args = circ_args_from_command($command);
	return $U->simplereq(
		'open-ils.circ', 'open-ils.circ.checkout', &offline_authtoken, $args );
}


# --------------------------------------------------------------------
# Performs the renewal action
# --------------------------------------------------------------------
sub handle_renew {
	my $command = shift;
	my $args = circ_args_from_command($command);
	my $t = time;
	return $U->simplereq(
		'open-ils.circ', 'open-ils.circ.renew', &offline_authtoken, $args );
}


# --------------------------------------------------------------------
# Runs a checkin action
# --------------------------------------------------------------------
sub handle_checkin {

	my $command		= shift;
	my $realtime	= $command->{_realtime};
	my $ws			= $command->{_workstation};
	my $barcode		= $command->{barcode};
	my $backdate	= $command->{backdate} || "";

	$logger->activity("offline: checkin : requestor=". &offline_requestor()->id.
		", realtime=$realtime, ".  "workstation=$ws, barcode=$barcode, backdate=$backdate");

	return $U->simplereq(
		'open-ils.circ', 
		'open-ils.circ.checkin', &offline_authtoken,
		{ barcode => $barcode, backdate => $backdate } );
}



# --------------------------------------------------------------------
# Registers a new patron
# --------------------------------------------------------------------
sub handle_register {
	my $command = shift;

	my $barcode = $command->{user}->{card}->{barcode};
	delete $command->{user}->{card}; 

	$logger->info("offline: creating new user with barcode $barcode");

	# now, create the user
	my $actor	= Fieldmapper::actor::user->new;
	my $card		= Fieldmapper::actor::card->new;


	# username defaults to the barcode
	$actor->usrname( ($actor->usrname) ? $actor->usrname : $barcode );

	# Set up all of the virtual IDs, isnew, etc.
	$actor->isnew(1);
	$actor->id(-1);
	$actor->card(-1);
	$actor->cards([$card]);

	$card->isnew(1);
	$card->id(-1);
	$card->usr(-1);
	$card->barcode($barcode);

	my $billing_address;
	my $mailing_address;

	my @sresp;
	for my $resp (@{$command->{user}->{survey_responses}}) {
		my $sr = Fieldmapper::action::survey_response->new;
		$sr->$_( $resp->{$_} ) for keys %$resp;
		$sr->isnew(1);
		$sr->usr(-1);
		push(@sresp, $sr);
		$logger->debug("offline: created new survey response for survey ".$sr->survey);
	}
	delete $command->{user}->{survey_responses};
	$actor->survey_responses(\@sresp) if @sresp;

	# extract the billing address
	if( my $addr = $command->{user}->{billing_address} ) {
		$billing_address = Fieldmapper::actor::user_address->new;
		$billing_address->$_($addr->{$_}) for keys %$addr;
		$billing_address->isnew(1);
		$billing_address->id(-1);
		$billing_address->usr(-1);
		delete $command->{user}->{billing_address};
		$logger->debug("offline: read billing address ".$billing_address->street1);
	}

	# extract the mailing address
	if( my $addr = $command->{user}->{mailing_address} ) {
		$mailing_address = Fieldmapper::actor::user_address->new;
		$mailing_address->$_($addr->{$_}) for keys %$addr;
		$mailing_address->isnew(1);
		$mailing_address->id(-2);
		$mailing_address->usr(-1);
		delete $command->{user}->{mailing_address};
		$logger->debug("offline: read mailing address ".$mailing_address->street1);
	}

	# make sure we have values for both
	$billing_address ||= $mailing_address;
	$mailing_address ||= $billing_address;

	$actor->billing_address($billing_address->id);
	$actor->mailing_address($mailing_address->id);
	$actor->addresses([$mailing_address]);

	push( @{$actor->addresses}, $billing_address ) 
		unless $billing_address->id eq $mailing_address->id;
	
	# pull all of the rest of the data from the command blob
	$actor->$_( $command->{user}->{$_} ) for keys %{$command->{user}};

	$logger->debug("offline: creating user object...");
	$actor = $U->simplereq(
		'open-ils.actor', 
		'open-ils.actor.patron.update', &offline_authtoken, $actor);

	return $actor if(ref($actor) eq 'HASH'); # an event occurred

	return OpenILS::Event->new('SUCCESS', payload => $actor);
}




# --------------------------------------------------------------------
# Removes the log file and Moves the script files from the pending 
# directory to the archive dir
# --------------------------------------------------------------------
sub archive_files {
	my $archivedir = &offline_archive_dir(1);
	my $pendingdir = &offline_pending_dir;

	my @files = <$pendingdir/*.log>;
	push(@files, &offline_meta_file);
	push(@files, &offline_result_file);

	$logger->debug("offline: Archiving files [@files] to $archivedir...");

	my $lock = &offline_lock_file;
	qx/rm $lock/ and handle_event(OpenILS::Event->new('OFFLINE_FILE_ERROR'), 1);

	return unless (<$pendingdir/*>);

	for my $f (@files) {
		qx/mv $f $archivedir/ and handle_event(OpenILS::Event->new('OFFLINE_FILE_ERROR'), 1);
	}

	qx/rmdir $pendingdir/ and handle_event(OpenILS::Event->new('OFFLINE_FILE_ERROR'), 1);

	(my $parentdir = $pendingdir) =~ s#^(/.*)/\w+/?$#$1#og; # - grab the parent dir
	qx/rmdir $parentdir/ unless <$parentdir/*>; # - remove the parent if empty
}



