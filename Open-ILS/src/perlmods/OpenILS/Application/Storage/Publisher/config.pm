package OpenILS::Application::Storage::Publisher::config;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::config;


sub metabib_field_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( config::metabib_field->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'metabib_field_all',
	api_name	=> 'open-ils.storage.direct.config.metabib_field.all',
	argc		=> 0,
	stream		=> 1,
);

1;
