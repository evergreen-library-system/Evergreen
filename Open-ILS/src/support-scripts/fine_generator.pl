#!/usr/bin/perl
# ---------------------------------------------------------------------
# Fine generator
# ./fine_generator.pl <bootstrap_config> <lockfile>
# ---------------------------------------------------------------------

use strict; 
use warnings;
use OpenSRF::Utils::JSON;
use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::MultiSession;

my $config = shift || die "bootstrap config required\n";
my $lockfile = shift || "/tmp/generate_fines-LOCK";
my $grace = shift;

if (defined($grace)) {
    die "Grace period is now defined in the database. It should not be passed to the fine generator.";
}
 
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
my $settings = OpenSRF::Utils::SettingsClient->new;
my $parallel = $settings->config_value( fine_generator => 'parallel' ) || 1; 

if ($parallel == 1) {

    my $r = OpenSRF::AppSession
            ->create( 'open-ils.storage' )
            ->request( 'open-ils.storage.action.circulation.overdue.generate_fines' );

    while (!$r->complete) { $r->recv };

} else {

    my $multi_generator = OpenSRF::MultiSession->new(
        app => 'open-ils.storage', 
        cap => $parallel, 
        api_level => 1,
    );

    my $storage = OpenSRF::AppSession->create("open-ils.storage");
    my $r = $storage->request('open-ils.storage.action.circulation.overdue.id_list');
    while (my $resp = $r->recv(timeout => 600)) {
        my $circ_id = $resp->content;
        $multi_generator->request( 'open-ils.storage.action.circulation.overdue.generate_fines', $circ_id );
    }
    $storage->disconnect();
    $multi_generator->session_wait(1);
    $multi_generator->disconnect;

}

unlink $lockfile;
