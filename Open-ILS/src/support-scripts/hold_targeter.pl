#!/usr/bin/perl
use strict; 
use warnings;
use Getopt::Long;
use OpenSRF::System;
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::Fieldmapper;
$ENV{OSRF_LOG_CLIENT} = 1;
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
my $retarget_interval;
my $soft_retarget_interval;
my $next_check_interval;
my $recv_timeout = 3600;
my $parallel_init_sleep = 0;

# how often the server sends a summary reply per backend.
my $return_throttle = 500;

GetOptions(
    'help'                  => \$help,
    'osrf-config=s'         => \$osrf_config,
    'lockfile=s'            => \$lockfile,
    'parallel=i'            => \$parallel,
    'verbose'               => \$verbose,
    'parallel-init-sleep=i' => \$parallel_init_sleep,
    'retarget-interval=s'   => \$retarget_interval,
    'next-check-interval=s'    => \$next_check_interval,
    'soft-retarget-interval=s' => \$soft_retarget_interval,
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

    --soft-retarget-interval
        Holds whose previous check time sits between the
        --soft-retarget-interval and the --retarget-interval are 
        treated like this:
        
        1. The list of potential copies is updated for all matching holds.
        2. Holds that have a viable target are otherwise left untouched,
           including their prev_check_time.
        3. Holds with no viable target are fully retargeted.

    --next-check-interval
        Specify how long after the current run time the targeter will
        retarget the currently affected holds.  Applying a specific
        interval is useful when the retarget_interval is shorter than
        the time between targeter runs.

        This value is used to determine if an org unit will be closed
        during the next iteration of the targeter.  It overrides the
        default behavior of calculating the next retarget time from the
        retarget-interval.

    --retarget-interval
        Retarget holds whose previous check time occured before the
        requested interval.
        Overrides the 'circ.holds.retarget_interval' global_flag value. 

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
                retarget_interval      => $retarget_interval,
                next_check_interval    => $next_check_interval,
                soft_retarget_interval => $soft_retarget_interval
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
                die $req->failed . "\n" if $req->failed;

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

