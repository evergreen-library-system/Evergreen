#!/usr/bin/perl
require '../oils_header.pl';
use vars qw/ $user $authtoken /;
use strict; use warnings;
use Time::HiRes qw/time usleep/;
use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;
use JSON;

#-----------------------------------------------------------------------------
# Does a checkout, renew, and checkin 
#-----------------------------------------------------------------------------

err("usage: $0 <config> <username> <password> <base_url> ".
	"<workstation_name> <patron_barcode> <item_barcode> <iterations>") unless $ARGV[7];

my $config		= shift; # - bootstrap config
my $username	= shift; # - oils login username
my $password	= shift; # - oils login password
my $baseurl		= shift; # - base offline script url
my $station		= shift; # - workstation name
my $patronbc	= shift; # - patron barcode
my $barcode		= shift; # - item barcode
my $iterations	= shift || 1; # - number of iterations

my $useragent = LWP::UserAgent->new; # - HTTP request handler
my $seskey;
my $params; # - CGI params


sub go {
	osrf_connect($config);
	oils_login($username, $password);
	$params = "?ses=$authtoken&ws=$station";
	run_scripts();
	oils_logout();
}
go();



#-----------------------------------------------------------------------------
# Builds the script lines
#-----------------------------------------------------------------------------
sub build_script {
	
	my $json = "";
	my $time = CORE::time;

	for(1..$iterations) {

		my($s,$m,$h,$d,$mon,$y) = localtime(++$time);
		$mon++; $y += 1900;
		my $t1 = "$y-$mon-$d";
		my $t2 = "$t1 $h:$m:$s";
	
		my $checkout = {
			timestamp		=> ++$time,
			type				=> "checkout",
			barcode			=> $barcode,
			patron_barcode => $patronbc,
			checkout_time	=> $t2, 
			due_date			=> $t1
		};
	
#		my $renew = undef;
		my $renew = {
			timestamp		=> ++$time,
			type				=> "renew",
			barcode			=> $barcode,
			patron_barcode => $patronbc,
			checkout_time	=> $t2, 
			due_date			=> $t1
		};
	
		my $checkin = {
			timestamp		=> ++$time,
			type				=> "checkin",
			barcode			=> $barcode,
			backdate			=> $t1
		};
	
		$json .= JSON->perl2JSON($checkout) . "\n";
		$json .= JSON->perl2JSON($renew) . "\n" if $renew;
		$json .= JSON->perl2JSON($checkin) . "\n";
	}

	return $json;
}

#-----------------------------------------------------------------------------
# Run the scripts
#-----------------------------------------------------------------------------
sub run_scripts { 
	create_session();
	upload_script(); 
	check_sessions();
	run_script();
	check_script();
}


sub create_session {

	my $url = "$baseurl/offline.pl$params&action=create&desc=test_d";
	my $req = GET( $url );
	my $res = $useragent->request($req);
	my $response = JSON->JSON2perl($res->{_content});

	oils_event_die($response);
	$seskey = $response->{payload};
	$params = "$params&seskey=$seskey";

	printl("Created new session with key $seskey");
}


#-----------------------------------------------------------------------------
# Uploads the offline script to the server
#-----------------------------------------------------------------------------
sub upload_script {
	my $script =  build_script();

	my $req = POST( 
		"$baseurl/offline.pl",
		Content_Type => 'form-data',
		Content => [
			action	=> 'load',
			seskey	=> $seskey,
			ses		=> $authtoken, 
			ws			=> $station, 
			file		=> [ undef, "offline-test.script", Content_Type => "text/plain", Content => $script ] ]
		);

	my $res = $useragent->request($req);

	# Pass request to the user agent and get a response back
	my $event = JSON->JSON2perl($res->{_content});
	oils_event_die($event);
	print "Upload succeeded to session $seskey...\n";
}


#-----------------------------------------------------------------------------
# Gets a list of all of the sessions that were either started today or 
# completed today
#-----------------------------------------------------------------------------
sub check_sessions {

	my $url = "$baseurl/offline.pl$params&action=status&status_type=scripts";
	my $req = GET( $url );
	my $res = $useragent->request($req);
	my $ses = JSON->JSON2perl($res->{_content});

	my $scripts = $ses->{scripts};
	delete $ses->{scripts};

	$ses->{$_} ||= "" for keys %$ses;

	print "-"x60 . "\n";
	print "Session Details\n\n";
	print "$_=".$ses->{$_}."\n" for keys %$ses;

	print "scripts:\n";
	for my $scr (@$scripts) {
		$scr->{$_} ||= "" for keys %$scr;
		print "\t$_=".$scr->{$_}."\n" for keys %$scr;
	}



	print "-"x60 . "\n";
}


#-----------------------------------------------------------------------------
# Tells the server to run the script 
#-----------------------------------------------------------------------------
sub run_script {

	print "Executing script...\n";
	my $url = "$baseurl/offline.pl$params&action=execute";
	my $req = GET( $url );

	my $res = $useragent->request($req);
	my $event = JSON->JSON2perl($res->{_content});

	oils_event_die($event);
}

sub check_script {

	my $complete = 0;
	my $start = time;

	while(1) {

		my $url = "$baseurl/offline.pl$params&action=status&status_type=summary";
		my $req = GET( $url );
		my $res = $useragent->request($req);
		my $blob = JSON->JSON2perl($res->{_content});

		my $total = $blob->{total};
		my $count = $blob->{num_complete} || "0";
		$complete = ($total == $count) ? 1 : 0;

		print "Completed Transactions: $count\n";
		last if $complete;

		sleep 1;
	}

	my $diff = time - $start;

	my $url = "$baseurl/offline.pl$params&action=status&status_type=exceptions";
	my $req = GET( $url );
	my $res = $useragent->request($req);
	my $blob = JSON->JSON2perl($res->{_content});

	my @events;
	push(@events, $_->{event}) for @$blob;

	print "Received event ".$_->{ilsevent}.' : '.$_->{textcode}."\n" for @events;

	print "-"x60 . "\n";
	print "Execute round trip took $diff seconds\n";
	print "-"x60 . "\n";
}


