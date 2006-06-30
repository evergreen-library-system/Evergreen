#!/usr/bin/perl
use strict; use warnings;

use Digest::MD5 qw(md5_hex);
use RPC::XML qw/smart_encode/;
use RPC::XML::Client;
use Data::Dumper; # for debugging

die "usage: $0 <username> <password>\n" unless $ARGV[1];


my $host			= 'http://10.4.0.122/xml-rpc/';
my $fine_age	= '1 day';
my $fine_limit	= 10;
my $location	= 'ARL';

my $username	= shift;
my $password	= shift;

my $authkey = login( $username, $password );


my $resp = request(
	'open-ils.collections',
	'open-ils.collections.users_of_interest.retrieve',
	$authkey, $fine_age, $fine_limit, $location );

my $user_data = $resp->value;


for my $d (@$user_data) {
	print "last billing = " .		$d->{last_pertinent_billing} . "\n";
	print "location id = " .		$d->{location} . "\n";
	print "threshold_amount = " . $d->{threshold_amount} . "\n";
	print "user id = " .				$d->{usr}->{id} . "\n";
	print "user dob = " .			$d->{usr}->{dob} . "\n";
	print "user profile = " .		$d->{usr}->{profile} . "\n";
	print "additional groups = ". join(', ', @{$d->{usr}->{groups}}) . "\n";
	print '-'x60 . "\n";
}



#request open-ils.collections open-ils.collections.user_transaction_details.retrieve "0d8681807cfa142310fec267c729641a", "2006-01-01", "WGRL-VR", [ 1000500 ]      	


#print Dumper $user_data;



# --------------------------------------------------------------------



# --------------------------------------------------------------------
# This sends an XML-RPC request and returns the RPC::XML::response
# object.  
# $resp->value gives the Perl, 
# $resp->as_string gives the XML
# --------------------------------------------------------------------
sub request {
	my( $service, $method, @args ) = @_;
	my $connection = RPC::XML::Client->new("$host/$service");
	my $resp = $connection->send_request($method, smart_encode(@args));
	return $resp;
}





# --------------------------------------------------------------------
# Login 
# --------------------------------------------------------------------
sub login {
	my( $username, $password ) = @_;

	my $seed = request( 
		'open-ils.auth',
		'open-ils.auth.authenticate.init', $username )->value;

	die "No auth seed returned\n" unless $seed;

	my $response = request(
		'open-ils.auth', 
		'open-ils.auth.authenticate.complete', 
		{	
			username => $username, 
			password => md5_hex($seed . md5_hex($password)), 
			type		=> 'temp',
		}
	)->value;

	die "No login response returned\n" unless $response;

	my $key = $response->{payload}->{authtoken};

	die "Login failed\n" unless $key;

	return $key;
}


