#!/usr/bin/perl
use strict; 
use warnings;
use Getopt::Long;
use OpenSRF::System;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
#----------------------------------------------------------------
# Batch hold (re)targeter
#
# Usage:
#   ./hold_targeter.pl /openils/conf/opensrf_core.xml
#----------------------------------------------------------------

my $help;
my $osrf_config = '/openils/conf/opensrf_core.xml';
my $lockfile = '/tmp/hold_targeter-LOCK';
my $parallel = 0;
my $verbose = 0;
my $target_all;
my $skip_viable;
my $retarget_interval;
my $recv_timeout = 3600;
my $parallel_init_sleep = 0;

# how often the server sends a summary reply per backend.
my $return_throttle = 50;

GetOptions(
    'osrf-config=s'     => \$osrf_config,
    'lockfile=s'        => \$lockfile,
    'parallel=i'        => \$parallel,
    'verbose'           => \$verbose,
    'target-all'        => \$target_all,
    'skip-viable'       => \$skip_viable,
    'retarget-interval=s'   => \$retarget_interval,
    'parallel-init-sleep=i' => \$parallel_init_sleep,
    'help'              => \$help
) || die "\nSee --help for more\n";

sub help {
    print <<HELP;

Batch hold targeter.

$0 \
    --osrf-config /openils/conf/opensrf_core.xml \
    --lockfile /tmp/hold_targeter-LOCK \
    --parallel 3
    --verbose

General Options

    --osrf-config [/openils/conf/opensrf_core.xml] 
        OpenSRF config file.

    --lockfile [/tmp/hold_targeter-LOCK]
        Full path to lock file


    --verbose
        Print process counts

Targeting Options

    --parallel <parallel-process-count>
        Number of parallel hold processors to run.  This overrides any
        value found in opensrf.xml

    --parallel-init-sleep <seconds=0>
        Number of seconds to wait before starting each subsequent
        parallel targeter instance.  This gives each targeter backend
        time to run the large targetable holds query before the next
        kicks off, so they don't all hit the database at once.

        Defaults to no sleep.

    --target-all
        Target all active holds, regardless of when they were last targeted.

    --skip-viable
        Avoid modifying holds that currently target viable copies.  In
        other words, only (re)target holds in a non-viable state.

    --retarget-interval
        Override the 'circ.holds.retarget_interval' global_flag value. 

HELP

    exit(0);
}

help() if $help;

sub init {

    OpenSRF::System->bootstrap_client(config_file => $osrf_config);
    Fieldmapper->import(
        IDL => OpenSRF::Utils::SettingsClient->new->config_value("IDL"));

    if (!$parallel) {
        my $settings = OpenSRF::Utils::SettingsClient->new;
        $parallel = $settings->config_value(hold_targeter => 'parallel') || 1;
    }
}

sub run_batches {

    # Hanging all of the parallel requests off the same app session
    # lets us operate the same as a MultiSession batch with additional
    # fine-grained controls over the receive timeout and real-time
    # response handling.
    my $ses = OpenSRF::AppSession->create('open-ils.hold-targeter');

    my @reqs;
    for my $slot (1..$parallel) {

        if ($slot > 1 && $parallel_init_sleep) {
            $verbose && print "Sleeping $parallel_init_sleep ".
                "seconds before targeter slot=$slot launch\n";
            sleep $parallel_init_sleep;
        }

        $verbose && print "Starting targeter slot=$slot\n";

        my $req = $ses->request(
            'open-ils.hold-targeter.target', {
                return_count    => 1,
                return_throttle => $return_throttle,
                parallel_count  => $parallel,
                parallel_slot   => $slot,
                skip_viable     => $skip_viable,
                target_all      => $target_all,
                retarget_interval => $retarget_interval
            }
        );

        $req->{_parallel_slot} = $slot; # for grouping/logging below
        push(@reqs, $req);
    }

    while (@reqs) {
        my $start = time;
        $ses->queue_wait($recv_timeout); # wait for a response

        # As a fail-safe, exit if no responses have arrived 
        # within the timeout interval.
        last if (time - $start) >= $recv_timeout;

        for my $req (@reqs) {
            # Pull all responses off the receive queues.
            while (my $resp = $req->recv(0)) {
                $verbose && print sprintf(
                    "Targeter [%d] processed %d holds\n",
                    $req->{_parallel_slot},
                    $resp->content
                );
            }
        }

        @reqs = grep {!$_->complete} @reqs;
    }
}

# ----

die "I seem to be running already. If not remove $lockfile, try again\n" 
    if -e $lockfile;

open(LOCK, ">$lockfile") or die "Cannot open lock file: $lockfile : $@\n";
print LOCK $$ or die "Cannot write to lock file: $lockfile : $@\n";
close LOCK;
   
eval { # Make sure we can delete the lock file.

    init();

    my $start = time;

    run_batches();

    my $minutes = sprintf('%0.2f', (time - $start) / 60.0);

    $verbose && print "Processing took $minutes minutes.\n";
};

warn "Hold processing exited with error: $@\n" if $@;

unlink $lockfile;

