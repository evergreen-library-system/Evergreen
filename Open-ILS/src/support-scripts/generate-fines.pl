#!/usr/bin/perl -w
use strict;
use OpenSRF::EX qw/:try/;
use OpenSRF::System;
use OpenSRF::Application;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils qw/:datetime/;
use DateTime;
use DateTime::Format::ISO8601;
use Data::Dumper;

die "USAGE:\n\t$0 config_file [grace?]\n" unless @ARGV;

my $parser = DateTime::Format::ISO8601->new;

# hard coded for now, option later

OpenSRF::System->bootstrap_client( config_file => $ARGV[0] );
my $session = OpenSRF::AppSession->create('open-ils.storage');

my $grace = $ARGV[1];

try {
	my $req = $session->request( 'open-ils.storage.action.circulation.overdue',$grace );
	while (!$req->failed && (my $res = $req->recv)) {
		my $c = $res->content;

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

		print	"\nARG! Overdue circulation ".$c->id.
			" for item ".$c->target_copy.
			" (user ".$c->usr.").\n".
			"\tItem was due on or before: ".localtime($due)."\n";

		my $fine = $session->request(
			'open-ils.storage.direct.money.billing.search',
			{ xact => $c->id, voided => 'f' },
			{ order_by => 'billing_ts DESC', limit => '1' }
		)->gather(1);

		my $last_fine;
		if ($fine) {
			$last_fine = $parser->parse_datetime( clense_ISO8601( $fine->billing_ts ) )->epoch;
		} else {
			$last_fine = $due;
			$last_fine += $fine_interval * $grace;
		}

		my $pending_fine_count = int( ($now - $last_fine) / $fine_interval ); 
		unless($pending_fine_count) {
			print "\tNo fines to create.  ";
			if ($grace && $now < $due + $fine_interval * $grace) {
				print "Still inside grace period of: ".
					seconds_to_interval( $fine_interval * $grace)."\n";
			} else {
				print "Last fine generated for: ".localtime($last_fine)."\n";
			}
			next;
		}

		print "\t$pending_fine_count pending fine(s)\n";

		for my $bill (1 .. $pending_fine_count) {

			my $total = $session->request(
				'open-ils.storage.direct.money.billable_transaction_summary.retrieve',
				$c->id
			)->gather(1);

			if ($total && $total->balance_owed > $c->max_fine) {
				$c->stop_fines('MAXFINES');
				$session->request( 'open-ils.storage.direct.action.circulation.update', $c )->gather(1);
				print "\tMaximum fine level of ".$c->max_fine." reached for this circulation.\n\tNo more fines will be generated.\n";
				last;
			}

			my $billing = new Fieldmapper::money::billing;
			$billing->xact( $c->id );
			$billing->note( "Overdue Fine" );
			$billing->amount( $c->recuring_fine );

			$billing->billing_ts(
				DateTime->from_epoch( epoch => $last_fine + $fine_interval * $bill )->strftime('%FT%T%z')
			);

			print	"\t\tCreating fine of ".$billing->amount." for period starting ".
				localtime(
					$parser->parse_datetime(
						clense_ISO8601( $billing->billing_ts )
					)->epoch
				)."\n";

			$session->request( 'open-ils.storage.direct.money.billing.create', $billing )->gather(1);
		}
	}
} catch Error with {
	my $e = shift;
	die "Error processing overdue circulations:\n\n$e\n";
};


