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
my $desc;

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
sub offline_archive_meta_file { return &offline_archive_dir . '/meta'; }
sub offline_archive_result_file { return &offline_archive_dir . '/results'; }
sub offline_base_dir { return $base_dir; }
sub offline_time_delta { return $time_delta; }
sub offline_config { return %config; }
sub offline_cgi { return $cgi; }
sub offline_seskey { return $seskey; }
sub offline_base_pending_dir { return $base_dir .'/pending/'; }
sub offline_base_archive_dir { return $base_dir .'/archive/'; }
sub offline_description { return $desc; }



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

	($requestor, $evt) = $U->checkses($authtoken);
	handle_event($evt) if $evt;

	$org = $cgi->param('org') || "";

	if(!$org) {
		if(my $ws = $cgi->param('ws')) {
			$workstation = fetch_workstation($ws);
			$org = $workstation->owning_lib if $workstation;
		} else {
			$org = $requestor->ws_ou;
			$logger->debug("offline: fetching org from requestor object: $org");
		}
	}

	if($org) {
		($org_unit, $evt) = $U->fetch_org_unit($org);	
		handle_event($evt) if $evt;
	} else {
		handle_event(OpenILS::Event->new('OFFLINE_NO_ORG'));
	}


	$time_delta	 = $cgi->param('delta') || "0";

	$seskey = $cgi->param('seskey') || time . "_$$";
	
	if( $cgi->param('createses') ) {
		if( -e &offline_pending_dir || -e &offline_archive_dir ) {
			&handle_event(OpenILS::Event->new('OFFLINE_SESSION_EXISTS'));
		}
		handle_event(OpenILS::Event->new('OFFLINE_INVALID_SESSION')) unless $seskey =~ /^\w+$/;
		&offline_pending_dir(1);
		$desc = $cgi->param('desc') || "Offline Script";
		&append_meta($desc);

	}
}


# --------------------------------------------------------------------
# Print out a full HTML page and exits
# --------------------------------------------------------------------
sub print_html {

	my %args	= @_;
	my $body	= $args{body} || "";
	my $res  = $args{result} || "";
	my $on	= ($org_unit) ? $org_unit->name : "";

	$authtoken	||= "";
	$org			||= "";
	$seskey		||= "";

	my $html = <<"	HTML";
		<html>
			<head>
				<script src='/opac/common/js/JSON.js'> </script>
				<script>
					function offline_complete(obj) { 
						if(!obj) return;
						try {
							xulG.handle_event(obj);
						} catch(e) {
							alert(js2JSON(obj)); 
						}
					}
				</script>
				<style> 
					a { margin: 6px; } 
					div { margin: 10px; text-align: center; }
				</style>
			</head>
			<body onload='offline_complete($res);'>
				<div>
					<div style='margin: 5px;'><b>$on</b></div>
					<a href='offline-upload.pl?ses=$authtoken&org=$org'>Upload More Files</a>
					<a href='offline-status.pl?ses=$authtoken&org=$org&seskey=$seskey'>Status Page</a>
					<a href='offline-execute.pl?ses=$authtoken&org=$org&seskey=$seskey'>Execute Batch</a>
				</div>
				<hr/>
				<div>$body</div>
			</body>
		</html>
	HTML

	if( &offline_cgi->param('raw') ) {
		print "content-type: text/plain\n\n";
		print $res;	

	} else {
		print "content-type: text/html\n\n";
		print $html;
	}

	exit(0);
}


# --------------------------------------------------------------------
# Prints the JSON form of the event out to the client
# --------------------------------------------------------------------
sub handle_event { &offline_handle_json(@_); }

sub offline_handle_json {
	my $obj = shift;
	my $ischild = shift;
	return unless $obj;
	print_html(result => JSON->perl2JSON($obj)) unless $ischild;
	append_result($obj) and exit;
}



sub handle_error { warn shift() . "\n"; }


