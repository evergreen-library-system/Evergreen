package OpenILS::Application::Storage::Publisher::action;
use base qw/OpenILS::Application::Storage::Publisher/;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::PermitHold;
use DateTime;
use DateTime::Format::ISO8601;


my $parser = DateTime::Format::ISO8601->new;
my $log = 'OpenSRF::Utils::Logger';

sub ou_hold_requests {
	my $self = shift;
	my $client = shift;
	my $ou = shift;

	my $h_table = action::hold_request->table;
	my $c_table = asset::copy->table;
	my $o_table = actor::org_unit->table;

	my $SQL = <<"	SQL";
		SELECT 	h.id
		  FROM	$h_table h
		  	JOIN $c_table cp ON (cp.id = h.current_copy)
			JOIN $o_table ou ON (ou.id = cp.circ_lib)
		  WHERE	ou.id = ?
		  	AND h.capture_time IS NULL
		  ORDER BY h.request_time
	SQL

	my $sth = action::hold_request->db_Main->prepare_cached($SQL);
	$sth->execute($ou);

	$client->respond($_) for (
		map {
			$self
				->method_lookup('open-ils.storage.direct.action.hold_request.retrieve')
				->run($_)
		} map {
			$_->[0]
		} @{ $sth->fetchall_arrayref }
	);
	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.targeted_hold_request.org_unit',
	api_level       => 1,
	argc		=> 1,
	stream		=> 1,
	method          => 'ou_hold_requests',
);


sub overdue_circs {
	my $grace = shift;

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

	return ( map { action::circulation->construct($_) } $sth->fetchall_hash );

}

sub complete_reshelving {
	my $self = shift;
	my $client = shift;
	my $window = shift;

	throw OpenSRF::EX::InvalidArg ("I need an interval of more than 0 seconds!")
		unless (interval_to_seconds( $window ));

	my $circ = action::circulation->table;
	my $cp = asset::copy->table;

	my $sql = <<"	SQL";
		UPDATE	$cp
		  SET	status = 0
		  WHERE	id IN ( SELECT	cp.id
				  FROM	$cp cp
				  	JOIN $circ circ ON (circ.target_copy = cp.id)
				  WHERE	circ.checkin_time IS NOT NULL
				  	AND circ.checkin_time < NOW() - CAST(? AS INTERVAL)
					AND cp.status = 7 )
	SQL

	my $sth = action::circulation->db_Main->prepare_cached($sql);
	$sth->execute($window);

	return $sth->rows;

}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.circulation.reshelving.complete',
	api_level       => 1,
	stream		=> 1,
	argc		=> 1,
	method          => 'complete_reshelving',
);

