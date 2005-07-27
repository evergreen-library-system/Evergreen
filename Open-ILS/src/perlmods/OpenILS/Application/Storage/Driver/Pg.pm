
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
	use OpenILS::Application::Storage::Driver::Pg::cdbi;
	use OpenILS::Application::Storage::Driver::Pg::fts;
	use OpenILS::Application::Storage::Driver::Pg::storage;
	use OpenILS::Application::Storage::Driver::Pg::dbi;
	use Class::DBI;
	use base qw/Class::DBI OpenILS::Application::Storage/;
	use DBI;
	use OpenSRF::EX qw/:try/;
	use OpenSRF::DomainObject::oilsResponse;
	use OpenSRF::Utils::Logger qw/:level/;
	my $log = 'OpenSRF::Utils::Logger';

	__PACKAGE__->set_sql( retrieve_limited => 'SELECT * FROM __TABLE__ ORDER BY id LIMIT ?' );
	__PACKAGE__->set_sql( copy_start => 'COPY %s (%s) FROM STDIN;' );
	__PACKAGE__->set_sql( copy_end => '\.' );

	my $master_db;
	my @slave_dbs;
	my $_db_params;
	sub child_init {
		my $self = shift;
		$_db_params = shift;

		$log->debug("Running child_init inside ".__PACKAGE__, INTERNAL);

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

		my $master = shift @$_db_params;
		$log->debug("Attmpting to connet to $$master{db} at $$master{host}", INFO);

		try {
			$master_db = DBI->connect("dbi:Pg:host=$$master{host};dbname=$$master{db}",$$master{user},$$master{pw}, \%attrs) ||
				throw OpenSRF::EX::ERROR ("Couldn't connect to $$master{db} on $$master{host} as $$master{user}!!");
		} catch Error with {
			my $e = shift;
			$log->debug("Error connecting to database:\n\t$e\n\t$DBI::errstr", ERROR);
			throw $e;
		};

		$log->debug("Connected to MASTER db $$master{db} at $$master{host}", INFO);
		
		$master_db->do("SET NAMES '$$master{client_encoding}';") if ($$master{client_encoding});

		for my $db (@$_db_params) {
			push @slave_dbs, DBI->connect("dbi:Pg:host=$$db{host};dbname=$$db{db}",$$db{user},$$db{pw}, \%attrs);
			$slave_dbs[-1]->do("SET NAMES '$$db{client_encoding}';") if ($$master{client_encoding});

			$log->debug("Connected to MASTER db '$$master{db} at $$master{host}", INFO);
		}

		$log->debug("All is well on the western front", INTERNAL);
	}

	sub db_Main {
		my $self = shift;
		return $master_db if ($self->current_xact_session);
		return $master_db unless (@slave_dbs);
		return ($master_db, @slave_dbs)[rand(scalar(@slave_dbs))];
	}

	sub quote {
		my $self = shift;
		return $self->db_Main->quote(@_)
	}

#	sub tsearch2_trigger {
#		my $self = shift;
#		return unless ($self->value);
#		$self->index_vector(
#			$self->db_Slaves->selectrow_array(
#				"SELECT to_tsvector('default',?);",
#				{},
#				$self->value
#			)
#		);
#	}

	my $_xact_session;

	sub current_xact_session {
		my $self = shift;
		if (defined($_xact_session)) {
			return $_xact_session;
		}
		return undef;
	}

	sub current_xact_is_auto {
		my $self = shift;
		my $auto = shift;
		if (defined($_xact_session) and ref($_xact_session)) {
			if (defined $auto) {
				$_xact_session->session_data(autocommit => $auto);
			}
			return $_xact_session->session_data('autocommit'); 
		}
	}

	sub current_xact_id {
		my $self = shift;
		if (defined($_xact_session) and ref($_xact_session)) {
			return $_xact_session->session_id;
		}
		return undef;
	}

	sub set_xact_session {
		my $self = shift;
		my $ses = shift;
		if (!defined($ses)) {
			return undef;
		}
		$_xact_session = $ses;
		return $_xact_session;
	}

	sub unset_xact_session {
		my $self = shift;
		my $ses = $_xact_session;
		undef $_xact_session;
		return $ses;
	}

}

1;
