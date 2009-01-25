#!/usr/bin/perl
# ---------------------------------------------------------------------
# Long Overdue script with default period param.
# ./long-overdue-status-update.pl <bootstrap_config> <lockfile> <age (default '180 days')>
# ---------------------------------------------------------------------

use strict; 
use warnings;
use OpenSRF::Utils::JSON;
use OpenSRF::System;

my $config = shift || die "bootstrap config required\n";
my $lockfile = shift || "/tmp/long_overdue-LOCK";
my $age = shift;

$age = '180 days' if (!defined($age));
 
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
		->request( 'open-ils.storage.action.circulation.long_overdue' => $age );

while (!$r->complete) { $r->recv };

unlink $lockfile;
