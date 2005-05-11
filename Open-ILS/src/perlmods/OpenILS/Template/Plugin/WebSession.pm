package OpenILS::Template::Plugin::WebSession;
use strict; use warnings;
use OpenILS::Utils::Fieldmapper;

use Template::Plugin;
use base qw/Template::Plugin/;
use OpenSRF::AppSession;
use OpenSRF::System;

use vars qw/$textmap/;

# allows us to use a process-wide variable cache
my $_CACHE = {};

sub gettext {
	my( $self, $text ) = @_;
	return $text;
}

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

sub add_cache {
	my($self, $key, $value ) = @_;
	$_CACHE->{$key} = $value;
}

sub get_cache {
	my( $self, $key ) = @_;
	if( exists($_CACHE->{$key})) {
		return $_CACHE->{$key};
	}
	return undef;
}



1;
