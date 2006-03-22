#!/usr/bin/perl
use strict; use warnings;

# --------------------------------------------------------------------
# Loads the offline script files for a given org, sorts and runs the 
# scripts, and returns the exception list
# --------------------------------------------------------------------

our $U;
our %config;
our $cgi;
our $base_dir;
our $logger;
my @data;
require 'offline-lib.pl';

my $org	= $cgi->param('org');
my $resp = &process_data( &sort_data( &collect_data() ) );
&archive_files();
handle_success("Scripts for org $org processed successfully <br/>" . JSON->perl2JSON($resp) );



# --------------------------------------------------------------------
# Collects all of the script logs into an in-memory structure that
# can be sorted, etc.
# --------------------------------------------------------------------
sub collect_data {

	handle_error("Org is not defined") unless $org;
	my $dir = get_pending_dir($org);
	handle_error("Batch from org $org is already in process") if (-e "$dir/lock");

	# Lock the pending directory
	system(("touch",  "$dir/lock")) == 0 or handle_error("Unable to create lock file");

	# Load the data from the files
	my $file;
	my @data;

	while( ($file = <$dir/*.log>) ) {
		$logger->debug("offline: Loading script file $file");
		open(F, $file) or handle_error("Unable to open script file $file");
		push(@data, <F>);
	}

	return \@data;
}


# --------------------------------------------------------------------
# Sorts the commands
# --------------------------------------------------------------------
sub sort_data {
	my $data = shift;
	$logger->debug("offline: Sorting data");
	return $data;
}


# --------------------------------------------------------------------
# Runs the commands and returns the list of errors
# --------------------------------------------------------------------
sub process_data {
	my $data = shift;
	my $resp = [];
	for my $d (@$data) {
		$logger->activity("offline: Executing command $d");
	}
	return $resp;
}

# --------------------------------------------------------------------
# Moves the script files from the pending directory to the archive dir
# --------------------------------------------------------------------
sub archive_files {
	my $archivedir = create_archive_dir($org);
	my $pendingdir = get_pending_dir($org);
	my $err = "Error moving offline logs from $pendingdir to $archivedir";
	my @files = <$pendingdir/*.log>;

	system( ("rm", "$pendingdir/lock") ) == 0 or handle_error($err);
	system( ("mv", "@files", "$archivedir") ) == 0 or handle_error($err);
	system( ("rmdir", "$pendingdir") ) == 0 or handle_error($err);
	$logger->debug("offline: Archiving files to $archivedir");
}


