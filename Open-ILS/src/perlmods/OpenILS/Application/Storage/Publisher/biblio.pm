package OpenILS::Application::Storage::Publisher::biblio;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::biblio;

sub get_record_entry {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	for my $id ( @ids ) {
		next unless ($id);
		
		my $rec = biblio::record_entry->retrieve($id);
		$client->respond( $self->_cdbi2Hash( $rec ) ) if ($rec);

		last if ($self->api_name !~ /list/o);
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'get_record_entry',
	api_name	=> 'open-ils.storage.biblio.record_entry.retrieve',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_record_entry',
	api_name	=> 'open-ils.storage.biblio.record_entry.retrieve.list',
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);

1;
