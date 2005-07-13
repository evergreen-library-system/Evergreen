#!/usr/bin/perl -w
use strict;
use OpenSRF::EX qw/:try/;
use OpenSRF::System;
use OpenSRF::Application;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils;
use Time::Local ('timegm_nocheck');

die "USAGE:\n\t$0 config_file [grace?]\n" unless @ARGV;


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
			'open-ils.storage.direct.money.billing.xact',
			$c->id, { order_by => 'billing_ts DESC' }
		)->gather(1);

		my $last_fine;
		if ($fine) {
			$last_fine = $fine->billing_ts;
		} else {
			# Use Date::Manip here
		}
	}

} catch Error with {
	my $e = shift;
	die "Error processing overdue circulations:\n\n$e\n";
};


