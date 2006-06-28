#!/usr/bin/perl
use strict; use warnings;

use Digest::MD5 qw(md5_hex);
use RPC::XML qw/smart_encode/;
use RPC::XML::Client;
use Data::Dumper; # for debugging


my $host			= 'http://10.4.0.122/xml-rpc/';
my $fine_age	= '1 day';
my $fine_limit	= 10;
my $location	= 'ARL';

my $username	= shift;
my $password	= shift;

my $authkey = login( $username, $password );

die "login failed\n" unless $authkey;

my $resp = request(
	'open-ils.collections',
	'open-ils.collections.users_of_interest.retrieve',
	$authkey, $fine_age, $fine_limit, $location );

my $data = $resp->value;


for my $d (@$data) {
	print "last billing = " . $d->{last_pertinent_billing} . "\n";
	print "location id = " . $d->{location} . "\n";
	print "threshold_amount = " . $d->{threshold_amount} . "\n";
	print "user barcode = " . $d->{usr} . "\n";
	print '-'x60 . "\n";
}



# --------------------------------------------------------------------




# --------------------------------------------------------------------
# This sends an XML-RPC request and returns the RPC::XML::response
# object.  $obj->value gives the Perl, $obj->as_string gives the XML
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

	return $response->{payload}->{authtoken};
}


