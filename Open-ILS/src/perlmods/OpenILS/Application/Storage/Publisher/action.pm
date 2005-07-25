package OpenILS::Application::Storage::Publisher::action;
use base qw/OpenILS::Application::Storage/;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenILS::Utils::Fieldmapper;
use DateTime;
use DateTime::Format::ISO8601;

my $parser = DateTime::Format::ISO8601->new;
my $log = 'OpenSRF::Utils::Logger';

sub grab_overdue {
	my $self = shift;
	my $client = shift;
	my $grace = shift || '';

	my $c_t = action::circulation->table;

	$grace = " - ($grace * (fine_interval))" if ($grace);

	my $sql = <<"	SQL";
		SELECT	*
		  FROM	$c_t
		  WHERE	stop_fines IS NULL
		  	AND due_date < ( CURRENT_TIMESTAMP $grace)
	SQL

	my $sth = action::circulation->db_Main->prepare_cached($sql);
	$sth->execute;

	$client->respond( $_->to_fieldmapper ) for ( map { action::circulation->construct($_) } $sth->fetchall_hash );

	return undef;

}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.circulation.overdue',
	api_level       => 1,
	stream		=> 1,
	method          => 'grab_overdue',
);

sub nearest_hold {
	my $self = shift;
	my $client = shift;
	my $pl = shift;
	my $cp = shift;

	my ($id) = action::hold_request->db_Main->selectrow_array(<<"	SQL", {}, $pl,$cp);
		SELECT	h.id
		  FROM	action.hold_request h
		  	JOIN action.hold_copy_map hm ON (hm.hold = h.id)
		  WHERE	h.pickup_lib = ?
		  	AND hm.target_copy = ?
			AND h.capture_time IS NULL
		ORDER BY h.pickup_lib - (SELECT home_ou FROM actor.usr a WHERE a.id = h.usr), h.request_time
		LIMIT 1
	SQL
	return $id;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.hold_request.nearest_hold',
	api_level       => 1,
	method          => 'nearest_hold',
);

sub next_resp_group_id {
	my $self = shift;
	my $client = shift;

	# XXX This is not replication safe!!!

	my ($id) = action::survey->db_Main->selectrow_array(<<"	SQL");
		SELECT NEXTVAL('action.survey_response_group_id_seq'::TEXT)
	SQL
	return $id;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.survey_response.next_group_id',
	api_level       => 1,
	method          => 'next_resp_group_id',
);

sub patron_circ_summary {
	my $self = shift;
	my $client = shift;
	my $id = ''.shift();

	return undef unless ($id);
	my $c_table = action::circulation->table;
	my $b_table = money::billing->table;

	my $select = <<"	SQL";
		SELECT	COUNT(DISTINCT c.id), SUM( COALESCE(b.amount,0) )
		  FROM	$c_table c
		  	LEFT OUTER JOIN $b_table b ON (c.id = b.xact)
		  WHERE	c.usr = ?
		  	AND c.xact_finish IS NULL
			AND c.stop_fines NOT IN ('CLAIMSRETURNED','LOST')
	SQL

	return action::survey->db_Main->selectrow_arrayref($select, {}, $id);
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.circulation.patron_summary',
	api_level       => 1,
	method          => 'patron_circ_summary',
);

#XXX Fix stored proc calls
sub find_local_surveys {
	my $self = shift;
	my $client = shift;
	my $ou = ''.shift();

	return undef unless ($ou);
	my $s_table = action::survey->table;

	my $select = <<"	SQL";
		SELECT	s.*
		  FROM	$s_table s
		  	JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  WHERE	CURRENT_DATE BETWEEN s.start_date AND s.end_date
	SQL

	my $sth = action::survey->db_Main->prepare_cached($select);
	$sth->execute($ou);

	$client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.survey.all',
	api_level       => 1,
	stream          => 1,
	method          => 'find_local_surveys',
);

#XXX Fix stored proc calls
sub find_opac_surveys {
	my $self = shift;
	my $client = shift;
	my $ou = ''.shift();

	return undef unless ($ou);
	my $s_table = action::survey->table;

	my $select = <<"	SQL";
		SELECT	s.*
		  FROM	$s_table s
		  	JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  WHERE	CURRENT_DATE BETWEEN s.start_date AND s.end_date
		  	AND s.opac IS TRUE;
	SQL

	my $sth = action::survey->db_Main->prepare_cached($select);
	$sth->execute($ou);

	$client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.survey.opac',
	api_level       => 1,
	stream          => 1,
	method          => 'find_opac_surveys',
);

