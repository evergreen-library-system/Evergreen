{ # Based on the change to Class::DBI in OpenILS::Application::Storage.  This will
  # allow us to use TSearch2 via a simple cdbi "search" interface.
	#-------------------------------------------------------------------------------
	use Class::DBI;
	package Class::DBI;

	sub search_fti {
		my $self = shift;
		my @args = @_;
		if (ref($args[-1]) eq 'HASH') {
			$args[-1]->{_placeholder} = "to_tsquery('default',?)";
		} else {
			push @args, {_placeholder => "to_tsquery('default',?)"};
		}
		$self->_do_search("@@"  => @args);
	}
}

{ # Every driver needs to provide a 'compile()' method to OpenILS::Application::Storage::FTS.
  # If that driver wants to support FTI, that is...
	#-------------------------------------------------------------------------------
	package OpenILS::Application::Storage::FTS;
	use OpenSRF::Utils::Logger qw/:level/;
	my $log = 'OpenSRF::Utils::Logger';

	sub compile {
		my $self = shift;
		my $term = shift;

		$self = ref($self) || $self;
		$self = bless {} => $self;

		$self->decompose($term);

		my $newterm = join('&', $self->words);

		if ($self->nots) {
			$newterm = '('.$newterm.')&('. join('|', $self->nots) . ')';
		}

		$newterm = OpenILS::Application::Storage->driver->quote($newterm);

		$self->{fts_query} = ["to_tsquery('default',$newterm)"];
		$self->{fts_query_nots} = [];
		$self->{fts_op} = '@@';

		return $self;
	}
}


{ # The driver package itself just needs a db_Main method (or db_Slaves if
  #Class::DBI::Replication is in use) for Class::DBI to call.
  #
  # Any other fixups can go in here too... Also, the drivers should subclass the
  # DBI driver that they are wrapping, or provide a 'quote()' method that calls
  # the DBD::xxx::quote() method on FTI's behalf.
  #
  # The dirver MUST be a subclass of Class::DBI(::Replication) and
  # OpenILS::Application::Storage.
  #-------------------------------------------------------------------------------
	package OpenILS::Application::Storage::Driver::Pg;
	use Class::DBI::Replication;
	use base qw/Class::DBI::Replication OpenILS::Application::Storage/;
	use DBI;
	use OpenSRF::EX qw/:try/;
	use OpenSRF::Utils::Logger qw/:level/;
	my $log = 'OpenSRF::Utils::Logger';

	__PACKAGE__->set_sql( retrieve_limited => 'SELECT * FROM __TABLE__ ORDER BY id LIMIT ?' );

	my $_db_params;
	sub child_init {
		my $self = shift;
		$_db_params = shift;

		$_db_params = [ $_db_params ] unless (ref($_db_params) eq 'ARRAY');

		my %attrs = (	%{$self->_default_attributes},
				RootClass => 'DBIx::ContextualFetch',
				ShowErrorStatement => 1,
				RaiseError => 1,
				AutoCommit => 1,
				PrintError => 1,
				Taint => 1,
				pg_enable_utf8 => 1,
				FetchHashKeyName => 'NAME_lc',
				ChopBlanks => 1,
		);

		my ($master,@slaves);
		for my $db (@$_db_params) {
			if ($db->{type} eq 'master') {
				__PACKAGE__->set_master("dbi:Pg:host=$$db{host};dbname=$$db{db}",$$db{user},$$db{pw}, \%attrs);
			}
			push @slaves, ["dbi:Pg:host=$$db{host};dbname=$$db{db}",$$db{user},$$db{pw}, \%attrs];
		}

		__PACKAGE__->set_slaves(@slaves);

		$log->debug("Running child_init inside ".__PACKAGE__, INTERNAL);
	}

	sub quote {
		return __PACKAGE__->db_Slaves->quote(@_)
	}

	sub tsearch2_trigger {
		my $self = shift;
		return unless ($self->value);
		$self->index_vector(
			$self->db_Slaves->selectrow_array(
				"SELECT to_tsvector('default',?);",
				{},
				$self->value
			)
		);
	}

	my $_xact_session;
	sub current_xact_session {
		my $self = shift;
		my $ses = shift;
		$_xact_session = $ses if (defined $ses);
		return $_xact_session;
	}

	sub db_Slaves {	
		my $self = shift;

		if ($self->current_xact_session && OpenSRF::AppSession->find($self->current_xact_session)) {
			return $self->db_Main;
		}

		return $self->_pick_slaves->($self, @_);
		return $self->SUPER::db_Slaves;
	}

}


