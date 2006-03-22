#!/usr/bin/perl
use strict; use warnings;
use CGI;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use JSON;


our $U = "OpenILS::Application::AppUtils";
our %config;
#do '##CONFIG##/upload-server.pl';
do 'offline-config.pl';
our $cgi = new CGI;
our $base_dir = $config{base_dir};
my $bsconfig = $config{bootstrap};


# --------------------------------------------------------------------
# Connect to OpenSRF
# --------------------------------------------------------------------
OpenSRF::System->bootstrap_client(config_file => $bsconfig);




# --------------------------------------------------------------------
# Prints out an error message to the client
# --------------------------------------------------------------------
sub handle_error {
	my $err = shift;
	$logger->error("offline: $err");
	print "content-type: text/html\n\n";
	print <<"	HTML";
	<html>
		<head>
			<title>Offline Upload Failed</title>
		</head>
		<body>
			<div style='margin-top: 50px; text-align: center;'>
				<b style='color:red;'>Offline Upload Failed</b><br/>
				<span> $err </span>
			</div>
		</body>
	</html>
	HTML
	exit(1);
}


# --------------------------------------------------------------------
# Prints out a success message to the client
# --------------------------------------------------------------------
sub handle_success {
	my $msg = shift;
	$logger->info("offline: returned success message: $msg");
	print "content-type: text/html\n\n";
	print <<"	HTML";
	<html>
		<head>
			<title>Success</title>
		</head>
		<body>
			<div style='margin-top: 50px; text-align: center;'>
				<b style='color:blue;'> $msg </b><br/>
			</div>
		</body>
	</html>
	HTML
}



# --------------------------------------------------------------------
# Fetches and creates if necessary the pending directory
# --------------------------------------------------------------------
sub get_pending_dir {
	my $org = shift;
	my $dir = "$base_dir/pending/$org/";
	system( ('mkdir', '-p', "$dir") ) == 0 
		or handle_error("Unable to create directory $dir");
	$logger->debug("offline: created/fetched pending directory $dir");	
	return $dir;
}

# --------------------------------------------------------------------
# Fetches and creates if necessary the archive directory
# --------------------------------------------------------------------
sub create_archive_dir {
	my $org = shift;
	my (undef,$min,$hour,$mday,$mon,$year) = localtime(time);

	$mon++;
	$year		+= 1900;
	$min		= "0$min"	unless $min		=~ /\d{2}/o;
	$hour		= "0$hour"	unless $hour	=~ /\d{2}/o;
	$mday		= "0$mday"	unless $mday	=~ /\d{2}/o;
	$mon		= "0$mon"	unless $mon		=~ /\d{2}/o;

	my $dir = "$base_dir/archive/$org/$year$mon$mday$hour$min/";
	system( ('mkdir', '-p', "$dir") ) == 0 
		or handle_error("Unable to create archive directory $dir");
	$logger->debug("offline: Created archive directory $dir");
	return $dir;
}



# --------------------------------------------------------------------
# Fetches the workstation object by name
# --------------------------------------------------------------------
sub fetch_workstation {
	my $name = shift;
	$logger->debug("offline: Fetching workstation $name");
	my $ws = $U->storagereq(
		'open-ils.storage.direct.actor.workstation.search.name', $name);
	handle_error("Workstation $name does not exists") unless $ws;
	return $ws;
}