sub find_optional_surveys {
	my $self = shift;
	my $client = shift;
	my $ou = ''.shift();

	return undef unless ($ou);
	my $s_table = action::survey->table;

	my $select = <<"	SQL";
		SELECT	s.*
		  FROM	$s_table s
		  	JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  WHERE	CURRENT_DATE BETWEEN s.start_date AND s.end_date
		  	AND s.required IS FALSE;
	SQL

	my $sth = action::survey->db_Main->prepare_cached($select);
	$sth->execute($ou);

	$client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.survey.optional',
	api_level       => 1,
	stream          => 1,
	method          => 'find_optional_surveys',
);

sub find_required_surveys {
	my $self = shift;
	my $client = shift;
	my $ou = ''.shift();

	return undef unless ($ou);
	my $s_table = action::survey->table;

	my $select = <<"	SQL";
		SELECT	s.*
		  FROM	$s_table s
		  	JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  WHERE	CURRENT_DATE BETWEEN s.start_date AND s.end_date
		  	AND s.required IS TRUE;
	SQL

	my $sth = action::survey->db_Main->prepare_cached($select);
	$sth->execute($ou);

	$client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.survey.required',
	api_level       => 1,
	stream          => 1,
	method          => 'find_required_surveys',
);

sub find_usr_summary_surveys {
	my $self = shift;
	my $client = shift;
	my $ou = ''.shift();

	return undef unless ($ou);
	my $s_table = action::survey->table;

	my $select = <<"	SQL";
		SELECT	s.*
		  FROM	$s_table s
		  	JOIN actor.org_unit_full_path(?) p ON (p.id = s.owner)
		  WHERE	CURRENT_DATE BETWEEN s.start_date AND s.end_date
		  	AND s.usr_summary IS TRUE;
	SQL

	my $sth = action::survey->db_Main->prepare_cached($select);
	$sth->execute($ou);

	$client->respond( $_->to_fieldmapper ) for ( map { action::survey->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.survey.usr_summary',
	api_level       => 1,
	stream          => 1,
	method          => 'find_usr_summary_surveys',
);


sub generate_fines {
	my $self = shift;
	my $client = shift;
	my $grace = shift;
	my $circ = shift;
	
	
	my @circs;
	if ($circ) {
		push @circs,
			$self->method_lookup(
				'open-ils.storage.direct.action.circulation.search_where'
			)->run( { id => $circ, stop_fines => undef } );
	} else {
		push @circs, $self->method_lookup('open-ils.storage.action.circulation.overdue')->run( $grace );
	}

	for my $c (@circs) {
	
		try {
			my $due_dt = $parser->parse_datetime( clense_ISO8601( $c->due_date ) );
	
			my $due = $due_dt->epoch;
			my $now = time;
			my $fine_interval = interval_to_seconds( $c->fine_interval );
	
			if ( interval_to_seconds( $c->fine_interval ) >= interval_to_seconds('1d') ) {	
				my $tz_offset_s = 0;;
				if ($due_dt->strftime('%z') =~ /(-|\+)(\d{2}):?(\d{2})/) {
					$tz_offset_s = $1 . interval_to_seconds( "${2}h ${3}m"); 
				}
	
				$due -= ($due % $fine_interval) + $tz_offset_s;
				$now -= ($now % $fine_interval) + $tz_offset_s;
			}
	
			$client->respond(
				"ARG! Overdue circulation ".$c->id.
				" for item ".$c->target_copy.
				" (user ".$c->usr.").\n".
				"\tItem was due on or before: ".localtime($due)."\n");
	
			my ($fine) = $self->method_lookup('open-ils.storage.direct.money.billing.search')->run(
				{ xact => $c->id, voided => 'f' },
				{ order_by => 'billing_ts DESC', limit => '1' }
			);
	
			my $last_fine;
			if ($fine) {
				$last_fine = $parser->parse_datetime( clense_ISO8601( $fine->billing_ts ) )->epoch;
			} else {
				$last_fine = $due;
				$last_fine += $fine_interval * $grace;
			}
	
			my $pending_fine_count = int( ($now - $last_fine) / $fine_interval ); 
			unless($pending_fine_count) {
				$client->respond( "\tNo fines to create.  " );
				if ($grace && $now < $due + $fine_interval * $grace) {
					$client->respond( "Still inside grace period of: ". seconds_to_interval( $fine_interval * $grace)."\n" );
				} else {
					$client->respond( "Last fine generated for: ".localtime($last_fine)."\n" );
				}
				next;
			}
	
			$client->respond( "\t$pending_fine_count pending fine(s)\n" );
	
			for my $bill (1 .. $pending_fine_count) {
	
				my ($total) = $self->method_lookup('open-ils.storage.direct.money.billable_transaction_summary.retrieve')->run( $c->id );
	
				if ($total && $total->balance_owed > $c->max_fine) {
					$c->stop_fines('MAXFINES');
					$self->method_lookup('open-ils.storage.direct.action.circulation.update')->run( $c );
					$client->respond(
						"\tMaximum fine level of ".$c->max_fine.
						" reached for this circulation.\n".
						"\tNo more fines will be generated.\n" );
					last;
				}
	
				my $billing = new Fieldmapper::money::billing;
				$billing->xact( $c->id );
				$billing->note( "Overdue Fine" );
				$billing->amount( $c->recuring_fine );
	
				$billing->billing_ts(
					DateTime->from_epoch( epoch => $last_fine + $fine_interval * $bill )->strftime('%FT%T%z')
				);
	
				$client->respond(
					"\t\tCreating fine of ".$billing->amount." for period starting ".
					localtime(
						$parser->parse_datetime(
							clense_ISO8601( $billing->billing_ts )
						)->epoch
					)."\n" );
	
				$self->method_lookup('open-ils.storage.direct.money.billing.create')->run( $billing );
			}
		} catch Error with {
			my $e = shift;
			$client->respond( "Error processing overdue circulation [".$c->id."]:\n\n$e\n" );
		};
	}
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.circulation.overdue.generate_fines',
	api_level       => 1,
	stream		=> 1,
	method          => 'generate_fines',
);



my $locations;
my $statuses;
my %cache = (titles => {}, cns => {});
sub hold_copy_targeter {
	my $self = shift;
	my $client = shift;
	my $check_expire = shift;
	my $one_hold = shift;

	$self->{user_filter} = OpenSRF::AppSession->create('open-ils.circ');
	$self->{user_filter}->connect;

	my $time = time;
	$check_expire ||= '12h';
	$check_expire = interval_to_seconds( $check_expire );

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time() - $check_expire);
	$year += 1900;
	$mon += 1;
	my $expire_threshold = sprintf(
		'%s-%0.2d-%0.2dT%0.2d:%0.2d:%0.2d-00',
		$year, $mon, $mday, $hour, $min, $sec
	);

	$self->method_lookup( 'open-ils.storage.transaction.begin')->run($client);

	($statuses) = $self->method_lookup('open-ils.storage.direct.config.copy_status.search.holdable.atomic')->run('t');

	($locations) = $self->method_lookup('open-ils.storage.direct.asset.copy_location.search.holdable.atomic')->run('t');

	my $holds;

	%cache = (titles => {}, cns => {});

	try {
		if ($one_hold) {
			($holds) = $self->method_lookup('open-ils.storage.direct.action.hold_request.search.atomic')
						->run(id => $one_hold);
		} else {
			($holds) = $self->method_lookup('open-ils.storage.direct.action.hold_request.search_where.atomic')
						->run(
							{ capture_time => undef,
							  prev_check_time => { '<=' => $expire_threshold },
							},
							{ order_by => 'request_time,prev_check_time' } );
			push @$holds, $self->method_lookup('open-ils.storage.direct.action.hold_request.search')
						->run(
							{ capture_time => undef,
				  			  prev_check_time => undef },
							{ order_by => 'request_time' } );
		}
	} catch Error with {
		my $e = shift;
		die "Could not retrieve uncaptured hold requests:\n\n$e\n";
	};

	for my $hold (@$holds) {
		try {
			my $copies;

			$copies = $self->metarecord_hold_capture($hold) if ($hold->hold_type eq 'M');
			$copies = $self->title_hold_capture($hold) if ($hold->hold_type eq 'T');
			$copies = $self->volume_hold_capture($hold) if ($hold->hold_type eq 'V');
			$copies = $self->copy_hold_capture($hold) if ($hold->hold_type eq 'C');

			$client->respond("Processing hold ".$hold->id."...\n");
			unless (ref $copies) {
				$client->respond("\tNo copies available for targeting!\n");
				next;
			}

			my @good_copies;
			for my $c (@$copies) {
				next if ( grep {$c->id == $hold->current_copy} @good_copies);
				push @good_copies, $c if ($c);
			}

			$client->respond("\t".scalar(@good_copies)." (non-current) copies available for targeting...\n");

			my $old_best = $hold->current_copy;
			$hold->clear_current_copy;
	
			if (!scalar(@good_copies)) {
				if ( $old_best && grep {$c->id == $hold->current_copy} @$copies ) {
					$client->respond("\tPushing current_copy back onto the targeting list\n");
				push @good_copies, $self->method_lookup('open-ils.storage.direct.asset.copy.retrieve')->run( $old_best );
				} else {
					$client->respond("\tcurrent_copy is no longer available for targeting... NEXT!\n");
					next;
				}
			}

			my $prox_list;
			$$prox_list[0] = [grep {$_->circ_lib == $hold->pickup_lib } @good_copies];
			$copies = [grep {$_->circ_lib != $hold->pickup_lib } @good_copies];

			my $best = $self->choose_nearest_copy($hold, $prox_list);

			if (!$best) {
				$prox_list = $self->create_prox_list( $hold->pickup_lib, $copies );
				$best = $self->choose_nearest_copy($hold, $prox_list);
			}

			if ($old_best) {
				# hold wasn't fulfilled, record the fact
			
				$client->respond("\tHold was not (but should have been) fulfilled by ".$old_best->id.".\n");
				my $ufh = new Fieldmapper::action::unfulfilled_hold_list;
				$ufh->hold( $hold->id );
				$ufh->current_copy( $old_best->id );
				$ufh->circ_lib( $old_best->circ_lib );
				$self->method_lookup('open-ils.storage.direct.action.unfulfilled_hold_list.create')->run( $ufh );
			}

			if ($best) {
				$hold->current_copy( $best->id );
				$client->respond("\tTargeting copy ".$best->id." for hold fulfillment.\n");
			}

			$hold->prev_check_time( 'now' );
			my ($r) = $self->method_lookup('open-ils.storage.direct.action.hold_request.update')->run( $hold );

			$client->respond("\tProcessing of hold ".$hold->id." complete.\n");
			$self->method_lookup('open-ils.storage.transaction.commit')->run;

		} otherwise {
			my $e = shift;
			$client->respond("\tProcessing of hold ".$hold->id." failed!.\n\t\t$e\n");
			$self->method_lookup('open-ils.storage.transaction.rollback')->run;
		};
	}
	$self->{user_filter}->disconnect;
	$self->{user_filter}->finish;
	delete $$self{user_filter};
	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.hold_request.copy_targeter',
	api_level       => 1,
	stream		=> 1,
	method          => 'hold_copy_targeter',
);



sub copy_hold_capture {
	my $self = shift;
	my $hold = shift;
	my $cps = shift;

	if (!defined($cps)) {
		try {
			($cps) = $self->method_lookup('open-ils.storage.direct.asset.copy.search.id.atomic')
						->run( $hold->target );
	
		} catch Error with {
			my $e = shift;
			die "Could not retrieve initial volume list:\n\n$e\n";
		};
	}

	my @copies = grep { $_->holdable == 1  and $_->ref == 0 } @$cps;

	for (my $i = 0; $i < @copies; $i++) {
		next unless $copies[$i];
		
		my $cn = $cache{cns}{$copies[$i]->call_number};
		my $rec = $cache{titles}{$cn->record};
		$copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->status eq $_->id}@$statuses);
		$copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->location eq $_->id}@$locations);
		$copies[$i] = undef if (
			$copies[$i] &&
			!$self->{user_filter}->request(
				'open-ils.circ.permit_hold',
				$hold => $copies[$i],
				{ title => $rec, call_number => $cn }
			)->gather(1)
		);
	}

	@copies = grep { defined $_ } @copies;

	my $count = @copies;

	return unless ($count);
	
	my @old_maps = $self->method_lookup('open-ils.storage.direct.action.hold_copy_map.search.hold')->run( $hold->id );

	$self->method_lookup('open-ils.storage.direct.action.hold_copy_map.batch.delete')->run(@old_maps );
	
	my @maps;
	for my $c (@copies) {
		my $m = new Fieldmapper::action::hold_copy_map;
		$m->hold( $hold->id );
		$m->target_copy( $c->id );
		$m->isnew( 1 );
		push @maps, $m;
	}

	$self->method_lookup('open-ils.storage.direct.action.hold_copy_map.batch.create')->run( @maps );

	return \@copies;
}


