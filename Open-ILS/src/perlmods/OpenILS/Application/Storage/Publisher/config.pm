package OpenILS::Application::Storage::Publisher::config;
use base qw/OpenILS::Application::Storage/;
#use OpenILS::Application::Storage::CDBI::config;


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
	api_name	=> 'open-ils.storage.direct.config.metabib_field.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);

sub standing_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( config::standing->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'standing_all',
	api_name	=> 'open-ils.storage.direct.config.standing.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);

sub ident_type_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( config::identification_type->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'ident_type_all',
	api_name	=> 'open-ils.storage.direct.config.identification_type.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);

sub config_status_all {
	my $self = shift;
	my $client = shift;

	for my $rec ( config::copy_status->retrieve_all ) {
		$client->respond( $rec->to_fieldmapper );
	}

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'config_status_all',
	api_name	=> 'open-ils.storage.direct.config.copy_status.retrieve.all',
	argc		=> 0,
	stream		=> 1,
);

1;
