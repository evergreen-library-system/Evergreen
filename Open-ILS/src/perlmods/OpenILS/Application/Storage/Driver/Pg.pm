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

		if (@{$self->nots}) {
			$newterm = '('.$newterm.')&('. join('|', $self->nots) . ')';
		}

		$log->debug("Compiled term is [$newterm]", DEBUG);
		$newterm = OpenILS::Application::Storage::Driver::Pg->quote($newterm);
		$log->debug("Quoted term is [$newterm]", DEBUG);

		$self->{fts_query} = ["to_tsquery('default',$newterm)"];
		$self->{fts_query_nots} = [];
		$self->{fts_op} = '@@';
		$self->{text_col} = shift;
		$self->{fts_col} = shift;

		return $self;
	}

	sub sql_where_clause {
		my $self = shift;
		my $column = $self->fts_col;
		my @output;
	
		my @ranks;
		for my $fts ( $self->fts_query ) {
			push @output, join(' ', $self->fts_col, $self->{fts_op}, $fts);
			push @ranks, "rank($column, $fts)";
		}
		$self->{fts_rank} = \@ranks;
	
		my $phrase_match = $self->sql_exact_phrase_match();
		return join(' AND ', @output) . $phrase_match;
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
		$master_db = DBI->connect("dbi:Pg:host=$$master{host};dbname=$$master{db}",$$master{user},$$master{pw}, \%attrs);
		$master_db->do("SET NAMES '$$master{client_encoding}';") if ($$master{client_encoding});

		$log->debug("Connected to MASTER db '$$master{db} at $$master{host}", INFO);
		
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


{
	package OpenILS::Application::Storage;
	use OpenSRF::Utils::Logger;
	my $log = 'OpenSRF::Utils::Logger';

	my $pg = 'OpenILS::Application::Storage::Driver::Pg';

	sub pg_begin_xaction {
		my $self = shift;
		my $client = shift;

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

		my $xact_id = $pg->current_xact_id;

		try {
			$log->debug("Committing trasaction with Open-ILS XACT-ID [$xact_id]", INFO);
			my $dbh = OpenILS::Application::Storage::CDBI->db_Main;
			$dbh->commit;

		} catch Error with {
			my $e = shift;
			$log->debug("Failed to commit trasaction with Open-ILS XACT-ID [$xact_id]: ".$e, INFO);
			return 0;
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

		return 1;
		
	}
	__PACKAGE__->register_method(
		method		=> 'pg_commit_xaction',
		api_name	=> 'open-ils.storage.transaction.commit',
		api_level	=> 1,
		argc		=> 0,
	);

	sub pg_rollback_xaction {
		my $self = shift;

		my $xact_id = $pg->current_xact_id;
		try {
			my $dbh = OpenILS::Application::Storage::CDBI->db_Main;
			$log->debug("Rolling back a trasaction with Open-ILS XACT-ID [$xact_id]", INFO);
			$dbh->rollback;

		} catch Error with {
			my $e = shift;
			$log->debug("Failed to roll back trasaction with Open-ILS XACT-ID [$xact_id]: ".$e, INFO);
			return 0;
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

		return 1;
	}
	__PACKAGE__->register_method(
		method		=> 'pg_rollback_xaction',
		api_name	=> 'open-ils.storage.transaction.rollback',
		api_level	=> 1,
		argc		=> 0,
	);

	sub copy_create {
		my $self = shift;
		my $client = shift;
		my @fm_nodes = @_;

		return undef unless ($pg->current_xact_session);

		my $cdbi = $self->{cdbi};

		my $pri = $cdbi->columns('Primary');

		my @cols = grep {$_ ne $pri} $cdbi->columns('All');

		my $col_list = join ',', @cols;

		$log->debug('Starting COPY import for '.$cdbi->table." ($col_list)", DEBUG);
		$cdbi->sql_copy_start($cdbi->table, $col_list)->execute;

		my $dbh = $cdbi->db_Main;
		for my $node ( @fm_nodes ) {
			next unless ($node);
			my $line = join("\t", map { defined($node->$_()) ? $node->$_() : '\N' } @cols);
			$log->debug("COPY line: [$line]",DEBUG);
			$dbh->func($line."\n", 'putline');
		}

		$dbh->func('endcopy');

		return scalar(@fm_nodes);
	}

}

{
	#---------------------------------------------------------------------
	package action::survey;
	
	action::survey->table( 'action.survey' );
	action::survey->sequence( 'action.survey_id_seq' );
	
	#---------------------------------------------------------------------
	package action::survey_question;
	
	action::survey_question->table( 'action.survey_question' );
	action::survey_question->sequence( 'action.survey_question_id_seq' );
	
	#---------------------------------------------------------------------
	package action::survey_answer;
	
	action::survey_answer->table( 'action.survey_answer' );
	action::survey_answer->sequence( 'action.survey_answer_id_seq' );
	
	#---------------------------------------------------------------------
	package action::survey_response;
	
	action::survey_response->table( 'action.survey_response' );
	action::survey_response->sequence( 'action.survey_response_id_seq' );
	
	#---------------------------------------------------------------------
	package config::metabib_field;
	
	config::metabib_field->table( 'config.metabib_field' );
	config::metabib_field->sequence( 'config.metabib_field_id_seq' );
	
	#---------------------------------------------------------------------
	package config::bib_source;
	
	config::bib_source->table( 'config.bib_source' );
	config::bib_source->sequence( 'config.bib_source_id_seq' );
	
	#---------------------------------------------------------------------
	package config::identification_type;
	
	config::identification_type->table( 'config.identification_type' );
	config::identification_type->sequence( 'config.identification_type_id_seq' );
	
	#---------------------------------------------------------------------
	package asset::call_number_note;
	
	asset::call_number->table( 'asset.call_number_note' );
	asset::call_number->sequence( 'asset.call_number_note_id_seq' );
	
	#---------------------------------------------------------------------
	package asset::copy_note;
	
	asset::copy->table( 'asset.copy_note' );
	asset::copy->sequence( 'asset.copy_note_id_seq' );

	#---------------------------------------------------------------------
	package asset::call_number;
	
	asset::call_number->table( 'asset.call_number' );
	asset::call_number->sequence( 'asset.call_number_id_seq' );
	
	#---------------------------------------------------------------------
	package asset::copy;
	
	asset::copy->table( 'asset.copy' );
	asset::copy->sequence( 'asset.copy_id_seq' );

	#---------------------------------------------------------------------
	package asset::stat_cat;
	
	asset::stat_cat->table( 'asset.stat_cat' );
	asset::stat_cat->sequence( 'asset.stat_cat_id_seq' );
	
	#---------------------------------------------------------------------
	package asset::stat_cat_entry;
	
	asset::stat_cat_entry->table( 'asset.stat_cat_entry' );
	asset::stat_cat_entry->sequence( 'asset.stat_cat_entry_id_seq' );
	
	#---------------------------------------------------------------------
	package asset::stat_cat_entry_copy_map;
	
	asset::stat_cat_entry_copy_map->table( 'asset.stat_cat_entry_copy_map' );
	asset::stat_cat_entry_copy_map->sequence( 'asset.stat_cat_entry_copy_map_id_seq' );
	
	#---------------------------------------------------------------------
	package biblio::record_entry;
	
	biblio::record_entry->table( 'biblio.record_entry' );
	biblio::record_entry->sequence( 'biblio.record_entry_id_seq' );

	#---------------------------------------------------------------------
	#package biblio::record_marc;
	#
	#biblio::record_marc->table( 'biblio.record_marc' );
	#biblio::record_marc->sequence( 'biblio.record_marc_id_seq' );
	#
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
	package actor::org_unit;
	
	actor::org_unit->table( 'actor.org_unit' );
	actor::org_unit->sequence( 'actor.org_unit_id_seq' );

	#---------------------------------------------------------------------
	package actor::stat_cat;
	
	actor::stat_cat->table( 'actor.stat_cat' );
	actor::stat_cat->sequence( 'actor.stat_cat_id_seq' );
	
	#---------------------------------------------------------------------
	package actor::stat_cat_entry;
	
	actor::stat_cat_entry->table( 'actor.stat_cat_entry' );
	actor::stat_cat_entry->sequence( 'actor.stat_cat_entry_id_seq' );
	
	#---------------------------------------------------------------------
	package actor::stat_cat_entry_user_map;
	
	actor::stat_cat_entry_user_map->table( 'actor.stat_cat_entry_copy_map' );
	actor::stat_cat_entry_user_map->sequence( 'actor.stat_cat_entry_usr_map_id_seq' );
	
	#---------------------------------------------------------------------
	package actor::card;
	
	actor::card->table( 'actor.card' );
	actor::card->sequence( 'actor.card_id_seq' );
	

	#---------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::metarecord;

	metabib::metarecord->table( 'metabib.metarecord' );
	metabib::metarecord->sequence( 'metabib.metarecord_id_seq' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.metarecord.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::metarecord',
	);


	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::title_field_entry;

	metabib::title_field_entry->table( 'metabib.title_field_entry' );
	metabib::title_field_entry->sequence( 'metabib.title_field_entry_id_seq' );
	metabib::title_field_entry->columns( 'FTS' => 'index_vector' );

#	metabib::title_field_entry->add_trigger(
#		before_create => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
#	);
#	metabib::title_field_entry->add_trigger(
#		before_update => \&OpenILS::Application::Storage::Driver::Pg::tsearch2_trigger
#	);

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.title_field_entry.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::title_field_entry',
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::author_field_entry;

	metabib::author_field_entry->table( 'metabib.author_field_entry' );
	metabib::author_field_entry->sequence( 'metabib.author_field_entry_id_seq' );
	metabib::author_field_entry->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.author_field_entry.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::author_field_entry',
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::subject_field_entry;

	metabib::subject_field_entry->table( 'metabib.subject_field_entry' );
	metabib::subject_field_entry->sequence( 'metabib.subject_field_entry_id_seq' );
	metabib::subject_field_entry->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.subject_field_entry.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::subject_field_entry',
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::keyword_field_entry;

	metabib::keyword_field_entry->table( 'metabib.keyword_field_entry' );
	metabib::keyword_field_entry->sequence( 'metabib.keyword_field_entry_id_seq' );
	metabib::keyword_field_entry->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.keyword_field_entry.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::keyword_field_entry',
	);

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	#package metabib::title_field_entry_source_map;

	#metabib::title_field_entry_source_map->table( 'metabib.title_field_entry_source_map' );

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	#package metabib::author_field_entry_source_map;

	#metabib::author_field_entry_source_map->table( 'metabib.author_field_entry_source_map' );

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	#package metabib::subject_field_entry_source_map;

	#metabib::subject_field_entry_source_map->table( 'metabib.subject_field_entry_source_map' );

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	#package metabib::keyword_field_entry_source_map;

	#metabib::keyword_field_entry_source_map->table( 'metabib.keyword_field_entry_source_map' );

	#-------------------------------------------------------------------------------

	#-------------------------------------------------------------------------------
	package metabib::metarecord_source_map;

	metabib::metarecord_source_map->table( 'metabib.metarecord_source_map' );
	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.metarecord_source_map.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::metarecord_source_map',
	);


	#-------------------------------------------------------------------------------
	package metabib::record_descriptor;

	metabib::record_descriptor->table( 'metabib.rec_descriptor' );
	metabib::record_descriptor->sequence( 'metabib.rec_descriptor_id_seq' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.record_descriptor.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::record_descriptor',
	);

	#-------------------------------------------------------------------------------


	#-------------------------------------------------------------------------------
	package metabib::full_rec;

	metabib::full_rec->table( 'metabib.full_rec' );
	metabib::full_rec->sequence( 'metabib.full_rec_id_seq' );
	metabib::full_rec->columns( 'FTS' => 'index_vector' );

	OpenILS::Application::Storage->register_method(
		api_name	=> 'open-ils.storage.direct.metabib.full_rec.batch.create',
		method		=> 'copy_create',
		api_level	=> 1,
		'package'	=> 'OpenILS::Application::Storage',
		cdbi		=> 'metabib::full_rec',
	);


	#-------------------------------------------------------------------------------
}

1;
