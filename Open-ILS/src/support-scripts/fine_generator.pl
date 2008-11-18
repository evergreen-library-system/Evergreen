#!/usr/bin/perl
# ---------------------------------------------------------------------
# Fine generator with default grace period param.
# ./object_dumper.pl <bootstrap_config> <lockfile> <grace (default 0)>
# ---------------------------------------------------------------------

use strict; 
use warnings;
use OpenSRF::Utils::JSON;
use OpenSRF::System;

my $config = shift || die "bootstrap config required\n";
my $lockfile = shift || "/tmp/generate_fines-LOCK";
my $grace = shift;

$grace = '' if (!defined($grace) or $grace == 0);
 
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
		->request( 'open-ils.storage.action.circulation.overdue.generate_fines' => $grace );

while (!$r->complete) { $r->recv };

unlink $lockfile;