{
	package OpenILS::Application::Storage;

	sub pg_begin_xaction {
		my $self = shift;
		my $client = shift;

		OpenILS::Application::Storage::Driver::Pg->current_xact_session( $client->session->session_id );

		$client->session->register_callback( disconnect => sub { __PACKAGE__->pg_commit_xaction($client); } )
			if ($self->api_name =~ /autocommit$/o);

		$client->session->register_callback( death => sub { __PACKAGE__->pg_rollback_xaction($client); } );

		return $self->begin_xaction;
	}
	__PACKAGE__->register_method(
		method		=> 'pg_begin_xaction',
		api_name	=> 'open-ils.storage.transaction.begin',
		api_level	=> 1,
		argc		=> 0,
	);
	__PACKAGE__->register_method(
		method		=> 'pg_begin_xaction',
		api_name	=> 'open-ils.storage.transaction.begin.autocommit',
		api_level	=> 1,
		argc		=> 0,
	);

	sub pg_commit_xaction {

		OpenILS::Application::Storage::Driver::Pg->current_xact_session( 0 );
		return $self->commit_xaction(@_);
	}
	__PACKAGE__->register_method(
		method		=> 'pg_commit_xaction',
		api_name	=> 'open-ils.storage.transaction.commit',
		api_level	=> 1,
		argc		=> 0,
	);

	sub pg_rollback_xaction {

		OpenILS::Application::Storage::Driver::Pg->current_xact_session( 0 );
		return $self->rollback_xaction(@_);
	}
	__PACKAGE__->register_method(
		method		=> 'pg_rollback_xaction',
		api_name	=> 'open-ils.storage.transaction.rollback',
		api_level	=> 1,
		argc		=> 0,
	);

}

{
	#---------------------------------------------------------------------
	package asset::call_number;
	
	asset::call_number->table( 'asset.call_number' );
	asset::call_number->sequence( 'asset.call_number_id_seq' );
	
	#---------------------------------------------------------------------
	package asset::copy;
	
	asset::copy->table( 'asset.copy' );
	asset::copy->sequence( 'asset.copy_id_seq' );
	
	#---------------------------------------------------------------------
	package biblio::record_entry;
	
	biblio::record_entry->table( 'biblio.record_entry' );
	biblio::record_entry->sequence( 'biblio.record_entry_id_seq' );

	#---------------------------------------------------------------------
	package biblio::record_node;
	
	biblio::record_node->table( 'biblio.record_data' );
	biblio::record_node->sequence( 'biblio.record_data_id_seq' );
	
	#---------------------------------------------------------------------
	package biblio::record_note;
	
	biblio::record_note->table( 'biblio.record_note' );
	biblio::record_note->sequence( 'biblio.record_note_id_seq' );
	
	#---------------------------------------------------------------------
	package actor::user;
	
	actor::user->table( 'actor.usr' );
	actor::user->sequence( 'actor.usr_id_seq' );
	
	#---------------------------------------------------------------------
	package actor::org_unit_type;
	
	actor::org_unit_type->table( 'actor.org_unit_type' );
	actor::org_unit_type->sequence( 'actor.org_unit_type_id_seq' );
	
	#---------------------------------------------------------------------
	
	#-------------------------------------------------------------------------------
	package metabib::metarecord;

	metabib::metarecord->table( 'metabib.metarecord' );
	metabib::metarecord->sequence( 'metabib.metarecord_id_seq' );

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::title_field_entry;

	metabib::title_field_entry->table( 'metabib.title_field_entry' );
	metabib::title_field_entry->sequence( 'metabib.title_field_entry_id_seq' );
	metabib::title_field_entry->columns( Primary => qw/id/ );
	metabib::title_field_entry->columns( Essential => qw/id/ );
	metabib::title_field_entry->columns( Others => qw/field value index_vector/ );

	metabib::title_field_entry->add_trigger(
		before_create => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
	);
	metabib::title_field_entry->add_trigger(
		before_update => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::author_field_entry;

	metabib::author_field_entry->table( 'metabib.author_field_entry' );
	metabib::author_field_entry->sequence( 'metabib.author_field_entry_id_seq' );

	metabib::author_field_entry->add_trigger(
		before_create => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
	);
	metabib::author_field_entry->add_trigger(
		before_update => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::subject_field_entry;

	metabib::subject_field_entry->table( 'metabib.subject_field_entry' );
	metabib::subject_field_entry->sequence( 'metabib.subject_field_entry_id_seq' );

	metabib::subject_field_entry->add_trigger(
		before_create => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
	);
	metabib::subject_field_entry->add_trigger(
		before_update => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::keyword_field_entry;

	metabib::keyword_field_entry->table( 'metabib.keyword_field_entry' );
	metabib::keyword_field_entry->sequence( 'metabib.keyword_field_entry_id_seq' );

	metabib::keyword_field_entry->add_trigger(
		before_create => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
	);
	metabib::keyword_field_entry->add_trigger(
		before_update => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::title_field_entry_source_map;

	metabib::title_field_entry_source_map->table( 'metabib.title_field_entry_source_map' );
	metabib::title_field_entry_source_map->table( 'metabib.title_field_entry_source_map_id_seq' );

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::author_field_entry_source_map;

	metabib::author_field_entry_source_map->table( 'metabib.author_field_entry_source_map' );
	metabib::author_field_entry_source_map->sequence( 'metabib.author_field_entry_source_map_id_seq' );

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::subject_field_entry_source_map;

	metabib::subject_field_entry_source_map->table( 'metabib.subject_field_entry_source_map' );
	metabib::subject_field_entry_source_map->sequence( 'metabib.subject_field_entry_source_map_id_seq' );

	#-------------------------------------------------------------------------------
}

1;
