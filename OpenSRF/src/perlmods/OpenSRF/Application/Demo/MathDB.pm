package OpenSRF::Application::Demo::MathDB;
use JSON;
use base qw/OpenSRF::Application/;
use OpenSRF::Application;
use OpenSRF::DomainObject::oilsResponse qw/:status/;
#use OpenSRF::DomainObject::oilsPrimitive;
use OpenSRF::Utils::Logger qw/:level/;
use strict;
use warnings;

sub DESTROY{}
our $log = 'OpenSRF::Utils::Logger';
sub initialize {}

__PACKAGE__->register_method( method => 'add_1', api_name => 'dbmath.add' );
sub add_1 {
	my $self = shift;
	my $client = shift;

	my $n1 = shift; 
	my $n2 = shift;
	my $a = $n1 + $n2;
	return JSON::number->new($a);
}

__PACKAGE__->register_method( method => 'sub_1', api_name => 'dbmath.sub' );
sub sub_1 {
	my $self = shift;
	my $client = shift;

	my $n1 = shift; 
	my $n2 = shift;
	my $a = $n1 - $n2;
	return JSON::number->new($a);
}

__PACKAGE__->register_method( method => 'mult_1', api_name => 'dbmath.mult' );
sub mult_1 {
	my $self = shift;
	my $client = shift;

	my $n1 = shift; 
	my $n2 = shift;
	my $a = $n1 * $n2;
	return JSON::number->new($a);
}

__PACKAGE__->register_method( method => 'div_1', api_name => 'dbmath.div' );
sub div_1 {
	my $self = shift;
	my $client = shift;

	my $n1 = shift; 
	my $n2 = shift;
	my $a = $n1 / $n2;
	return JSON::number->new($a);
}

1;
