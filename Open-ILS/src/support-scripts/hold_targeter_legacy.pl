#!/usr/bin/perl
# ---------------------------------------------------------------------
# Usage:
#   hold_targeter.pl <config_file> <lock_file>
# ---------------------------------------------------------------------

use strict; 
use warnings;
use OpenSRF::Utils::JSON;
use OpenSRF::System;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::MultiSession;
use OpenSRF::EX qw(:try);

my $config = shift || die "bootstrap config required\n";
my $lockfile = shift || "/tmp/hold_targeter-LOCK";

if (-e $lockfile) {
    die "I seem to be running already. If not remove $lockfile, try again\n";
}

open(F, ">$lockfile");
print F $$;
close F;

my $settings;
my $parallel;

try {
    OpenSRF::System->bootstrap_client( config_file => $config );
    $settings = OpenSRF::Utils::SettingsClient->new;
    $parallel = $settings->config_value( hold_targeter => 'parallel' ) || 1;
} otherwise {
    my $e = shift;
    warn "$e\n";
    unlink $lockfile;
    exit 1;
};

if ($parallel == 1) {

    try {
        my $r = OpenSRF::AppSession
                   ->create( 'open-ils.storage' )
                   ->request( 'open-ils.storage.action.hold_request.copy_targeter' => '24h' );

        while (!$r->complete) { 
            my $start = time;
            $r->recv(timeout => 3600);
            last if (time() - $start) >= 3600;
        };
    } otherwise {
        my $e = shift;
        warn "Failure in single-session targeter:\n$e\n";
    };

} else {

    try {
        my $multi_targeter = OpenSRF::MultiSession->new(
            app => 'open-ils.storage', 
            cap => $parallel, 
            api_level => 1,
            session_hash_function => sub {
                my $ses = shift;
                my $req = shift;
                return $_[-1]; # last parameter is the ID of the metarecord associated with the
                               # request's target; using this as the hash function value ensures
                               # that parallel targeters won't try to simultaneously handle two
                               # hold requests that have overlapping pools of copies that could
                               # fill those requests
            }
        );
    
        my $storage = OpenSRF::AppSession->create("open-ils.storage");
    
        my $r = $storage->request('open-ils.storage.action.hold_request.targetable_holds.id_list', '24h');
        while ( my $h = $r->recv ) {
            if ($r->failed) {
                print $r->failed->stringify . "\n";
                last;
            }
            if (my $hold = $h->content) {
                $multi_targeter->request( 'open-ils.storage.action.hold_request.copy_targeter', '', $hold->[0], $hold->[1]);
            }
        }
    
        $storage->disconnect();
    
        $multi_targeter->session_wait(1);
        $multi_targeter->disconnect;
    } otherwise {
        my $e = shift;
        warn "Failure in multi-session targeter:\n$e\n";
    }
}

unlink $lockfile;

