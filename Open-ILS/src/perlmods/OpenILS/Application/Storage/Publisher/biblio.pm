package OpenILS::Application::Storage::Publisher::biblio;
use base qw/OpenILS::Application::Storage/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::CDBI::biblio;
use OpenILS::Utils::Fieldmapper;

sub create_record_entry {
	my $self = shift;
	my $client = shift;
	my $metadata = shift;

	my %hash = map { ( $_ => $metadata->$_) } Fieldmapper::biblio::record_entry->real_fields;

	try {
		my $rec = biblio::record_entry->create(\%hash);
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
	
	my $rec = biblio::record_entry->retrieve(''.$entry->id);
	return 0 unless ($rec);

	$rec->autoupdate(0);

	for my $field ( Fieldmapper::biblio::record_entry->real_fields ) {
		$rec->$field( $entry->$field );
	}

	return 0 unless ($rec->is_changed);

	$rec->update;

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
	
	my $rec = biblio::record_entry->retrieve(''.$entry->id);
	return 0 unless ($rec);

	$rec->delete;
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

	(my $search_field = $self->api_name) =~ s/^.*retrieve\.([^\.]+).*?$/$1/o;

	my @fields = Fieldmapper::biblio::record_entry->real_fields;
	for my $id ( @ids ) {
		next unless ($id);
		
		my $fm = new Fieldmapper::biblio::record_entry;
		for my $rec ( biblio::record_entry->search($search_field => "$id") ) {
			for my $f (@fields) {
				$fm->$f( $rec->$f );
			}
			$client->respond( $fm ) if ($rec);
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

	my @fields = Fieldmapper::biblio::record_entry->real_fields;
	for my $id ( @ids ) {
		next unless ($id);
		
		my $fm = new Fieldmapper::biblio::record_entry;
		my $rec = biblio::record_entry->retrieve("$id");
		for my $f (@fields) {
			$fm->$f( $rec->$f );
		}
		$client->respond( $fm ) if ($rec);

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

	my %hash = map { ( $_ => $node->$_) } Fieldmapper::biblio::record_node->real_fields;

	try {
		my $n = biblio::record_node->create(\%hash);
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

	
	my $n = biblio::record_node->retrieve(''.$node->id);
	return 0 unless ($n);

	$n->autoupdate(0);

	for my $field ( Fieldmapper::biblio::record_node->real_fields ) {
		$n->$field( $node->$field );
	}

	$n->update;
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
	
	my $rec = biblio::record_node->retrieve(''.$node->id);
	return 0 unless ($rec);

	$rec->delete;

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
		
		my $rec = biblio::record_node->retrieve("$id");
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

	my $table = biblio::record_node->table;
	my @fields = Fieldmapper::biblio::record_node->real_fields;
	my $field_list = join ',', @fields;

	my $sth = biblio::record_node->db_Main->prepare_cached(<<"	SQL");
		SELECT	$field_list
		  FROM	$table
		  WHERE	owner_doc = ?
		  ORDER BY intra_doc_id;
	SQL


	for my $id ( @ids ) {
		next unless ($id);
		
		$sth->execute("$id");


		my @nodeset;
		while (my $data = $sth->fetchrow_arrayref) {
			my $n = new Fieldmapper::biblio::record_node;
			my $index = 0;
			for my $f ( @fields ) {
				$n->$f( $$data[$index] );
				$index++;
			}
			push @nodeset, $n;
		}
		$sth->finish;

		$client->respond( \@nodeset );
		
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