sub choose_nearest_copy {
	my $self = shift;
	my $hold = shift;
	my $prox_list = shift;

	for my $p ( 0 .. int( scalar(@$prox_list) - 1) ) {
		next unless (ref $$prox_list[$p]);
		my @capturable = grep { $_->status == 0 } @{ $$prox_list[$p] };
		next unless (@capturable);
		return $capturable[rand(scalar(@capturable))];
	}
}

sub create_prox_list {
	my $self = shift;
	my $lib = shift;
	my $copies = shift;

	my @prox_list;
	for my $cp (@$copies) {
		my ($prox) = $self->method_lookup('open-ils.storage.asset.copy.proximity')->run( $cp->id, $lib );
		$prox_list[$prox] = [] unless defined($prox_list[$prox]);
		push @{$prox_list[$prox]}, $cp;
	}
	return \@prox_list;
}

sub volume_hold_capture {
	my $self = shift;
	my $hold = shift;
	my $vols = shift;

	if (!defined($vols)) {
		try {
			($vols) = $self->method_lookup('open-ils.storage.direct.asset.call_number.search.id.atomic')->run( $hold->target );
	
			$cache{cns}{$_->id} = $_ for (@$vols);

		} catch Error with {
			my $e = shift;
			die "Could not retrieve initial volume list:\n\n$e\n";
		};
	}

	my @v_ids = map { $_->id } @$vols;

	my $cp_list;
	try {
		($cp_list) = $self->method_lookup('open-ils.storage.direct.asset.copy.search.call_number.atomic')->run( \@v_ids );
	
	} catch Error with {
		my $e = shift;
		warn "Could not retrieve copy list:\n\n$e\n";
	};

	$self->copy_hold_capture($hold,$cp_list) if (ref $cp_list and @$cp_list);
}