sub grab_overdue {
	my $self = shift;
	my $client = shift;
	my $grace = shift || '';

	$client->respond( $_->to_fieldmapper ) for ( overdue_circs($grace) );

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
		ORDER BY h.pickup_lib - (SELECT home_ou FROM actor.usr a WHERE a.id = h.usr), h.selection_depth DESC, h.request_time
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

	$log->debug("Retrieving patron summary for id $id", DEBUG);

	my $select = <<"	SQL";
		SELECT	COUNT(DISTINCT c.id), SUM( COALESCE(b.amount,0) )
		  FROM	$c_table c
		  	LEFT OUTER JOIN $b_table b ON (c.id = b.xact AND b.voided = FALSE)
		  WHERE	c.usr = ?
		  	AND c.xact_finish IS NULL
			AND (
				c.stop_fines NOT IN ('CLAIMSRETURNED','LOST')
				OR c.stop_fines IS NULL
			)
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

sub hold_pull_list {
	my $self = shift;
	my $client = shift;
	my $ou = shift;
	my $limit = shift || 10;
	my $offset = shift || 0;

	return undef unless ($ou);
	my $h_table = action::hold_request->table;
	my $a_table = asset::copy->table;

	my $select = <<"	SQL";
		SELECT	h.*
		  FROM	$h_table h
		  	JOIN $a_table a ON (h.current_copy = a.id)
		  WHERE	a.circ_lib = ?
		  	AND h.capture_time IS NULL
		  ORDER BY h.request_time ASC
		  LIMIT $limit
		  OFFSET $offset
	SQL

	my $sth = action::survey->db_Main->prepare_cached($select);
	$sth->execute($ou);

	$client->respond( $_->to_fieldmapper ) for ( map { action::hold_request->construct($_) } $sth->fetchall_hash );

	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.direct.action.hold_request.pull_list.search.current_copy_circ_lib',
	api_level       => 1,
	stream          => 1,
	signature	=> [
		"Returns the holds for a specific library's pull list.",
 		[ [org_unit => "The library's org id", "number"],
		  [limit => 'An optional page size, defaults to 10', 'number'],
		  [offset => 'Offset for paging, defaults to 0, 0 based', 'number'],
		],
		['A list of holds for the stated library to pull for', 'array']
	],
	method          => 'hold_pull_list',
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
		push @circs, action::circulation->search_where( { id => $circ, stop_fines => undef } );
	} else {
		push @circs, overdue_circs($grace);
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
	
			my ($fine) = money::billing->search(
				xact => $c->id, voided => 'f',
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
	
				my ($total) = money::billable_transaction_summary->retrieve( $c->id );
	
				if ($total && $total->balance_owed > $c->max_fine) {
					$c->update({stop_fines => 'MAXFINES'});
					$client->respond(
						"\tMaximum fine level of ".$c->max_fine.
						" reached for this circulation.\n".
						"\tNo more fines will be generated.\n" );
					last;
				}
	
				my $billing = money::billing->create(
					{ xact		=> ''.$c->id,
					  note		=> "Overdue Fine",
					  billing_type	=> "Overdue materials",
					  amount	=> ''.$c->recuring_fine,
					  billing_ts	=> DateTime->from_epoch( epoch => $last_fine + $fine_interval * $bill )->strftime('%FT%T%z')
					}
				);
	
				$client->respond(
					"\t\tCreating fine of ".$billing->amount." for period starting ".
					localtime(
						$parser->parse_datetime(
							clense_ISO8601( $billing->billing_ts )
						)->epoch
					)."\n" );
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



sub new_hold_copy_targeter {
	my $self = shift;
	my $client = shift;
	my $check_expire = shift;
	my $one_hold = shift;

	my $holds;

	try {
		if ($one_hold) {

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

			$holds = [ action::hold_request->search_where(
					{ id => $one_hold,
					  fulfillment_time => undef, 
					  prev_check_time => [ undef, { '<=' => $expire_threshold } ] }
				   ) ];
		} elsif ( $check_expire ) {

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

			$holds = [ action::hold_request->search_where(
							{ capture_time => undef,
							  fulfillment_time => undef,
							  prev_check_time => { '<=' => $expire_threshold },
							},
							{ order_by => 'selection_depth DESC, request_time,prev_check_time' } ) ];
			push @$holds, action::hold_request->search(
							capture_time => undef,
							fulfillment_time => undef,
				  			prev_check_time => undef,
							{ order_by => 'selection_depth DESC, request_time' } );
		} else {
			$holds [ action::hold_request->search(
							capture_time => undef,
							fulfillment_time => undef,
				  			prev_check_time => undef,
							{ order_by => 'selection_depth DESC, request_time' } ) ];
		}
	} catch Error with {
		my $e = shift;
		die "Could not retrieve uncaptured hold requests:\n\n$e\n";
	};

	my @successes;
	for my $hold (@$holds) {
		try {
			#action::hold_request->db_Main->begin_work;
			if ($self->method_lookup('open-ils.storage.transaction.current')->run) {
				$log->debug("Cleaning up after previous transaction\n");
				$self->method_lookup('open-ils.storage.transaction.rollback')->run;
			}
			$self->method_lookup('open-ils.storage.transaction.begin')->run( $client );
			$log->info("Processing hold ".$hold->id."...\n");

			action::hold_copy_map->search( { hold => $hold->id } )->delete_all;
	
			my $all_copies = [];

			# find all the potential copies
			if ($hold->hold_type eq 'M') {
				for my $r ( map
						{$_->record}
						metabib::record_descriptor
							->search(
								record => [ map { $_->id } metabib::metarecord
											->retrieve($hold->target)
											->source_records ],
								item_type => [split '', $hold->holdable_formats]
							)
				) {
					my ($rtree) = $self
						->method_lookup( 'open-ils.storage.biblio.record_entry.ranged_tree')
						->run( $r->id, $hold->usr->home_ou->id, $hold->selection_depth );

					for my $cn ( @{ $rtree->call_numbers } ) {
						push @$all_copies,
							asset::copy->search( id => [map {$_->id} @{ $cn->copies }] );
					}
				}
			} elsif ($hold->hold_type eq 'T') {
				my ($rtree) = $self
					->method_lookup( 'open-ils.storage.biblio.record_entry.ranged_tree')
					->run( $hold->target, $hold->usr->home_ou->id, $hold->selection_depth );

				unless ($rtree) {
					push @successes, { hold => $hold->id, eligible_copies => 0, error => 'NO_RECORD' };
					die 'OK';
				}

				for my $cn ( @{ $rtree->call_numbers } ) {
					push @$all_copies,
						asset::copy->search( id => [map {$_->id} @{ $cn->copies }] );
				}
			} elsif ($hold->hold_type eq 'V') {
				my ($vtree) = $self
					->method_lookup( 'open-ils.storage.asset.call_number.ranged_tree')
					->run( $hold->target, $hold->usr->home_ou->id, $hold->selection_depth );

				push @$all_copies,
					asset::copy->search( id => [map {$_->id} @{ $vtree->copies }] );
					
			} elsif  ($hold->hold_type eq 'C') {

				$all_copies = [asset::copy->retrieve($hold->target)];
			}

			@$all_copies = grep {	$_->status->holdable && 
						$_->location->holdable && 
						$_->holdable
					} @$all_copies;

			# let 'em know we're still working
			$client->status( new OpenSRF::DomainObject::oilsContinueStatus );
			
			if (!ref $all_copies || !@$all_copies) {
				$log->info("\tNo copies available for targeting at all!\n");
				$self->method_lookup('open-ils.storage.transaction.commit')->run;
				push @successes, { hold => $hold->id, eligible_copies => 0, error => 'NO_COPIES' };
				die 'OK';
			}

			my $copies = [];
			for my $c ( @$all_copies ) {
				push @$copies, $c
					if ( OpenILS::Utils::PermitHold::permit_copy_hold(
						{ title => $c->call_number->record->to_fieldmapper,
						  title_descriptor => $c->call_number->record->record_descriptor->next->to_fieldmapper,
						  patron => $hold->usr->to_fieldmapper,
						  copy => $c->to_fieldmapper,
						  requestor => $hold->requestor->to_fieldmapper,
						  request_lib => $hold->request_lib->to_fieldmapper,
						} ));
			}
			my $copy_count = @$copies;
			$client->status( new OpenSRF::DomainObject::oilsContinueStatus );

			# map the potentials, so that we can pick up checkins
			$log->debug( "\tMapping ".scalar(@$copies)." potential copies for hold ".$hold->id);
			action::hold_copy_map->create( { hold => $hold->id, target_copy => $_->id } ) for (@$copies);

			my @good_copies;
			for my $c (@$copies) {
				next if ($c->id == $hold->current_copy);
				push @good_copies, $c if ($c);
			}

			$log->debug("\t".scalar(@good_copies)." (non-current) copies available for targeting...");

			my $old_best = $hold->current_copy;
			$hold->update({ current_copy => undef });
	
			if (!scalar(@good_copies)) {
				$log->info("\tNo (non-current) copies eligible to fill the hold.");
				if ( $old_best && grep { $old_best == $_ } @$copies ) {
					$log->debug("\tPushing current_copy back onto the targeting list");
					push @good_copies, $old_best;
				} else {
					$log->debug("\tcurrent_copy is no longer available for targeting... NEXT HOLD, PLEASE!");
					$self->method_lookup('open-ils.storage.transaction.commit')->run;
					push @successes, { hold => $hold->id, eligible_copies => 0, error => 'NO_TARGETS' };
					die 'OK';
				}
			}

			$client->status( new OpenSRF::DomainObject::oilsContinueStatus );
			my $prox_list = [];
			$$prox_list[0] =
			[
				grep {
					$_->circ_lib == $hold->pickup_lib
				} @good_copies
			];

			$copies = [grep {$_->circ_lib != $hold->pickup_lib } @good_copies];

			my $best = $self->choose_nearest_copy($hold, $prox_list);

			if (!$best) {
				$log->debug("\tNothing at the pickup lib, looking elsewhere among ".scalar(@$copies)." copies");
				$prox_list = $self->create_prox_list( $hold->pickup_lib, $copies );
				$best = $self->choose_nearest_copy($hold, $prox_list);
			}

			$client->status( new OpenSRF::DomainObject::oilsContinueStatus );
			if ($old_best) {
				# hold wasn't fulfilled, record the fact
			
				$log->info("\tHold was not (but should have been) fulfilled by ".$old_best->id);
				action::unfulfilled_hold_list->create(
						{ hold => ''.$hold->id,
						  current_copy => ''.$old_best->id,
						  circ_lib => ''.$old_best->circ_lib,
						});
			}

			if ($best) {
				$hold->update( { current_copy => ''.$best->id } );
				$log->debug("\tUpdating hold [".$hold->id."] with new 'current_copy' [".$best->id."] for hold fulfillment.");
			} else {
				$log->info( "\tThere were no targetable copies for the hold" );
			}

			$hold->update( { prev_check_time => 'now' } );

			$self->method_lookup('open-ils.storage.transaction.commit')->run;
			$log->info("\tProcessing of hold ".$hold->id." complete.");

			push @successes,
				{ hold => $hold->id,
				  old_target => ($old_best ? $old_best->id : undef),
				  eligible_copies => $copy_count,
				  target => ($best ? $best->id : undef) };

		} otherwise {
			my $e = shift;
			if ($e !~ /^OK/o) {
				$log->error("Processing of hold failed:  $e");
				$self->method_lookup('open-ils.storage.transaction.rollback')->run;
			}
		};
	}

	return \@successes;
}
__PACKAGE__->register_method(
	api_name	=> 'open-ils.storage.action.hold_request.copy_targeter',
	api_level	=> 1,
	method		=> 'new_hold_copy_targeter',
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
	$self->{client} = $client;

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


	$statuses ||= [ config::copy_status->search(holdable => 't') ];

	$locations ||= [ asset::copy_location->search(holdable => 't') ];

	my $holds;

	%cache = (titles => {}, cns => {});

	try {
		if ($one_hold) {
			$holds = [ action::hold_request->search(id => $one_hold) ];
		} else {
			$holds = [ action::hold_request->search_where(
							{ capture_time => undef,
							  prev_check_time => { '<=' => $expire_threshold },
							},
							{ order_by => 'request_time,prev_check_time' } ) ];
			push @$holds, action::hold_request->search(
							capture_time => undef,
				  			prev_check_time => undef,
							{ order_by => 'request_time' } );
		}
	} catch Error with {
		my $e = shift;
		die "Could not retrieve uncaptured hold requests:\n\n$e\n";
	};

	for my $hold (@$holds) {
		try {
			#action::hold_request->db_Main->begin_work;
			if ($self->method_lookup('open-ils.storage.transaction.current')->run) {
				$client->respond("Cleaning up after previous transaction\n");
				$self->method_lookup('open-ils.storage.transaction.rollback')->run;
			}
			$self->method_lookup('open-ils.storage.transaction.begin')->run( $client );
			$client->respond("Processing hold ".$hold->id."...\n");

			my $copies;

			$copies = $self->metarecord_hold_capture($hold) if ($hold->hold_type eq 'M');
			$self->{client}->status( new OpenSRF::DomainObject::oilsContinueStatus );

			$copies = $self->title_hold_capture($hold) if ($hold->hold_type eq 'T');
			$self->{client}->status( new OpenSRF::DomainObject::oilsContinueStatus );
			
			$copies = $self->volume_hold_capture($hold) if ($hold->hold_type eq 'V');
			$self->{client}->status( new OpenSRF::DomainObject::oilsContinueStatus );
			
			$copies = $self->copy_hold_capture($hold) if ($hold->hold_type eq 'C');

			unless (ref $copies || !@$copies) {
				$client->respond("\tNo copies available for targeting at all!\n");
			}

			my @good_copies;
			for my $c (@$copies) {
				next if ( grep {$c->id == $hold->current_copy} @good_copies);
				push @good_copies, $c if ($c);
			}

			$client->respond("\t".scalar(@good_copies)." (non-current) copies available for targeting...\n");

			my $old_best = $hold->current_copy;
			$hold->update({ current_copy => undef });
	
			if (!scalar(@good_copies)) {
				$client->respond("\tNo (non-current) copies available to fill the hold.\n");
				if ( $old_best && grep {$c->id == $hold->current_copy} @$copies ) {
					$client->respond("\tPushing current_copy back onto the targeting list\n");
					push @good_copies, asset::copy->retrieve( $old_best );
				} else {
					$client->respond("\tcurrent_copy is no longer available for targeting... NEXT HOLD, PLEASE!\n");
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
				action::unfulfilled_hold_list->create(
						{ hold => ''.$hold->id,
						  current_copy => ''.$old_best->id,
						  circ_lib => ''.$old_best->circ_lib,
						});
			}

			if ($best) {
				$hold->update( { current_copy => ''.$best->id } );
				$client->respond("\tTargeting copy ".$best->id." for hold fulfillment.\n");
			}

			$hold->update( { prev_check_time => 'now' } );
			$client->respond("\tUpdating hold ".$hold->id." with new 'current_copy' for hold fulfillment.\n");

			$client->respond("\tProcessing of hold ".$hold->id." complete.\n");
			$self->method_lookup('open-ils.storage.transaction.commit')->run;

			#action::hold_request->dbi_commit;

		} otherwise {
			my $e = shift;
			$log->error("Processing of hold failed:  $e");
			$client->respond("\tProcessing of hold failed!.\n\t\t$e\n");
			$self->method_lookup('open-ils.storage.transaction.rollback')->run;
			#action::hold_request->dbi_rollback;
		};
	}

	$self->{user_filter}->disconnect;
	$self->{user_filter}->finish;
	delete $$self{user_filter};
	return undef;
}
__PACKAGE__->register_method(
	api_name        => 'open-ils.storage.action.hold_request.copy_targeter',
	api_level       => 0,
	stream		=> 1,
	method          => 'hold_copy_targeter',
);


sub copy_hold_capture {
	my $self = shift;
	my $hold = shift;
	my $cps = shift;

	if (!defined($cps)) {
		try {
			$cps = [ asset::copy->search( id => $hold->target ) ];
		} catch Error with {
			my $e = shift;
			die "Could not retrieve initial volume list:\n\n$e\n";
		};
	}

	my @copies = grep { $_->holdable } @$cps;

	for (my $i = 0; $i < @$cps; $i++) {
		next unless $$cps[$i];
		
		my $cn = $cache{cns}{$copies[$i]->call_number};
		my $rec = $cache{titles}{$cn->record};
		$copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->status eq $_->id}@$statuses);
		$copies[$i] = undef if ($copies[$i] && !grep{ $copies[$i]->location eq $_->id}@$locations);
		$copies[$i] = undef if (
			!$copies[$i] ||
			!$self->{user_filter}->request(
				'open-ils.circ.permit_hold',
				$hold->to_fieldmapper, do {
					my $cp_fm = $copies[$i]->to_fieldmapper;
					$cp_fm->circ_lib( $copies[$i]->circ_lib->to_fieldmapper );
					$cp_fm->location( $copies[$i]->location->to_fieldmapper );
					$cp_fm->status( $copies[$i]->status->to_fieldmapper );
					$cp_fm;
				},
				{ title => $rec->to_fieldmapper,
				  usr => actor::user->retrieve($hold->usr)->to_fieldmapper,
				  requestor => actor::user->retrieve($hold->requestor)->to_fieldmapper,
				})->gather(1)
		);
		$self->{client}->status( new OpenSRF::DomainObject::oilsContinueStatus );
	}

	@copies = grep { $_ } @copies;

	my $count = @copies;

	return unless ($count);
	
	action::hold_copy_map->search( { hold => $hold->id } )->delete_all;
	
	my @maps;
	$self->{client}->respond( "\tMapping ".scalar(@copies)." eligable copies for hold ".$hold->id."\n");
	for my $c (@copies) {
		push @maps, action::hold_copy_map->create( { hold => $hold->id, target_copy => $c->id } );
	}
	$self->{client}->respond( "\tA total of ".scalar(@maps)." mapping were created for hold ".$hold->id."\n");

	return \@copies;
}


sub choose_nearest_copy {
	my $self = shift;
	my $hold = shift;
	my $prox_list = shift;

	for my $p ( 0 .. int( scalar(@$prox_list) - 1) ) {
		next unless (ref $$prox_list[$p]);
		my @capturable = grep { $_->status == 0 || $_->status == 7 } @{ $$prox_list[$p] };
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
		next unless (defined($prox));
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
			$vols = [ asset::call_number->search( id => $hold->target ) ];
			$cache{cns}{$_->id} = $_ for (@$vols);
		} catch Error with {
			my $e = shift;
			die "Could not retrieve initial volume list:\n\n$e\n";
		};
	}

	my @v_ids = map { $_->id } @$vols;

	my $cp_list;
	try {
		$cp_list = [ asset::copy->search( call_number => \@v_ids ) ];
	
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
			$titles = [ biblio::record_entry->search( id => $hold->target ) ];
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
		$titles = [ metabib::metarecord_source_map->search( metarecord => $hold->target) ];
	
	} catch Error with {
		my $e = shift;
		die "Could not retrieve initial title list:\n\n$e\n";
	};

	try {
		my @recs = map {$_->record} metabib::record_descriptor->search( record => $titles, item_type => [split '', $hold->holdable_formats] ); 

		$titles = [ biblio::record_entry->search( id => \@recs ) ];
	
	} catch Error with {
		my $e = shift;
		die "Could not retrieve format-pruned title list:\n\n$e\n";
	};


	$cache{titles}{$_->id} = $_ for (@$titles);
	$self->title_hold_capture($hold,$titles) if (ref $titles and @$titles);
}

1;
