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

	# Load the data from the files
	my $file;
	my %data;

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

		$logger->debug("offline: sorting scripts for WS $ws");

		# find the meta line for this ws.
		my ($m) = grep { $_->{'workstaion'} eq $ws } @$meta;

		my @scripts = @{$$data{$ws}};

		# cycle through the scripts for the current workstation
		for my $s (@scripts) {
			my $command = JSON->JSON2perl($s);
			$command->{_workstation} = $ws;
			$command->{_realtime} = $command->{timestamp} + $m->{delta};
			push( @parsed, $command );

		}
	}

	return \@parsed;
}


# --------------------------------------------------------------------
# Runs the commands and returns the list of errors
# --------------------------------------------------------------------
sub process_data {
	my $data = shift;
	my $resp = [];
	for my $d (@$data) {
		$logger->activity("offline: Executing command ".Dumper($d));
	}
	return $resp;
}

# --------------------------------------------------------------------
# Moves the script files from the pending directory to the archive dir
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


