package OpenSRF::Application::Demo::MathDB;
use base qw/OpenSRF::Application/;
use OpenSRF::Application;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
use OpenSRF::DomainObject::oilsPrimitive;
use OpenSRF::Utils::Logger qw/:level/;
use strict;
use warnings;
sub DESTROY{}
our $log = 'OpenSRF::Utils::Logger';

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
	my $result = new OpenSRF::DomainObject::oilsResult;
	$result->content( OpenSRF::DomainObject::oilsScalar->new($a) );
	return $result;
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
	my $result = new OpenSRF::DomainObject::oilsResult;
	$result->content( OpenSRF::DomainObject::oilsScalar->new($a) );
	return $result;
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
	my $a = $n1 * $n2;
	my $result = new OpenSRF::DomainObject::oilsResult;
	$result->content( OpenSRF::DomainObject::oilsScalar->new($a) );
#	$client->respond($result);
	return $result;
}

sub div_1 {
	my $client = shift;
	my @args = @_;
	$log->debug("Dividing @args", INTERNAL);
	$log->debug("AppRequest is $client", INTERNAL);
	my $n1 = shift; my $n2 = shift;
	$n1 =~ s/\s+//; $n2 =~ s/\s+//;
	my $a = $n1 / $n2;
	my $result = new OpenSRF::DomainObject::oilsResult;
	$result->content( OpenSRF::DomainObject::oilsScalar->new($a) );
	return $result;
	$client->respond($result);
	return 1;
}

1;
