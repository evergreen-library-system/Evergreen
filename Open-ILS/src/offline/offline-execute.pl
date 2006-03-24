#!/usr/bin/perl
use strict; use warnings;

# --------------------------------------------------------------------
# Loads the offline script files for a given org, sorts and runs the 
# scripts, and returns the exception list
# --------------------------------------------------------------------

our ($REQUESTOR, $META_FILE, $LOCK_FILE, $AUTHTOKEN, $U, %config, $cgi, $base_dir, $logger, $ORG);
my @data;
require 'offline-lib.pl';

my $evt = $U->check_perms($REQUESTOR->id, $ORG, 'OFFLINE_EXECUTE');
handle_event($evt) if $evt;

my $resp = &process_data( &sort_data( &collect_data() ) );
&archive_files();
handle_event(OpenILS::Event->new('SUCCESS', payload => $resp));



# --------------------------------------------------------------------
# Collects all of the script logs into an in-memory structure that
# can be sorted, etc.
# Returns a blob like -> { $ws1 => [ commands... ], $ws2 => [ commands... ] }
# --------------------------------------------------------------------
sub collect_data {

	handle_event(OpenILS::Event->new('OFFLINE_PARAM_ERROR')) unless $ORG;
	my $dir = get_pending_dir();
	handle_event(OpenILS::Event->new('OFFLINE_SESSION_ACTIVE')) if (-e "$dir/$LOCK_FILE");

	# Lock the pending directory
	system(("touch",  "$dir/$LOCK_FILE")) == 0 
		or handle_event(OpenILS::Event->new('OFFLINE_FILE_ERROR'));

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
	my $meta = read_meta();
	
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
	my @resp;

	for my $d (@$data) {
		my $t = $d->{type};

		push( @resp, {command => $d, event => handle_checkin($d)})	if( $t eq 'checkin' );
		push( @resp, {command => $d, event => handle_inhouse($d)})	if( $t eq 'in_house_use' );
		push( @resp, {command => $d, event => handle_checkout($d)})	if( $t eq 'checkout' );
		push( @resp, {command => $d, event => handle_renew($d)})		if( $t eq 'renew' );
		push( @resp, {command => $d, event => handle_register($d)})	if( $t eq 'register' );
	}
	return \@resp;
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

	$logger->activity("offline: checkin : requestor=". $REQUESTOR->id.
		", realtime=$realtime, ".  "workstation=$ws, barcode=$barcode, backdate=$backdate");

	return $U->simplereq(
		'open-ils.circ', 
		'open-ils.circ.checkin', $AUTHTOKEN,
		{ barcode => $barcode, backdate => $backdate } );
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

	$logger->activity("offline: in_house_use : requestor=". $REQUESTOR->id.
		", realtime=$realtime, ".  "workstation=$ws, barcode=$barcode, count=$count");

	my( $copy, $evt ) = $U->fetch_copy_by_barcode($barcode);
	return $evt if $evt;

	my $ids = $U->simplereq(
		'open-ils.circ', 
		'open-ils.circ.in_house_use.create', $AUTHTOKEN,
		{ copyid => $copy->id, count => $count, location =>  $ORG} );
	
	return OpenILS::Event->new('SUCCESS', payload => $ids) if( ref($ids) eq 'ARRAY' );
	return $ids;
}



sub handle_checkout {
	my $command = shift;
	return OpenILS::Event->new('SUCCESS', payload => $command);
}


sub handle_renew {
	my $command = shift;
	return OpenILS::Event->new('SUCCESS', payload => $command);
}


sub handle_register {
	my $command = shift;
	return OpenILS::Event->new('SUCCESS', payload => $command);
}



# --------------------------------------------------------------------
# Removes the log file and Moves the script files from the pending 
# directory to the archive dir
# --------------------------------------------------------------------
sub archive_files {
	my $archivedir = create_archive_dir();
	my $pendingdir = get_pending_dir();
	my @files = <$pendingdir/*.log>;
	push(@files, <$pendingdir/$META_FILE>);

	$logger->debug("offline: Archiving files to $archivedir...");
	system( ("rm", "$pendingdir/$LOCK_FILE") ) == 0 
		or handle_event(OpenILS::Event->new('OFFLINE_FILE_ERROR'));

	return unless (<$pendingdir/*>);

	for my $f (@files) {
		system( ("mv", "$f", "$archivedir") ) == 0 
			or handle_event(OpenILS::Event->new('OFFLINE_FILE_ERROR'));
	}

	system( ("rmdir", "$pendingdir") ) == 0 
		or handle_event(OpenILS::Event->new('OFFLINE_FILE_ERROR'));
}


