package OpenILS::App::MathDB;
use JSON;
use base qw/OpenILS::Application/;
use OpenILS::Application;
use OpenILS::DomainObject::oilsResponse qw/:status/;
use OpenILS::DomainObject::oilsPrimitive;
use OpenILS::Utils::Logger qw/:level/;
use strict;
use warnings;
sub DESTROY{}
our $log = 'OpenILS::Utils::Logger';
sub initialize {}

#sub method_lookup {
#
#	my( $class, $method_name, $method_proto ) = @_;
#
#	if( $method_name eq "add" ) {
#		return \&add;
#	}
#
#	if( $method_name eq "sub" ) {
#		return \&sub;
#	}
#
#	if( $method_name eq "mult" ) {
#		return \&mult;
#	}
#
#	if( $method_name eq "div" ) {
#		return \&div;
#	}
#
#	return undef;
#
#}

sub add_1 {
	my $client = shift;
	my @args = @_;
	$log->debug("Adding @args", INTERNAL);
	$log->debug("AppRequest is $client", INTERNAL);
	my $n1 = shift; my $n2 = shift;
	$n1 =~ s/\s+//; $n2 =~ s/\s+//;
	my $a = $n1 + $n2;
	return JSON::number::new($a);



	my $result = new OpenILS::DomainObject::oilsResult;
	$result->content( OpenILS::DomainObject::oilsScalar->new($a) );
	return $a;
	$client->respond($result);
	return 1;
}
sub sub_1 {
	my $client = shift;
	my @args = @_;
	$log->debug("Subbing @args", INTERNAL);
	$log->debug("AppRequest is $client", INTERNAL);
	my $n1 = shift; my $n2 = shift;
	$n1 =~ s/\s+//; $n2 =~ s/\s+//;
	my $a = $n1 - $n2;
	return JSON::number::new($a);



	my $result = new OpenILS::DomainObject::oilsResult;
	$result->content( OpenILS::DomainObject::oilsScalar->new($a) );
	return $a;
	$client->respond($result);
	return 1;
}

sub mult_1 {
	my $client = shift;
	my @args = @_;
	$log->debug("Multiplying @args", INTERNAL);
	$log->debug("AppRequest is $client", INTERNAL);
	my $n1 = shift; my $n2 = shift;
	$n1 =~ s/\s+//; $n2 =~ s/\s+//;
	my $a = JSON::number::new($n1 * $n2);
	return $a;



	my $result = new OpenILS::DomainObject::oilsResult;
	$result->content( OpenILS::DomainObject::oilsScalar->new($a) );
#	$client->respond($result);
	return $a;
}

sub div_1 {
	my $client = shift;
	my @args = @_;
	$log->debug("Dividing @args", INTERNAL);
	$log->debug("AppRequest is $client", INTERNAL);
	my $n1 = shift; my $n2 = shift;
	$n1 =~ s/\s+//; $n2 =~ s/\s+//;
	my $a = $n1 / $n2;
	return JSON::number::new($a);


	my $result = new OpenILS::DomainObject::oilsResult;
	$result->content( JSON::number::new($a) );
	return $result;
	$client->respond($a);
	return 1;
}

1;
