#!/usr/bin/perl
# ---------------------------------------------------------------------
# Usage:
#   hold_targeter.pl <config_file> <lock_file>
# ---------------------------------------------------------------------

use strict; 
use warnings;
use JSON;
use OpenSRF::System;

my $config = shift || die "bootstrap config required\n";
my $lockfile = shift || "/tmp/hold_targeter-LOCK";

if (-e $lockfile) {
	open(F,$lockfile);
	my $pid = <F>;
	close F;

	open(F,'/bin/ps axo pid|');
	while ( my $p = <F>) {
		chomp($p);
		if ($p =~ s/\s*(\d+)$/$1/o && $p == $pid) {
			die "I seem to be running already at pid $pid.  If not, try again\n";
		}
	}
	close F;
}

open(F, ">$lockfile");
print F $$;
close F;

OpenSRF::System->bootstrap_client( config_file => $config );

my $r = OpenSRF::AppSession
		->create( 'open-ils.storage' )
		->request( 'open-ils.storage.action.hold_request.copy_targeter' => '24h' );

while (!$r->complete) { $r->recv };

unlink $lockfile;

