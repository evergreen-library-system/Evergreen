package OpenILS::Application::Storage::Publisher::money;
use base qw/OpenILS::Application::Storage/;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::EX qw/:try/;
use OpenILS::Utils::Fieldmapper;
use DateTime;
use DateTime::Format::ISO8601;

my $log = 'OpenSRF::Utils::Logger';

sub xact_summary {
	my $self = shift;
	my $client = shift;
	my $xact = shift || '';

	my $sql = <<"	SQL";
		SELECT	balance_owed
		  FROM	money.usr_billable_summary_xact
		  WHERE	transaction = ?
	SQL

	return money::billing->db_Main->selectrow_hashref($sql, {}, "$xact");
}
#__PACKAGE__->register_method(
#	api_name        => 'open-ils.storage.money.billing.billable_transaction_summary',
#	api_level       => 1,
#	method          => 'xact_summary',
#);

my $parser = DateTime::Format::ISO8601->new;
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


1;
