#!/usr/bin/perl
use strict; use warnings;

use Digest::MD5 qw(md5_hex);
use RPC::XML qw/smart_encode/;
use RPC::XML::Client;
use Data::Dumper; # for debugging

die "usage: $0 <host> <location> <username> <password>\n" unless $ARGV[3];


# some example query params
my $host			= shift;
my $location	= shift;
my $username	= shift;
my $password	= shift;


$host				= "http://$host/xml-rpc/";
my $fine_age	= '1 day';
my $fine_limit	= 10;




# --------------------------------------------------------------------
# Login to the system so we can get an authentication token
# --------------------------------------------------------------------
my $authkey = login( $username, $password );




# --------------------------------------------------------------------
# First get the list of users that should be placed into collections
# --------------------------------------------------------------------
my $resp = request(
	'open-ils.collections',
	'open-ils.collections.users_of_interest.retrieve',
	$authkey, $fine_age, $fine_limit, $location );



# --------------------------------------------------------------------
# Get the Perl-ized version of the data
# --------------------------------------------------------------------
my $user_data = $resp->value;



# --------------------------------------------------------------------
# For each user in the response, print some preliminary info on the 
# user, then fetch the full user/transaction details and print 
# info on those
# --------------------------------------------------------------------
for my $d (@$user_data) {


	# --------------------------------------------------------------------
	# Print some basic info about the user	
	# --------------------------------------------------------------------
	print "user id = " .				$d->{usr}->{id} . "\n";
	print "user dob = " .			$d->{usr}->{dob} . "\n";
	print "user profile = " .		$d->{usr}->{profile} . "\n";
	print "additional groups = ". join(', ', @{$d->{usr}->{groups}}) . "\n";
	print "last billing = " .		$d->{last_pertinent_billing} . "\n";
	print "threshold_amount = " . $d->{threshold_amount} . "\n";
	# --------------------------------------------------------------------


	# --------------------------------------------------------------------
	# Now "flesh" the user object and grab all of the transaction details
	# --------------------------------------------------------------------
	my $xact_data = request(
		'open-ils.collections',
		'open-ils.collections.user_transaction_details.retrieve',
		$authkey, '2006-01-01', '2006-12-12', $location, [ $d->{usr}->{id} ] );
	$xact_data = $xact_data->value->[0];

	my $user		= $xact_data->{usr}->{__data__};
	my $circs	= $xact_data->{transactions}->{circulations};
	my $grocery = $xact_data->{transactions}->{grocery};


	# --------------------------------------------------------------------
	# Print out the user's addresses
	# --------------------------------------------------------------------
	for my $addr (@{$user->{addresses}}) {
		my $a = $addr->{__data__};

		print join(' ', 
			$a->{street1}, 
			$a->{street2}, 
			$a->{city}, 
			$a->{state}, 
			$a->{post_code}) . "\n";
	}

	print_xact_details($_->{__data__}) for (@$circs, @$grocery);

	print "\n" . '-'x60 . "\n";
}


# --------------------------------------------------------------------
# Prints details on transactions, billings, and payments
# --------------------------------------------------------------------
sub print_xact_details {
	my $xact = shift;

	my $loc = ($xact->{circ_lib}) ? $xact->{circ_lib} : $xact->{billing_location};
	print " - transaction ".$xact->{id}. " started at " . 
		$xact->{xact_start} . " at " . $loc->{__data__}->{shortname} ."\n";

	# --------------------------------------------------------------------
	# Print some info on any bills attached to this transaction
	# --------------------------------------------------------------------
	for my $bill (@{$xact->{billings}}) {
		my $b = $bill->{__data__};
		print "\tbill ".$b->{id}. " created on " . $b->{billing_ts} . "\n";
		print "\tamount = ".$b->{amount} . "\n";
		print "\ttype = ".$b->{billing_type} . "\n";
		print "\t" . '-'x30 . "\n";
	}

	# --------------------------------------------------------------------
	# Print some info on any payments made on this transaction
	# --------------------------------------------------------------------
	for my $payment (@{$xact->{payments}}) {
		my $p = $payment->{__data__};
		print "\tpayment ".$p->{id}. " made on " . $p->{payment_ts} . "\n";
		print "\tamount = ".$p->{amount} . "\n";
		print "\t" . '-'x30 . "\n";

	}
}




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


