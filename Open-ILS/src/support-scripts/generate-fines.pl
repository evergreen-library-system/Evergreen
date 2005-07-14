#!/usr/bin/perl -w
use strict;
use OpenSRF::EX qw/:try/;
use OpenSRF::System;
use OpenSRF::Application;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils;
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

		print	"ARG! overdue circ ".$c->id.
			" for item ".$c->target_copy.
			" : was due at ".$c->due_date."\n";

		my $fine = $session->request(
			'open-ils.storage.direct.money.billing.search.xact',
			$c->id, { order_by => 'billing_ts DESC' }
		)->gather(1);

		my $now = time;
		my $fine_interval = OpenSRF::Utils->interval_to_seconds( $c->fine_interval );

		my $last_fine;
		if ($fine) {
			$last_fine = $parser->parse_datetime( OpenSRF::Utils->clense_ISO8601( $fine->billing_ts ))->epoch;
		} else {
			# Use Date::Manip here
			$last_fine = $parser->parse_datetime( OpenSRF::Utils->clense_ISO8601( $c->due_date ))->epoch;
			$last_fine += $fine_interval if ($grace);
		}

		my $pending_fine_count = int( ($now - $last_fine) / $fine_interval ); 
		next unless($pending_fine_count);

		print "Circ ".$c->id." has $pending_fine_count pending fine(s).\n";

		for my $bill (1 .. $pending_fine_count) {

			my $total = $session->request(
				'open-ils.storage.money.billing.billable_transaction_summary',
				$c->id
			)->gather(1);

			if ($total && $total->{balance_owed} > $c->max_fine) {
				$c->stop_fines('MAXFINES');
				
				$session->request(
					'open-ils.storage.direct.action.circulation.update',
					$c
				)->gather(1);

				last;
			}

			my $billing = new Fieldmapper::money::billing;
			$billing->xact( $c->id );
			$billing->note( "Overdue Fine" );
			$billing->amount( $c->recuring_fine );
			$billing->billing_ts(
				DateTime->from_epoch(
					epoch => $last_fine + $fine_interval * $bill
				)->strftime('%FT%T%z')
			);

			$session->request(
				'open-ils.storage.direct.money.billing.create',
				$billing
			)->gather(1);

		}
	}

} catch Error with {
	my $e = shift;
	die "Error processing overdue circulations:\n\n$e\n";
};


