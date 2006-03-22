#!/usr/bin/perl
use strict; use warnings;

# --------------------------------------------------------------------
#  Uploads offline action files
#	pending files go into $base_dir/pending/<org>/<ws>.log
#	completed transactions go into $base_dir/archive/<org>/YYYMMDDHHMM/<ws>.log
# --------------------------------------------------------------------

our $U;
our %config;
our $cgi;
our $base_dir;
our $logger;
my $org;
require 'offline-lib.pl';

if( $cgi->param('file') ) { 
	&load_file(); 
	&handle_success("File Upload Succeeded<br/><br/>".
	"<a href='offline-execute.pl?org=$org'>Execute Scripts for org $org</a>");
} else {
	&display_upload(); 
}


# --------------------------------------------------------------------
# Use this for testing manual uploads
# --------------------------------------------------------------------
sub display_upload {

	my $ws	= $cgi->param('ws');
	my $ses	= $cgi->param('ses');

	handle_error("Missing data in upload.  We need ws and ses") 
		unless ($ws and $ses);

	print "content-type: text/html\n\n";
	print <<"	HTML";
	<html>
		<head>
			<title>Offline Upload Server</title>
			<style type='text/css'>
				input { margin: 5px;' }
			</style>
		</head>
		<body>
			<div style='margin-top: 50px; text-align: center;'>
				<form action='offline-upload.pl' method='post' enctype='multipart/form-data'>
					<b>Testing</b><br/><br/>
					<b> - Select an offline file to upload - </b><br/><br/>
					<input type='file' name='file'> </input>
					<input type='submit' name='Submit' value='Upload'> </input>
					<input type='hidden' name='ws' value='$ws'> </input>
					<input type='hidden' name='ses' value='$ses'> </input>
				</form>
			</div>
		</body>
	</html>
	HTML
}



sub load_file() {

	my $wsname	= $cgi->param('ws');
	my $ses		= $cgi->param('ses');
	my $filehandle = $cgi->upload('file');

	my $ws = fetch_workstation($wsname);
	$org = $ws->owning_lib;
	my $dir = get_pending_dir($org);
	my $output = "$dir/$wsname.log";
	my $lock = "$dir/lock";

	handle_error("Offline batch in process for this location.  Please try again later." ) if( -e $lock );
	handle_error("File $output already exists" ) if( -e $output );

	$logger->debug("offline: Writing log file $output");
	open(FILE, ">$output");
	while( <$filehandle> ) { print FILE; }
}





