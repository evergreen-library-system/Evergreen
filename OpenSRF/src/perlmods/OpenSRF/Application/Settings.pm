package OpenSRF::Application::Settings;
use OpenSRF::Application;
use OpenSRF::Utils::SettingsParser;
use base 'OpenSRF::Application';



__PACKAGE__->register_method( method => 'get_host_config', api_name => 'opensrf.settings.host_config.get' );
sub get_host_config {
	my( $self, $client, $host ) = @_;
	my $parser = OpenSRF::Utils::SettingsParser->new();
	return $parser->get_server_config($host);
}




__PACKAGE__->register_method( method => 'xpath_get', api_name => 'opensrf.settings.xpath.get' );

__PACKAGE__->register_method( 
		method	=> 'xpath_get', 
		api_name => 'opensrf.settings.xpath.get.raw' );

sub xpath_get {
	my($self, $client, $xpath) = @_;
	warn "*************** Received XPATH $xpath\n";
	return  OpenSRF::Utils::SettingsParser->new()->_get_all( $xpath );
}


1;
