package OpenILS::Application::Storage::Publisher::biblio;
use base qw/OpenILS::Application::Storage/;
use OpenILS::Application::Storage::CDBI::biblio;

sub create_record_node {
	my $self = shift;
	my $client = shift;
	my $node = shift;;

	my $n = biblio::record_node->create($node);
	return $n->id;
}
__PACKAGE__->register_method(
	method		=> 'create_record_node',
	api_name	=> 'open-ils.storage.biblio.record_node.create',
	api_level	=> 1,
	argc		=> 1,
);

sub update_record_node {
	my $self = shift;
	my $client = shift;
	my $node = shift;;

	my $n = biblio::record_node->retrieve($$node{id});
	return undef unless ($n);

	for my $field ( keys %$node ) {
		$n->$field( $$node{$field} );
	}

	$n->update;
	return $n->id;
}
__PACKAGE__->register_method(
	method		=> 'update_record_node',
	api_name	=> 'open-ils.storage.biblio.record_node.update',
	api_level	=> 1,
	argc		=> 1,
);


sub create_record_nodeset {
	my $self = shift;
	my $client = shift;

	my $method = $self->method_lookup('open-ils.storage.biblio.record_node.create');

	my @ids;
	while ( my $node = shift(@_) ) {
		$client->respond( $method->run( $node ) );
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'create_record_nodeset',
	api_name	=> 'open-ils.storage.biblio.record_node.batch.create',
	api_level	=> 1,
	argc		=> 1,
);

sub create_record_entry {
	my $self = shift;
	my $client = shift;
	my $metadata = shift;

	my $rec = biblio::record_entry->create($metadata);
	return $rec->id;
}
__PACKAGE__->register_method(
	method		=> 'create_record_entry',
	api_name	=> 'open-ils.storage.biblio.record_entry.create',
	api_level	=> 1,
	argc		=> 2,
	note		=> <<TEXT,

Params should be passed as a hash ref! 
Required fields are:

	creator
	editor

Please at least try to fill in:

	tcn_source
	tcn_value
	metarecord
	source
	active

TEXT

);

sub update_record_entry {
	my $self = shift;
	my $client = shift;
	my $entry = shift;

	my $rec = biblio::record_entry->retrieve($$entry{id});
	return undef unless ($rec);

	for my $field ( keys %$node ) {
		$rec->$field( $$node{$field} );
	}

	$rec->update;
	return $rec->id;
}
__PACKAGE__->register_method(
	method		=> 'update_record_node',
	api_name	=> 'open-ils.storage.biblio.record_node.update',
	api_level	=> 1,
	argc		=> 1,
);



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

sub get_record_node {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	for my $id ( @ids ) {
		next unless ($id);
		
		my $rec = biblio::record_node->retrieve($id);
		$client->respond( $self->_cdbi2Hash( $rec ) ) if ($rec);

		last if ($self->api_name !~ /list/o);
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'get_record_node',
	api_name	=> 'open-ils.storage.biblio.record_node.retrieve',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_record_node',
	api_name	=> 'open-ils.storage.biblio.record_node.retrieve.list',
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);

sub get_record_nodeset {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	for my $id ( @ids ) {
		next unless ($id);
		
		$client->respond(
			$self->_cdbi_list2AoH(
				biblio::record_node->search(
					owner_doc => $id, { order_by => 'intra_doc_id' }
				)
			)
		);

		last if ($self->api_name !~ /list/o);
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'get_record_nodeset',
	api_name	=> 'open-ils.storage.biblio.record_entry.nodeset.retrieve',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_record_nodeset',
	api_name	=> 'open-ils.storage.biblio.record_entry.nodeset.retrieve.list',
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);


1;
