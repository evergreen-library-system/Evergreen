package OpenILS::Application::Storage::Publisher::biblio;
use base qw/OpenILS::Application::Storage/;
use OpenSRF::EX qw/:try/;
use OpenILS::Application::Storage::CDBI::biblio;
use OpenILS::Utils::Fieldmapper;

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

	my $n = biblio::record_node->retrieve("$$node{id}");
	return undef unless ($n);

	for my $field ( keys %$node ) {
		$n->$field( $$node{$field} );
	}

	try {
		$n->update;
		$client->respond( $n->id );
	} catch Error with {
		$client->respond( 0 );
	};

	return undef;
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

	# COPY version... not working yet
	if (0) {
	
		my $dbh = biblio::record_node->db_Main;
		my @cols = grep { $_ ne biblio::record_node->primary } biblio::record_node->columns('All');

		$dbh->do('COPY '. biblio::record_node->table .' ('.join(',',@cols).')'.' FROM STDIN');

		while ( my $node = shift(@_) ) {
			my @parts;
			for my $col (@cols) {
				my $part;
				if ($part = $node->{$col}) {
					push @parts, $dbh->quote($part);
				} else {
					push @parts, '\N';
				}
			}
			return 0 unless ($dbh->func(join("\t", map {s/^'(.*)'$/$1/o} @parts)."\n", 'putline'));
		}
		$dbh->func('\.', 'putline');
		return 1;
	} else {
		# INSERT version, works but slow

		my $method = $self->method_lookup('open-ils.storage.biblio.record_node.create');

		my @ids;
		my $total = scalar(@ids);
		my @success;

		while ( my $node = shift(@_) ) {
			my ($res) = $method->run( $node );
			push @success, $res if ($res);
		}
	
		if ($total == scalar(@success)) {
			return 1;
		} else {
			return 0;
		}
	}
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

	my $rec = biblio::record_entry->retrieve("$$entry{id}");
	return undef unless ($rec);

	for my $field ( keys %$node ) {
		$rec->$field( $$node{$field} );
	}

	try {
		$rec->update;
		$client->respond( $rec->id );
	} catech Error with {
		$client->respond( 0 );
	};

	return undef;
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
		
		my $rec = biblio::record_entry->retrieve("$id");
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