sub title_hold_capture {
	my $self = shift;
	my $hold = shift;
	my $titles = shift;

	if (!defined($titles)) {
		try {
			($titles) = $self->method_lookup('open-ils.storage.direct.biblio.record_entry.search.id.atomic')->run( $hold->target );
	
			$cache{titles}{$_->id} = $_ for (@$titles);
	
		} catch Error with {
			my $e = shift;
			die "Could not retrieve initial title list:\n\n$e\n";
		};
	}

	my @t_ids = map { $_->id } @$titles;
	my $cn_list;
	try {
		($cn_list) = $self->method_lookup('open-ils.storage.direct.asset.call_number.search.record.atomic')->run( \@t_ids );
	
	} catch Error with {
		my $e = shift;
		warn "Could not retrieve volume list:\n\n$e\n";
	};

	$cache{cns}{$_->id} = $_ for (@$cn_list);

	$self->volume_hold_capture($hold,$cn_list) if (ref $cn_list and @$cn_list);
}

sub metarecord_hold_capture {
	my $self = shift;
	my $hold = shift;

	my $titles;
	try {
		($titles) = $self->method_lookup('open-ils.storage.ordered.metabib.metarecord.records.atomic')->run( $hold->target );
	
	} catch Error with {
		my $e = shift;
		die "Could not retrieve initial title list:\n\n$e\n";
	};

	try {
		my @recs = map {$_->record}
				$self->method_lookup('open-ils.storage.direct.metabib.record_descriptor.search')
						->run( record => $titles, item_type => [split '', $hold->holdable_formats] ); 

		$titles = [];
		($titles) = $self->method_lookup('open-ils.storage.direct.biblio.record_entry.search.id.atomic')->run( \@recs );
	
	} catch Error with {
		my $e = shift;
		die "Could not retrieve format-pruned title list:\n\n$e\n";
	};


	$cache{titles}{$_->id} = $_ for (@$titles);

	$self->title_hold_capture($hold,$titles) if (ref $titles and @$titles);
}

1;
