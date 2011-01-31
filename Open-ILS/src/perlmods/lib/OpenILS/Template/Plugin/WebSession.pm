package OpenILS::Template::Plugin::WebSession;
use strict; use warnings;
use OpenILS::Utils::Fieldmapper;

use Template::Plugin;
use base qw/Template::Plugin/;
use OpenSRF::AppSession;
use OpenSRF::System;

sub new {
	my ($class) = @_;
	$class = ref($class) || $class;
	my $self = {};
	return bless($self,$class);
}
	
my $bootstrapped = 0;
sub bootstrap_client {
	my( $self, $config_file ) = @_;
	if(!$bootstrapped) {
		OpenSRF::System->bootstrap_client( config_file => $config_file );
		$bootstrapped = 1;
	}
}

sub init_app_session {
	my($self, $service) = @_;
	return undef unless $service;
	return OpenSRF::AppSession->create($service);
}



1;
