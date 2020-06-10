
{ # The driver package itself just needs a db_Main method.
  #
  # Any other fixups can go in here too... Also, the drivers should subclass the
  # DBI driver that they are wrapping, or provide a 'quote()' method that calls
  # the DBD::xxx::quote() method on FTI's behalf.
  #
  # The dirver MUST be a subclass of Class::DBI and
  # OpenILS::Application::Storage.
  #-------------------------------------------------------------------------------
    package OpenILS::Application::Storage::Driver::Pg;
    # The following modules add, or use, subroutines in modules that
    # are not available when this module is compiled.  We therefore
    # "require" these modules rather than "use" them.  Everything is
    # available at run time.
    require OpenILS::Application::Storage::Driver::Pg::cdbi;
    require OpenILS::Application::Storage::Driver::Pg::fts;
    require OpenILS::Application::Storage::Driver::Pg::storage;
    require OpenILS::Application::Storage::Driver::Pg::dbi;

    use UNIVERSAL::require; 
    BEGIN {                 
        'Class::DBI::Frozen::301'->use or 'Class::DBI'->use or die $@;
    }     
    use base qw/Class::DBI OpenILS::Application::Storage/;
    use DBI;
    use OpenSRF::EX qw/:try/;
    use OpenSRF::DomainObject::oilsResponse;
    use OpenSRF::Utils::Logger qw/:level/;
    my $log = 'OpenSRF::Utils::Logger';

    __PACKAGE__->set_sql( retrieve_limited => 'SELECT * FROM __TABLE__ ORDER BY id LIMIT ?' );
    __PACKAGE__->set_sql( copy_start => 'COPY %s (%s) FROM STDIN;' );
    __PACKAGE__->set_sql( copy_end => '\.' );

    my $primary_db;
    my @standby_dbs;
    my $_db_params;

    sub db_Handles {
        return ($primary_db, @standby_dbs);
    }

    sub child_init {
        my $self = shift;
        $_db_params = shift;

        $log->debug("Running child_init inside ".__PACKAGE__, INTERNAL);

        $_db_params = [ $_db_params ] unless (ref($_db_params) eq 'ARRAY');

        my %attrs = (   %{$self->_default_attributes},
                RootClass => 'DBIx::ContextualFetch',
                ShowErrorStatement => 1,
                RaiseError => 1,
                AutoCommit => 1,
                PrintError => 1,
                Taint => 1,
                #TraceLevel => "1|SQL",
                pg_enable_utf8 => 1,
                pg_server_prepare => 0,
                FetchHashKeyName => 'NAME_lc',
                ChopBlanks => 1,
        );

        my $primary = shift @$_db_params;
        $$primary{port} ||= '5432';
        $$primary{host} ||= 'localhost';
        $$primary{db} ||= 'openils';

        $log->debug("Attempting to connect to $$primary{db} at $$primary{host}", INFO);

        try {
            $primary_db = DBI->connect(
                "dbi:Pg:".
                    "host=$$primary{host};".
                    "port=$$primary{port};".
                    "dbname=$$primary{db}".
                    ($$primary{application_name} ? ";application_name='$$primary{application_name}'": ""),
                $$primary{user},
                $$primary{pw},
                \%attrs)
            || do { sleep(1);
                DBI->connect(
                    "dbi:Pg:".
                        "host=$$primary{host};".
                        "port=$$primary{port};".
                        "dbname=$$primary{db}".
                        ($$primary{application_name} ? ";application_name='$$primary{application_name}'": ""),
                    $$primary{user},
                    $$primary{pw},
                    \%attrs) }
            || throw OpenSRF::EX::ERROR
                ("Couldn't connect to $$primary{db}".
                 " on $$primary{host}::$$primary{port}".
                 " as $$primary{user}!!");
        } catch Error with {
            my $e = shift;
            $log->debug("Error connecting to database:\n\t$e\n\t$DBI::errstr", ERROR);
            throw $e;
        };

        $log->debug("Connected to primary db $$primary{db} at $$primary{host}", INFO);
        
        $primary_db->do("SET NAMES '$$primary{client_encoding}';") if ($$primary{client_encoding});

        for my $db (@$_db_params) {
            try {
                push @standby_dbs, DBI->connect("dbi:Pg:host=$$db{host};port=$$db{port};dbname=$$db{db}". ($$db{application_name} ? ";application_name='$$db{application_name}'" : ""),$$db{user},$$db{pw}, \%attrs)
                    || do { sleep(1); DBI->connect("dbi:Pg:host=$$db{host};port=$$db{port};dbname=$$db{db}". ($$db{application_name} ? ";application_name='$$db{application_name}'" : ""),$$db{user},$$db{pw}, \%attrs) }
                    || throw OpenSRF::EX::ERROR
                        ("Couldn't connect to $$db{db}".
                        " on $$db{host}::$$db{port}".
                        " as $$db{user}!!");
            } catch Error with {
                my $e = shift;
                $log->debug("Error connecting to database:\n\t$e\n\t$DBI::errstr", ERROR);
                throw $e;
            };

            $standby_dbs[-1]->do("SET NAMES '$$db{client_encoding}';") if ($$primary{client_encoding});

            $log->debug("Connected to primary db '$$primary{db} at $$primary{host}", INFO);
        }

        $log->debug("All is well on the western front", INTERNAL);
    }

    sub db_Main {
        my $self = shift;
        return $primary_db if ($self->current_xact_session || $OpenILS::Application::Storage::WRITE);
        return $primary_db unless (@standby_dbs);
        return ($primary_db, @standby_dbs)[rand(scalar(@standby_dbs))];
    }

    sub quote {
        my $self = shift;
        return $self->db_Main->quote(@_)
    }

    my $_xact_session;
    my $_audit_session;

    sub current_xact_session {
        my $self = shift;
        if (defined($_xact_session)) {
            return $_xact_session;
        }
        return undef;
    }

    sub current_audit_session {
        my $self = shift;
        if (defined($_audit_session)) {
            return $_audit_session;
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

    sub set_audit_session {
        my $self = shift;
        my $ses = shift;
        if (!defined($ses)) {
            return undef;
        }
        $_audit_session = $ses;
        return $_audit_session;
    }

    sub unset_xact_session {
        my $self = shift;
        my $ses = $_xact_session;
        undef $_xact_session;
        return $ses;
    }

    sub unset_audit_session {
        my $self = shift;
        my $ses = $_audit_session;
        undef $_audit_session;
        return $ses;
    }

}

1;
