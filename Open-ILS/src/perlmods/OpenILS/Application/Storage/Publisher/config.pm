package OpenILS::Application::Storage::Publisher::config;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::config;

sub getBiblioFieldMaps {
	my $self = shift;
	my $client = shift;
	my $id = shift;
	$log->debug(" Executing [".$self->method."] as [".$self->api_name."]",INTERNAL);
	
	if ($self->api_name =~ /by_class$/o) {
		if ($id) {
			return $self->_cdbi2Hash( config::metarecord_field_map->search( fieldclass => $id ) );
		} else {
			throw OpenSRF::EX::InvalidArg ('Please give me a Class to look up!');
		}
	} else {
		if ($id) {
			return $self->_cdbi2Hash( config::metarecord_field_map->retrieve( $id ) );
		} else {
			return $self->_cdbi_list2AoH( config::metarecord_field_map->retrieve_all );
		}
	}
}	
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMaps',
	api_name	=> 'open-ils.storage.config.metarecord_field',
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMaps',
	api_name	=> 'open-ils.storage.config.metarecord_field.all',
	argc		=> 0,
);
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMaps',
	api_name	=> 'open-ils.storage.config.metarecord_field.list.by_class',
	argc		=> 1,
);


sub getBiblioFieldMapClasses {
	my $self = shift;
	my $client = shift;
	my @ids = shift;

	$log->debug(" Executing [".$self->method."] as [".$self->api_name."]",INTERNAL);

	if ($self->api_name =~ /all/o) {
		return $self->_cdbi_list2AoH( config::metarecord_field_class_map->retrieve_all );
	} else {
		for my $id (@ids) {
			next unless ($id);
			$client->respond( $self->_cdbi2Hash( config::metarecord_field_class_map->retrieve( $id ) ) );
			last unless ($self->api_name =~ /list/o);
		} 
		return undef;
	}
}	
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMapClasses',
	api_name	=> 'open-ils.storage.config.metarecord_field_class',
	argc		=> 1,
);

__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMapClasses',
	api_name	=> 'open-ils.storage.config.metarecord_field_class.list',
	argc		=> 1,
	stream		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'getBiblioFieldMapClasses',
	api_name	=> 'open-ils.storage.config.metarecord_field_class.all',
	argc		=> 0,
);

1;
