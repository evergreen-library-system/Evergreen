package OpenILS::Application::Storage::Publisher::metabib;
use base qw/OpenILS::Application::Storage/;
use vars qw/$VERSION/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::CDBI::metabib;
use OpenILS::Utils::Fieldmapper;

$VERSION = 1;

sub create_full_rec {
	my $self = shift;
	my $client = shift;
	my $metadata = shift;

	try {
		my $rec = metabib::full_rec->create($metadata);
		$client->respond( $rec->id );
	} catch Error with {
		$client->respond( 0 );
	};

	return undef;
}
__PACKAGE__->register_method(
	method		=> 'create_full_rec',
	api_name	=> 'open-ils.storage.metabib.full_rec.create',
	api_level	=> 1,
	argc		=> 2,
	note		=><<TEXT
Method to create a "full_rec" (Koha) nodeset in the DB.
0|new->id = open-ils.storage.metabib.full_rec.create ( Fieldmapper::metabib::full_rec );
TEXT

);

sub update_full_rec {
	my $self = shift;
	my $client = shift;
	my $entry = shift;
	
	try {
		metabib::full_rec->update($entry);
	} catch Error with {
		return 0;
	};
	return 1;
}
__PACKAGE__->register_method(
	method		=> 'update_full_rec',
	api_name	=> 'open-ils.storage.metabib.full_rec.update',
	api_level	=> 1,
	argc		=> 1,
);

sub delete_full_rec {
	my $self = shift;
	my $client = shift;
	my $entry = shift;
	
	try {
		metabib::full_rec->delete($entry);
	} catch Error with {
		return 0;
	};
	return 1;
}
__PACKAGE__->register_method(
	method		=> 'delete_full_rec',
	api_name	=> 'open-ils.storage.metabib.full_rec.delete',
	api_level	=> 1,
	argc		=> 1,
);

sub get_full_rec {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	for my $id ( @ids ) {
		next unless ($id);
		
		my ($rec) = metabib::full_rec->fast_fieldmapper($id);
		$client->respond( $rec ) if ($rec);

		last if ($self->api_name !~ /list/o);
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'get_full_rec',
	api_name	=> 'open-ils.storage.metabib.full_rec.retrieve',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_full_rec',
	api_name	=> 'open-ils.storage.metabib.full_rec.retrieve.list',
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);


sub create_record_nodeset {
	my $self = shift;
	my $client = shift;
	my @nodes = @_;

	my $method = $self->method_lookup('open-ils.storage.metabib.record_node.create');

	my @success;
	while ( my $node = shift(@nodes) ) {
		my ($res) = $method->run( $node );
		push @success, $res if ($res);
	}
	
	my $insert_total = 0;
	$insert_total += $_ for (@success);

	return $insert_total;
}
__PACKAGE__->register_method(
	method		=> 'create_record_nodeset',
	api_name	=> 'open-ils.storage.metabib.record_node.batch.create',
	api_level	=> 1,
	argc		=> 1,
);

sub update_record_nodeset {
	my $self = shift;
	my $client = shift;

	my $method = $self->method_lookup('open-ils.storage.metabib.record_node.update');

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
	api_name	=> 'open-ils.storage.metabib.record_node.batch.update',
	api_level	=> 1,
	argc		=> 1,
);

sub delete_record_nodeset {
	my $self = shift;
	my $client = shift;

	my $method = $self->method_lookup('open-ils.storage.metabib.record_node.delete');

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
	api_name	=> 'open-ils.storage.metabib.record_node.batch.delete',
	api_level	=> 1,
	argc		=> 1,
);

sub get_record_nodeset {
	my $self = shift;
	my $client = shift;
	my @ids = @_;

	for my $id ( @ids ) {
		next unless ($id);
		
		$client->respond( [metabib::record_node->fast_fieldmapper( owner_doc => "$id", {order_by => 'intra_doc_id'} )] );
		
		last if ($self->api_name !~ /list/o);
	}
	return undef;
}
__PACKAGE__->register_method(
	method		=> 'get_record_nodeset',
	api_name	=> 'open-ils.storage.metabib.full_rec.nodeset.retrieve',
	api_level	=> 1,
	argc		=> 1,
);
__PACKAGE__->register_method(
	method		=> 'get_record_nodeset',
	api_name	=> 'open-ils.storage.metabib.full_rec.nodeset.retrieve.list',
	api_level	=> 1,
	argc		=> 1,
	stream		=> 1,
);


1;
