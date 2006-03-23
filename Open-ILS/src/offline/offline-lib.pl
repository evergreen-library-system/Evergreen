#!/usr/bin/perl
use strict; use warnings;
use CGI;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
use OpenSRF::EX qw/:try/;
use JSON;
our $U = "OpenILS::Application::AppUtils";


# --------------------------------------------------------------------
# Load the config options
# --------------------------------------------------------------------
our $META_FILE = "meta"; # name of the metadata file
our $LOCK_FILE = "lock"; # name of the lock file
our $ORG; # org id
our $ORG_UNIT; # org unit object
our $TIME_DELTA; # time offset for the log files
our %config; # config data
our $cgi; # our CGI object
our $PRINT_HTML; # true if access the CGIs via a web browser
our $AUTHTOKEN; # The login session key
our $REQUESTOR; # the requestor user object
our $base_dir; # the base directory for logs
our $WORKSTATION;

#do '##CONFIG##/upload-server.pl';
do 'offline-config.pl';

&initialize();





# --------------------------------------------------------------------
# Loads the necessary CGI params, connects to OpenSRF, and verifies
# the login session
# --------------------------------------------------------------------
sub initialize {

	$base_dir	= $config{base_dir};
	my $bsconfig	= $config{bootstrap};
	my $evt;

	# --------------------------------------------------------------------
	# Connect to OpenSRF
	# --------------------------------------------------------------------
	$logger->debug("offline: bootstrapping client with config $bsconfig");
	OpenSRF::System->bootstrap_client(config_file => $bsconfig); 


	# --------------------------------------------------------------------
	# Load the required CGI params
	# --------------------------------------------------------------------
	$cgi = new CGI;
	$PRINT_HTML = $cgi->param('html') || "";
	$AUTHTOKEN	= $cgi->param('ses') 
		or handle_event(OpenILS::Event->new('NO_SESSION'));

	$ORG = $cgi->param('org') || "";
	if(!$ORG) {
		my $ws = fetch_workstation($cgi->param('ws'));
		$ORG = $ws->owning_lib if $ws;
	}

	if($ORG) {
		($ORG_UNIT, $evt) = $U->fetch_org_unit($ORG);	
		handle_event($evt) if $evt;
	} 

	($REQUESTOR, $evt) = $U->checkses($AUTHTOKEN);
	handle_event($evt) if $evt;

	$TIME_DELTA	 = $cgi->param('delta');
}

# --------------------------------------------------------------------
# Generic HTML template to provide basic functionality
# --------------------------------------------------------------------
my $on = ($ORG_UNIT) ? $ORG_UNIT->name : "";
my $HTML = <<HTML;
	<html>
		<head>
			<title>{TITLE}</title>
		</head>
		<body>
			<div style='text-align: center; border-bottom: 2px solid #E0F0E0; padding: 10px; margin-bottom: 50px;'>
				<div style='margin: 5px;'><b>$on</b></div>
				<a style='margin: 6px;' href='offline-upload.pl?ses=$AUTHTOKEN&org=$ORG&html=1'>Upload More Files</a>
				<a style='margin: 6px;' href='offline-status.pl?ses=$AUTHTOKEN&org=$ORG&html=1'>Status Page</a>
				<a style='margin: 6px;' href='offline-execute.pl?ses=$AUTHTOKEN&org=$ORG&html=1'>Execute Batch</a>
			</div>
			<div style='text-align: center;'>
				{BODY}
			</div>
		</body>
	</html>
HTML


# --------------------------------------------------------------------
# Print out a full HTML page and exits
# --------------------------------------------------------------------
sub print_html {
	my %args		= @_;
	my $title	= $args{title} || "";
	my $body		= $args{body} || "";

	if($HTML) {
		$HTML =~ s/{TITLE}/$title/;
		$HTML =~ s/{BODY}/$body/;

	} else { # it can happen..
		$HTML = "$body"; 
	}

	print "content-type: text/html\n\n";
	print $HTML;
	exit(0);
}


# --------------------------------------------------------------------
# Prints JSON to the client
# --------------------------------------------------------------------
sub print_json {
	my( $obj, $add_header ) = @_;
	print "content-type: text/html\n\n" if $add_header;
	print JSON->perl2JSON($obj);
}

# --------------------------------------------------------------------
# Prints the JSON form of the event out to the client
# --------------------------------------------------------------------
sub handle_event {
	my $evt = shift;
	return unless $evt;

	$logger->info("offline: returning event ".$evt->{textcode});

	if( $PRINT_HTML ) {

		# maybe make this smarter
		print_html(
			title => 'Offline Event Occurred', 
			body => JSON->perl2JSON($evt));

	} else {
		print_json($evt,1);

	}
	exit(0);
}


# --------------------------------------------------------------------
# Fetches and creates if necessary the pending directory
# --------------------------------------------------------------------
sub get_pending_dir {
	my $dir = "$base_dir/pending/$ORG/";
	system( ('mkdir', '-p', "$dir") ) == 0 
		or handle_error("Unable to create directory $dir");
	$logger->debug("offline: created/fetched pending directory $dir");	
	return $dir;
}

# --------------------------------------------------------------------
# Fetches and creates if necessary the archive directory
# --------------------------------------------------------------------
sub create_archive_dir {
	my (undef,$min,$hour,$mday,$mon,$year) = localtime(time);

	$mon++;
	$year		+= 1900;
	$min		= "0$min"	unless $min		=~ /\d{2}/o;
	$hour		= "0$hour"	unless $hour	=~ /\d{2}/o;
	$mday		= "0$mday"	unless $mday	=~ /\d{2}/o;
	$mon		= "0$mon"	unless $mon		=~ /\d{2}/o;

	my $dir = "$base_dir/archive/$ORG/$year$mon$mday$hour$min/";
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

sub append_meta {
	my $data = shift;
	$data = JSON->perl2JSON($data);
	my $mf = get_pending_dir($ORG) . "/$META_FILE";
	$logger->debug("offline: Append metadata to file $mf: $data");
	open(F, ">>$mf") or handle_event(OpenILS::Event->new('OFFLINE_FILE_ERROR', payload => $@));
	print F "$data\n";
	close(F);
}

sub read_meta {
	my $mf = get_pending_dir($ORG) . "/$META_FILE";
	open(F, "$mf") or return [];
	my @data = <F>;
	close(F);
	my @resp;
	push @resp, JSON->JSON2perl($_) for @data;
	@resp = grep { $_ and $_->{'workstation'} } @resp;
	$logger->debug("offline: Reading metadata from file $mf: @resp");
	return \@resp;
}

sub log_to_wsname {
	my $log = shift;
	$log =~ s/\.log//og;
	$log =~ s#/.*/(\w+)#$1#og;
	return $log
}
