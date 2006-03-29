#!/usr/bin/perl
require '../oils_header.pl';
use vars qw/ $user $authtoken /;
use strict; use warnings;
use Time::HiRes qw/time usleep/;
use LWP::UserAgent;
use HTTP::Request::Common;
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
my $params; # - CGI params


sub go {
	osrf_connect($config);
	oils_login($username, $password);
	run_scripts();
	oils_logout();
}
go();



#-----------------------------------------------------------------------------
# Builds the script lines
#-----------------------------------------------------------------------------
sub build_script {
	
	my $json = "";
	(my $time = time) =~ s/\..*//og; # - remove the milliseconds we get from Time::HiRes

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
	my $seskey = upload_script(); 
	$params = "?ses=$authtoken&ws=$station&seskey=$seskey&raw=1";
	run_script($seskey);
	check_script($seskey);
}


#-----------------------------------------------------------------------------
# Uploads the offline script to the server
#-----------------------------------------------------------------------------
sub upload_script {
	my $script =  build_script();

	my $req = POST( 
		"$baseurl/offline-upload.pl",
		Content_Type => 'form-data',
		Content => [
			raw	=> 1,
			ses 	=> $authtoken, 
			ws		=> $station, 
			file	=> [ undef, "offline-test.script", Content_Type => "text/plain", Content => $script ] ]
		);

	my $res = $useragent->request($req);

	# Pass request to the user agent and get a response back
	my $event = JSON->JSON2perl($res->{_content});
	oils_event_die($event);
	print "Upload succeeded...\n";
	return $event->{payload};
}



#-----------------------------------------------------------------------------
# Tells the server to run the script 
#-----------------------------------------------------------------------------
sub run_script {
	my $req = GET( "$baseurl/offline-execute.pl$params" );
	
	print "Executing script...\n";

	my $res = $useragent->request($req);
	my $event = JSON->JSON2perl($res->{_content});
	oils_event_die($event);
}

sub check_script {

	my $complete = 0;
	my $start = time;

	while(1) {

		my $req = GET( "$baseurl/offline-status.pl$params" );
		my $res = $useragent->request($req);
		my $blob = JSON->JSON2perl($res->{_content});

		$complete = $blob->{complete};
		my $count = $blob->{num_complete} || "0";

		print "Completed Transactions: $count\n";
		last if $complete;

		usleep 500000;
	}

	my $diff = time - $start;

	my $req = GET( "$baseurl/offline-status.pl$params&detail=1" );
	my $res = $useragent->request($req);
	my $blob = JSON->JSON2perl($res->{_content});

	my @results;
	my @events;
	push(@results, @{$_->{results}}) for (@{$blob->{data}});
	push(@events, $_->{event}) for @results;

	print "Received event ".$_->{ilsevent}.' : '.$_->{textcode}."\n" for @events;

	print "-"x60 . "\n";
	print "Execute round trip took $diff seconds\n";
	print "-"x60 . "\n";
}


