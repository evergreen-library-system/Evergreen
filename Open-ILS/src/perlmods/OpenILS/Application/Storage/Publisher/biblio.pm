package OpenILS::Application::Storage::Publisher::biblio;
use base qw/OpenILS::Application::Storage/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::CDBI::biblio;
use OpenILS::Utils::Fieldmapper;

$VERSION = 1;

sub create_record_entry {
	my $self = shift;
	my $client = shift;
	my $metadata = shift;

	try {
		my $rec = biblio::record_entry->create($metadata);
		$client->respond( $rec->id );
	} catch Error with {
		$client->respond( 0 );
	};

	return undef;
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
	
	my $rec = biblio::record_entry->update($entry);
	return 0 unless ($rec);
	return 1;
}
__PACKAGE__->register_method(
	method		=> 'update_record_entry',
	api_name	=> 'open-ils.storage.biblio.record_entry.update',
	api_level	=> 1,
	argc		=> 1,
);

sub delete_record_entry {
	my $self = shift;
	my $client = shift;
	my $entry = shift;
	
	my $rec = biblio::record_entry->delete($entry);
	return 0 unless ($rec);
	return 1;
}
__PACKAGE__->register_method(
	method		=> 'delete_record_entry',
	api_name	=> 'open-ils.storage.biblio.record_entry.delete',
	api_level	=> 1,
	argc		=> 1,
);

sub search_record_entry_one_field {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	(my $search_field = $self->api_name) =~ s/^.*\.search\.([^\.]+).*?$/$1/o;

	for my $id ( @ids ) {
		next unless ($id);
		
		for my $rec ( biblio::record_entry->fast_fieldmapper($search_field => "$id") ) {
			$client->respond( $rec ) if ($rec);
		}

		last if ($self->api_name !~ /list/o);
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'search_record_entry_one_field',
	api_name	=> 'open-ils.storage.biblio.record_entry.search.tcn_value',
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'search_record_entry_one_field',
	api_name	=> 'open-ils.storage.biblio.record_entry.search.tcn_value.list',
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);

sub get_record_entry {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	for my $id ( @ids ) {
		next unless ($id);
		
		my ($rec) = biblio::record_entry->fast_fieldmapper($id);
		$client->respond( $rec ) if ($rec);

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

sub create_record_node {
	my $self = shift;
	my $client = shift;
	my $node = shift;;

	try {
		my $n = biblio::record_node->create($node);
		$client->respond( $n->id );
	} catch Error with {
		$client->respond( 0 );
	};

	return undef;
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

	my $n = biblio::record_node->update($node);
	return 0 unless ($n);
	return 1;
}
__PACKAGE__->register_method(
	method		=> 'update_record_node',
	api_name	=> 'open-ils.storage.biblio.record_node.update',
	api_level	=> 1,
	argc		=> 1,
);

sub delete_record_node {
	my $self = shift;
	my $client = shift;
	my $node = shift;
	
	my $rec = biblio::record_node->delete($node);
	return 0 unless ($rec);
	return 1;
}
__PACKAGE__->register_method(
	method		=> 'delete_record_node',
	api_name	=> 'open-ils.storage.biblio.record_node.delete',
	api_level	=> 1,
	argc		=> 1,
);

sub get_record_node {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	for my $id ( @ids ) {
		next unless ($id);
		
		my ($rec) = biblio::record_node->fast_fieldmapper($id);
		$client->respond( $rec ) if ($rec);

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

sub create_record_nodeset {
	my $self = shift;
	my $client = shift;

	my $method = $self->method_lookup('open-ils.storage.biblio.record_node.create');

	my @success;
	while ( my $node = shift(@_) ) {
		my ($res) = $method->run( $node );
		push @success, $res if ($res);
	}
	
	my $insert_total = 0;
	$insert_total += $_ for (@success);

	return $insert_total;
}
__PACKAGE__->register_method(
	method		=> 'create_record_nodeset',
	api_name	=> 'open-ils.storage.biblio.record_node.batch.create',
	api_level	=> 1,
	argc		=> 1,
);

sub update_record_nodeset {
	my $self = shift;
	my $client = shift;

	my $method = $self->method_lookup('open-ils.storage.biblio.record_node.update');

	my @success;
	while ( my $node = shift(@_) ) {
		my ($res) = $method->run( $node );
		push @success, $res if ($res);
	}

	my $update_total = 0;
	$update_total += $_ for (@success);
	
	return $update_total;
}
__PACKAGE__->register_method(
	method		=> 'create_record_nodeset',
	api_name	=> 'open-ils.storage.biblio.record_node.batch.update',
	api_level	=> 1,
	argc		=> 1,
);

sub delete_record_nodeset {
	my $self = shift;
	my $client = shift;

	my $method = $self->method_lookup('open-ils.storage.biblio.record_node.delete');

	my @success;
	while ( my $node = shift(@_) ) {
		my ($res) = $method->run( $node );
		push @success, $res if ($res);
	}

	my $delete_total = 0;
	$delete_total += $_ for (@success);
	
	return $delete_total;
}
__PACKAGE__->register_method(
	method		=> 'create_record_nodeset',
	api_name	=> 'open-ils.storage.biblio.record_node.batch.delete',
	api_level	=> 1,
	argc		=> 1,
);

sub get_record_nodeset {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	for my $id ( @ids ) {
		next unless ($id);
		
		$client->respond( [biblio::record_node->fast_fieldmapper( owner_doc => "$id", {order_by => 'intra_doc_id'} )] );
		
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
