#!/usr/bin/perl
use strict; use warnings;
use CGI;
use OpenSRF::System;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Application::AppUtils;
use OpenILS::Event;
use OpenSRF::EX qw/:try/;
use JSON;
use Data::Dumper;
use OpenILS::Utils::Fieldmapper;
use Digest::MD5 qw/md5_hex/;
use OpenSRF::Utils qw/:daemon/;
our $U = "OpenILS::Application::AppUtils";
our %config;


# --------------------------------------------------------------------
# Load the config options
# --------------------------------------------------------------------
my $time_delta;
my $cgi; 
my $base_dir; 
my $requestor; 
my $workstation;
my $org;
my $org_unit;
my $authtoken;
my $seskey;

# --------------------------------------------------------------------
# Define accessors for all of the shared vars
# --------------------------------------------------------------------
sub offline_requestor { return $requestor; }
sub offline_authtoken { return $authtoken; }
sub offline_workstation { return $workstation; }
sub offline_org { return $org; }
sub offline_org_unit { return $org_unit;}
sub offline_meta_file { return &offline_pending_dir . '/meta'; }
sub offline_lock_file { return &offline_pending_dir . '/lock'; }
sub offline_result_file { return &offline_pending_dir . '/results'; }
sub offline_base_dir { return $base_dir; }
sub offline_time_delta { return $time_delta; }
sub offline_config { return %config; }
sub offline_cgi { return $cgi; }
sub offline_seskey { return $seskey; }



# --------------------------------------------------------------------
# Load the config
# --------------------------------------------------------------------
#do '##CONFIG##/upload-server.pl';
do 'offline-config.pl';


# --------------------------------------------------------------------
# Set everything up
# --------------------------------------------------------------------
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
	OpenSRF::System->bootstrap_client(config_file => $bsconfig); 


	# --------------------------------------------------------------------
	# Load the required CGI params
	# --------------------------------------------------------------------
	$cgi = new CGI;

	$authtoken	= $cgi->param('ses') 
		or handle_event(OpenILS::Event->new('NO_SESSION'));

	$org = $cgi->param('org') || "";
	if(!$org) {
		if(my $ws = $cgi->param('ws')) {
			$workstation = fetch_workstation($ws);
			$org = $workstation->owning_lib if $workstation;
		}
	}

	if($org) {
		($org_unit, $evt) = $U->fetch_org_unit($org);	
		handle_event($evt) if $evt;
	} 

	($requestor, $evt) = $U->checkses($authtoken);
	handle_event($evt) if $evt;

	$time_delta	 = $cgi->param('delta') || "0";

	$seskey = $cgi->param('seskey') || time . "_$$";
}


# --------------------------------------------------------------------
# Print out a full HTML page and exits
# --------------------------------------------------------------------
sub print_html {

	my %args	= @_;
	my $body	= $args{body} || "";
	my $res  = $args{result} || "";
	my $on	= ($org_unit) ? $org_unit->name : "";

	my $html = <<"	HTML";
		<html>
			<head>
				<script>
					function offline_complete(obj) { 
						if(!obj) return; 
						if(obj.payload) 
							alert('Received ' + obj.payload.length + ' events'); 
						else 
							alert('Received event: ' + obj.ilsevent + ' : ' + obj.textcode);
					}
				</script>
			</head>
			<body onload='offline_complete($res);'>
				<div style='text-align: center; border-bottom: 2px solid #E0F0E0; padding: 10px; margin-bottom: 50px;'>
					<div style='margin: 5px;'><b>$on</b></div>
					<a style='margin: 6px;' href='offline-upload.pl?ses=$authtoken&org=$org&seskey=$seskey'>Upload More Files</a>
					<a style='margin: 6px;' href='offline-status.pl?ses=$authtoken&org=$org&seskey=$seskey'>Status Page</a>
					<a style='margin: 6px;' href='offline-execute.pl?ses=$authtoken&org=$org&seskey=$seskey'>Execute Batch</a>
				</div>
				<div style='margin: 10px; text-align: center;'>
					$body
				</div>
			</body>
		</html>
	HTML

	print "content-type: text/html\n\n";
	print $html;

	exit(0);
}


# --------------------------------------------------------------------
# Prints the JSON form of the event out to the client
# --------------------------------------------------------------------
sub handle_event {
	my $evt = shift;
	my $ischild = shift;
	return unless $evt;

	$logger->info("offline: returning event ".$evt->{textcode});

	# maybe make this smarter
	print_html( result => JSON->perl2JSON($evt)) unless $ischild;
	append_result($evt) and exit;
}


# --------------------------------------------------------------------
# Appends a result event to the result file
# --------------------------------------------------------------------
sub append_result {
	my $evt = JSON->perl2JSON(shift());
	my $fname = &offline_result_file;
	open(R, ">>$fname") or die 
		"Unable to open result file [$fname] for appending: $@\n";
	print R "$evt\n";
	close(R);
}


sub handle_error { warn shift() . "\n"; }


# --------------------------------------------------------------------
# Fetches (and creates if necessary) the pending directory
# --------------------------------------------------------------------
sub offline_pending_dir {
	my $dir = "$base_dir/pending/$org/$seskey/";

	if( ! -e $dir ) {
		qx/mkdir -p $dir/ and handle_error("Unable to create directory $dir");
	}

	return $dir;
}

# --------------------------------------------------------------------
# Fetches and creates if necessary the archive directory
# --------------------------------------------------------------------
sub create_archive_dir {
	#my (undef,$min,$hour,$mday,$mon,$year) = localtime(time);
	my (undef,undef, undef, $mday,$mon,$year) = localtime(time);

	$mon++;
	$year		+= 1900;
#	$min		= "0$min"	unless $min		=~ /\d{2}/o;
#	$hour		= "0$hour"	unless $hour	=~ /\d{2}/o;
	$mday		= "0$mday"	unless $mday	=~ /\d{2}/o;
	$mon		= "0$mon"	unless $mon		=~ /\d{2}/o;

	my $dir = "$base_dir/archive/$org/${year}_${mon}_${mday}/$seskey/";
	qx/mkdir -p $dir/ and handle_error("Unable to create archive directory $dir");
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
	handle_event(OpenILS::Event->new('WORKSTATION_NOT_FOUND')) unless $ws;
	return $ws;
}

sub append_meta {
	my $data = shift;
	$data = JSON->perl2JSON($data);
	my $mf = &offline_meta_file;
	$logger->debug("offline: Append metadata to file $mf: $data");
	open(F, ">>$mf") or handle_event(OpenILS::Event->new('OFFLINE_FILE_ERROR', payload => $@));
	print F "$data\n";
	close(F);
}

sub read_meta {
	my $mf = &offline_meta_file;
	open(F, "$mf") or return [];
	my @data = <F>;
	close(F);
	my @resp;
	push(@resp, JSON->JSON2perl($_)) for @data;
	@resp = grep { $_ and $_->{'workstation'} } @resp;
	return \@resp;
}

sub log_to_wsname {
	my $log = shift;
	$log =~ s/\.log//og;
	$log =~ s#/.*/(\w+)#$1#og;
	return $log
}

1;
