#!/usr/bin/perl
use strict; use warnings;

# --------------------------------------------------------------------
# Loads the offline script files for a given org, sorts and runs the 
# scripts, and returns the exception list
# --------------------------------------------------------------------

our $U;
our $logger;
require 'offline-lib.pl';
&execute();


sub execute {
	my $evt = $U->check_perms(&offline_requestor->id, &offline_org, 'OFFLINE_VIEW');
	handle_event($evt) if $evt;
	&report_json(&gather_workstations) if &offline_cgi->param('detail');
	&report_json_summary; 
}


# --------------------------------------------------------------------
# Collects a list of workstations that have pending files
# --------------------------------------------------------------------
sub gather_workstations {
	my $dir = &offline_pending_dir;
	$dir = &offline_archive_dir unless -e $dir;
	return [] unless -e $dir;
	my @files =  <$dir/*.log>;
	$_ =~ s/\.log//og for @files; # remove .log
	$_ =~ s#/.*/(\w+)#$1#og for @files; # remove leading file path
	return \@files;
}


# --------------------------------------------------------------------
# Just resturns whether or not the transaction is complete and how
# many items have been processed
# --------------------------------------------------------------------
sub report_json_summary {

	my $complete = 0;
	my $results = &offline_read_results;
	if(!$$results[0]) {
		$results  = &offline_read_archive_results;
		handle_event(OpenILS::Event->new(
			'OFFLINE_SESSION_NOT_FOUND')) unless $$results[0];
		$complete = 1;
	}

	&offline_handle_json(
		{complete => $complete, num_complete => scalar(@$results)});
}


# --------------------------------------------------------------------
# Reports the workstations and their results as JSON
# --------------------------------------------------------------------
sub report_json { 
	my $wslist = shift;
	my @data;

	my $meta = &offline_read_meta;
	my $results = &offline_read_results;
	my $complete = 0;

	if(!$$meta[0]) {
		$logger->debug("offline: attempting to report on archived files for session ".&offline_seskey);
		$meta		= &offline_read_archive_meta;
		$results  = &offline_read_archive_results;
		$complete = 1;
	}

	for my $ws (@$wslist) {
		my ($m) = grep { $_ and $_->{'log'} and $_->{'log'} =~ m#/.*/$ws.log# } @$meta;
		my @res = grep { $_->{command}->{_workstation} eq $ws } @$results;
		delete $m->{'log'};
		push( @data, { meta => $m, workstation => $ws, results =>  \@res } );
	}

	&offline_handle_json({ complete => $complete, data => \@data});
}