# --------------------------------------------------------------------
# Fetches (and creates if necessary) the pending directory
# --------------------------------------------------------------------
sub offline_pending_dir {
	my $create = shift;
	my $dir = "$base_dir/pending/$org/$seskey/";

	if( $create and ! -e $dir ) {
		$logger->debug("offline: creating pending directory $dir");
		qx/mkdir -p $dir/ and handle_error("Unable to create directory $dir");
	}

	return $dir;
}

sub _offline_date {
	my (undef,undef, undef, $mday,$mon,$year) = localtime(time);
	$mon++; $year	+= 1900;
	$mday	= "0$mday" unless $mday =~ /\d{2}/o;
	$mon	= "0$mon" unless $mon	=~ /\d{2}/o;
	return ($year, $mon, $mday);
}

# --------------------------------------------------------------------
# Fetches and creates if necessary the archive directory
# --------------------------------------------------------------------
sub offline_archive_dir { return create_archive_dir(@_); }
sub create_archive_dir {
	my $create = shift;
	my( $year, $mon, $mday) = &_offline_date;
	my $dir = "$base_dir/archive/$org/${year}_${mon}_${mday}/$seskey/";

	if( $create and ! -e $dir ) {
		$logger->debug("offline: creating archive directory $dir");
		qx/mkdir -p $dir/ and handle_error("Unable to create archive directory $dir");
	}
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


# --------------------------------------------------------------------
# Read/Write to/from the essential files
# --------------------------------------------------------------------
sub append_meta { &_offline_file_append_perl( shift(), &offline_meta_file ); }
sub append_result { &_offline_file_append_perl( shift(), &offline_result_file ); }
sub _offline_file_append_perl {
	my( $obj, $file ) = @_;
	return unless $obj;
	$obj = JSON->perl2JSON($obj);
	open(F, ">>$file") or die
		"Unable to append data to file: $file [$! $@]\n";
	print F "$obj\n";
	close(F);
}


sub offline_read_meta { return &_offline_read_meta(&offline_meta_file); }
sub offline_read_archive_meta { return &_offline_read_meta(&offline_archive_meta_file); }
sub _offline_read_meta { return &_offline_file_to_perl(shift(), 'workstation'); }
sub offline_read_archive_results { return &_offline_read_results(&offline_archive_result_file); }
sub offline_read_results { return &_offline_read_results(&offline_result_file); }
sub _offline_read_results { return &_offline_file_to_perl(shift(), 'command'); }

sub _offline_file_to_perl {
	my( $file, $exist_key ) = @_;
	open(F,$file) or return [];
	my @data = <F>;
	close(F);
	my @resp;
	push(@resp, JSON->JSON2perl($_)) for @data;
	#@resp = grep { $_ and $_->{$exist_key} } @resp;

	# HACK to shoehorn the session description in
	#$desc = shift @resp if $exist_key eq 'workstation';  

	return \@resp;
}


sub log_to_wsname {
	my $log = shift;
	$log =~ s/\.log//og;
	$log =~ s#/.*/(\w+)#$1#og;
	return $log
}

sub offline_pending_orgs {
	my $dir = &offline_base_pending_dir;
	my @org;
	for my $org (<$dir/*>) {
		$org =~ s#/.*/(\w+)#$1#og;
		push @org, $org;
	}
	return \@org;
}


# --------------------------------------------------------------------
# Returns a list of all pending org sessions as well as all complete
# org sessions for today only as [ $name, $directory ] pairs
# --------------------------------------------------------------------
sub offline_org_sessions {

	my $org = shift;
	my( $year, $mon, $mday) = &_offline_date;

	my $pdir = &offline_base_pending_dir . '/' . &offline_org;
	my $adir = &offline_base_archive_dir . 
		'/' . &offline_org . "/${year}_${mon}_${mday}/";

	my @ses;
	for my $ses (<$pdir/*>, <$adir/*>) {
		my $name = $ses;
		$name =~ s#/.*/(\w+)#$1#og;
		push @ses, [ $name, $ses ];
	}
	return \@ses;
}




1;
