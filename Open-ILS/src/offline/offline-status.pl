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
	&report_sessions() if &offline_cgi->param('seslist');
	&report_json_summary; 
}


sub report_sessions {
	my $sessions = &offline_org_sessions(&offline_org);
	my $results = [];
	for my $s (@$sessions) {
		my $name = $$s[0];
		my $file = $$s[1];
		my $meta = &_offline_file_to_perl("$file/meta", 'workstation');
		my $done = ($file =~ m#/archive/#o) ? 1 : 0;
		my $desc = shift @$meta;
		push( @$results, { session => $name, desc => $desc, meta => $meta, complete => $done } );
	}
	&offline_handle_json($results);
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
	my $results;

	if( -e &offline_pending_dir ) {
		$results = &offline_read_results

	} elsif( -e &offline_archive_dir ) {
		$results  = &offline_read_archive_results;
		$complete = 1;

	} else {
		handle_event(OpenILS::Event->new('OFFLINE_SESSION_NOT_FOUND'));
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

	shift @$meta;
	for my $ws (@$wslist) {
		my ($m) = grep { $_ and $_->{'log'} and $_->{'log'} =~ m#/.*/$ws.log# } @$meta;
		my @res = grep { $_->{command}->{_workstation} eq $ws } @$results;
		delete $m->{'log'};
		@res = grep { $_->{event}->{ilsevent} ne '0' } @res; # strip all the success events
		push( @data, { meta => $m, workstation => $ws, results =>  \@res } ) if @res;
	}

	&offline_handle_json({ complete => $complete, data => \@data});
}



