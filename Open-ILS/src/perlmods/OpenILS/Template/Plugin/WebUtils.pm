package OpenILS::Template::Plugin::WebUtils;
use strict; use warnings;
use OpenILS::Utils::Fieldmapper;

use Template::Plugin;
use base qw/Template::Plugin/;
use OpenSRF::AppSession;
use OpenSRF::System;
use XML::LibXML;
use OpenSRF::Utils::SettingsParser;

sub new {
	my ($class) = @_;
	$class = ref($class) || $class;
	my $self = {};
	return bless($self,$class);
}
	

sub XML2perl {
	my( $self, $doc ) = @_;
	return OpenSRF::Utils::SettingsParser::XML2perl($doc);
}



1;
