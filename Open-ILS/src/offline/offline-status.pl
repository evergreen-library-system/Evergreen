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
	
	my $html	= &offline_cgi->param('html');
	my $wslist = &gather_workstations;

	if( $html ) { 
		&report_html($wslist); 

	} else { 
		&report_json($wslist); 
	}
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



