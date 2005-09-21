package OpenILS::Template::Plugin::JSON;
use strict; use warnings;

use Template::Plugin;
use base qw/Template::Plugin/;
use JSON;

sub new {
	my ($class) = @_;
	$class = ref($class) || $class;
	my $self = {};
	return bless($self,$class);
}

sub perl2JSON {
	my( $self, $perl ) = @_;
	return JSON->perl2JSON($perl);
}
	

sub JSON2perl {
	my( $self, $perl ) = @_;
	return JSON->JSON2perl($perl);
}

sub perl2prettyJSON {
	my( $self, $perl ) = @_;
	return JSON->perl2prettyJSON($perl);
}
	

1;
