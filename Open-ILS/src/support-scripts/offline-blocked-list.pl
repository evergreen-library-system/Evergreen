#!/usr/bin/perl
use strict;

use OpenSRF::EX qw(:try);
use OpenSRF::System;
use OpenSRF::AppSession;

my $config = shift || die "Please specify a config file\n";

OpenSRF::System->bootstrap_client( config_file => $config );

my $ses = OpenSRF::AppSession->connect( 'open-ils.storage' );

my $lost = $ses->request( 'open-ils.storage.actor.user.lost_barcodes' );
while (my $resp = $lost->recv ) {
	print $resp->content . " L\n";
}
$lost->finish;

my $expired = $ses->request( 'open-ils.storage.actor.user.expired_barcodes' );
while (my $resp = $expired->recv ) {
	print $resp->content . " E\n";
}
$expired->finish;

my $barred = $ses->request( 'open-ils.storage.actor.user.barred_barcodes' );
while (my $resp = $barred->recv ) {
	print $resp->content . " B\n";
}
$barred->finish;

my $penalized = $ses->request( 'open-ils.storage.actor.user.penalized_barcodes' );
while (my $resp = $penalized->recv ) {
	print $resp->content . " D\n";
}
$penalized->finish;

$ses->disconnect;
$ses->finish;

