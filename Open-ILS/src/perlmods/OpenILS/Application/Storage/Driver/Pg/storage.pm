
{
	package OpenILS::Application::Storage;
	use OpenSRF::Utils::Logger;
	our $NOPRIMARY = 0;
	my $log = 'OpenSRF::Utils::Logger';

	my $pg = 'OpenILS::Application::Storage::Driver::Pg';


	sub current_xact {
		my $self = shift;
		my $client = shift;
		return $pg->current_xact_id;
	}
	__PACKAGE__->register_method(
		method		=> 'current_xact',
		api_name	=> 'open-ils.storage.transaction.current',
		api_level	=> 1,
		argc		=> 0,
	);


	sub pg_begin_xaction {
		my $self = shift;
		my $client = shift;

		local $OpenILS::Application::Storage::WRITE = 1;

		if (my $old_xact = $pg->current_xact_session) {
			if ($pg->current_xact_is_auto) {
				$log->debug("Commiting old autocommit transaction with Open-ILS XACT-ID [$old_xact]", INFO);
				$self->pg_commit_xaction($client);
			} else {
				$log->debug("Rolling back old NON-autocommit transaction with Open-ILS XACT-ID [$old_xact]", INFO);
				$self->pg_rollback_xaction($client);
				throw OpenSRF::DomainObject::oilsException->new(
						statusCode => 500,
						status => "Previous transaction rolled back!",
				);
			}
		}
		
		$pg->set_xact_session( $client->session );
		my $xact_id = $pg->current_xact_id;

		$log->debug("Beginning a new trasaction with Open-ILS XACT-ID [$xact_id]", INFO);

		my $dbh = OpenILS::Application::Storage::CDBI->db_Main;
		
		try {
			$dbh->begin_work;

		} catch Error with {
			my $e = shift;
			$log->debug("Failed to begin a new trasaction with Open-ILS XACT-ID [$xact_id]: ".$e, INFO);
			throw $e;
		};


		my $death_cb = $client->session->register_callback(
			death => sub {
				__PACKAGE__->pg_rollback_xaction;
			}
		);

		$log->debug("Registered 'death' callback [$death_cb] for new trasaction with Open-ILS XACT-ID [$xact_id]", DEBUG);

		$client->session->session_data( death_cb => $death_cb );

		if ($self->api_name =~ /autocommit$/o) {
			$pg->current_xact_is_auto(1);
			my $dc_cb = $client->session->register_callback(
				disconnect => sub {
					my $ses = shift;
					$ses->unregister_callback(death => $death_cb);
					__PACKAGE__->pg_commit_xaction;
				}
			);
			$log->debug("Registered 'disconnect' callback [$dc_cb] for new trasaction with Open-ILS XACT-ID [$xact_id]", DEBUG);
			if ($client and $client->session) {
				$client->session->session_data( disconnect_cb => $dc_cb );
			}
		}

		return 1;

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
		my $self = shift;

		local $OpenILS::Application::Storage::WRITE = 1;

		my $xact_id = $pg->current_xact_id;

		my $success = 1;
		try {
			$log->debug("Committing transaction with Open-ILS XACT-ID [$xact_id]", INFO) if ($xact_id);
			my $dbh = OpenILS::Application::Storage::CDBI->db_Main;
			$dbh->commit;

		} catch Error with {
			my $e = shift;
			$log->debug("Failed to commit transaction with Open-ILS XACT-ID [$xact_id]: ".$e, INFO);
			$success = 0;
		};
		
		$pg->current_xact_session->unregister_callback( death => 
			$pg->current_xact_session->session_data( 'death_cb' )
		) if ($pg->current_xact_session);

		if ($pg->current_xact_is_auto) {
			$pg->current_xact_session->unregister_callback( disconnect => 
				$pg->current_xact_session->session_data( 'disconnect_cb' )
			);
		}

		$pg->unset_xact_session;

		return $success;
		
	}
	__PACKAGE__->register_method(
		method		=> 'pg_commit_xaction',
		api_name	=> 'open-ils.storage.transaction.commit',
		api_level	=> 1,
		argc		=> 0,
	);

	sub pg_rollback_xaction {
		my $self = shift;

		local $OpenILS::Application::Storage::WRITE = 1;

		my $xact_id = $pg->current_xact_id;

		my $success = 1;
		try {
			my $dbh = OpenILS::Application::Storage::CDBI->db_Main;
			$log->debug("Rolling back a trasaction with Open-ILS XACT-ID [$xact_id]", INFO);
			$dbh->rollback;

		} catch Error with {
			my $e = shift;
			$log->debug("Failed to roll back trasaction with Open-ILS XACT-ID [$xact_id]: ".$e, INFO);
			$success = 0;
		};
	
		$pg->current_xact_session->unregister_callback( death =>
			$pg->current_xact_session->session_data( 'death_cb' )
		) if ($pg->current_xact_session);

		if ($pg->current_xact_is_auto) {
			$pg->current_xact_session->unregister_callback( disconnect =>
				$pg->current_xact_session->session_data( 'disconnect_cb' )
			);
		}

		$pg->unset_xact_session;

		return $success;
	}
	__PACKAGE__->register_method(
		method		=> 'pg_rollback_xaction',
		api_name	=> 'open-ils.storage.transaction.rollback',
		api_level	=> 1,
		argc		=> 0,
	);

	sub set_savepoint {
		my $self = shift;
		my $client = shift;
		my $sp = shift || 'osrf_savepoint';
		return OpenILS::Application::Storage::CDBI->db_Main->pg_savepoint($sp);
	}
	__PACKAGE__->register_method(
        	method          => 'set_savepoint',
	        api_name        => 'open-ils.storage.savepoint.set',
        	api_level       => 1,
	        argc            => 1,
	);

	sub release_savepoint {
		my $self = shift;
		my $client = shift;
		my $sp = shift || 'osrf_savepoint';
		return OpenILS::Application::Storage::CDBI->db_Main->pg_release($sp);
	}
	__PACKAGE__->register_method(
        	method          => 'release_savepoint',
	        api_name        => 'open-ils.storage.savepoint.release',
        	api_level       => 1,
	        argc            => 1,
	);

	sub rollback_to_savepoint {
		my $self = shift;
		my $client = shift;
		my $sp = shift || 'osrf_savepoint';
		return OpenILS::Application::Storage::CDBI->db_Main->pg_rollback_to($sp);
	}
	__PACKAGE__->register_method(
        	method          => 'rollback_to_savepoint',
	        api_name        => 'open-ils.storage.savepoint.rollback',
        	api_level       => 1,
	        argc            => 1,
	);


	sub copy_create_start {
		my $self = shift;
		my $client = shift;

		local $OpenILS::Application::Storage::WRITE = 1;

		#return undef unless ($pg->current_xact_session);

		my @cols = $self->{cdbi}->columns('Essential');
		if ($NOPRIMARY) {
			my ($p) = $self->{cdbi}->columns('Primary');
			@cols = grep { $_ ne $p } @cols;
		}

		my $col_list = join ',', @cols;

		$log->debug('Starting COPY import for '.$self->{cdbi}->table." ($col_list)", DEBUG);
		$self->{cdbi}->sql_copy_start($self->{cdbi}->table, $col_list)->execute;

		return 1;
	}

	sub copy_create_push {
		my $self = shift;
		my $client = shift;
		my @fm_nodes = @_;

		local $OpenILS::Application::Storage::WRITE = 1;

		#return undef unless ($pg->current_xact_session);

		my @cols = $self->{cdbi}->columns('Essential');
		if ($NOPRIMARY) {
			my ($p) = $self->{cdbi}->columns('Primary');
			@cols = grep { $_ ne $p } @cols;
		}

		my $dbh = $self->{cdbi}->db_Main;
		for my $node ( @fm_nodes ) {
			next unless ($node);
			my $line = join("\t", map { defined($node->$_()) ? $node->$_() : '\N' } @cols);
			$log->debug("COPY line: [$line]",DEBUG);
			$dbh->pg_putline($line."\n");
		}

		return scalar(@fm_nodes);
	}

	sub copy_create_finish {
		my $self = shift;
		my $client = shift;
		my @fm_nodes = @_;

		local $OpenILS::Application::Storage::WRITE = 1;

		#return undef unless ($pg->current_xact_session);

		my $dbh = $self->{cdbi}->db_Main;

		$dbh->pg_endcopy || $log->debug("Could not end COPY with pg_endcopy", WARN);

		$log->debug('COPY import for '.$self->{cdbi}->table." ($col_list) complete", DEBUG);

		return 1;
	}

	sub copy_create {
		my $self = shift;
		my $client = shift;
		my @fm_nodes = @_;

		local $NOPRIMARY = 1;

		copy_create_start(  $self => $client );
		copy_create_push(   $self => $client => @fm_nodes );
		copy_create_finish( $self => $client );

		return scalar(@fm_nodes);
	}

	sub autoprimary {
		my $class = shift;
		my $val = shift;
		$NOPRIMARY = $val if (defined $val);
		return $NOPRIMARY;
	}

}

1;
