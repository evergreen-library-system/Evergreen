#!/usr/bin/perl
# ---------------------------------------------------------------------
# Usage:
#   hold_targeter.pl <config_file> <lock_file>
# ---------------------------------------------------------------------

use strict; 
use warnings;
use OpenSRF::Utils::JSON;
use OpenSRF::System;

my $config = shift || die "bootstrap config required\n";
my $lockfile = shift || "/tmp/hold_targeter-LOCK";

if (-e $lockfile) {
	die "I seem to be running already. If not remove $lockfile, try again\n";
}

open(F, ">$lockfile");
print F $$;
close F;

OpenSRF::System->bootstrap_client( config_file => $config );

my $r = OpenSRF::AppSession
		->create( 'open-ils.storage' )
		->request( 'open-ils.storage.action.hold_request.copy_targeter' => '24h' );

while (!$r->complete) { 
    my $start = time;
    $r->recv(timeout => 3600);
    last if (time() - $start) >= 3600;
};

unlink $lockfile;

