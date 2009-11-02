#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright (C) 2009 Equinox Software, Inc
# Author: Bill Erickson <erickson@esilibrary.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
use strict;
use warnings;
use Getopt::Long;
use OpenSRF::AppSession;
use OpenSRF::Utils::JSON;
use OpenSRF::EX qw(:try);
require 'oils_header.pl';

my $opt_lockfile = '/tmp/action-trigger-LOCK';
my $opt_osrf_config = '/openils/conf/opensrf_core.xml';
my $opt_custom_filter = '/openils/conf/action_trigger_filters.json';
my $opt_run_pending = 0;
my $opt_debug_stdout = 0;
my $opt_help = 0;
my $opt_hooks;
my $opt_process_hooks = 0;

GetOptions(
    'osrf-config=s' => \$opt_osrf_config,
    'run-pending' => \$opt_run_pending,
    'hooks=s' => \$opt_hooks,
    'process-hooks' => \$opt_process_hooks,
    'debug-stdout' => \$opt_debug_stdout,
    'custom-filters=s' => \$opt_custom_filter,
    'lock-file=s' => \$opt_lockfile,
    'help' => \$opt_help,
);


# typical passive hook filters
my $hook_handlers = {

    # default overdue circulations
    'checkout.due' => {
        context_org => 'circ_lib',
        filter => {
            checkin_time => undef, 
            '-or' => [
                {stop_fines => ['MAXFINES', 'LONGOVERDUE']}, 
                {stop_fines => undef}
            ]
        }
    }
};

if ($opt_custom_filter) {
    open FILTERS, $opt_custom_filter;
    $hook_handlers = OpenSRF::Utils::JSON->JSON2perl(join('',(<FILTERS>)));
    close FILTERS;
}

sub help {
    print <<HELP;

$0 : Create and process action/trigger events

    --osrf-config=<config_file>
        OpenSRF core config file.  Defaults to:
            /openils/conf/opensrf_core.xml

    --custom-filters=<filter_file>
        File containing a JSON Object which describes any hooks that should
        use a user-defined filter to find their target objects.  Defaults to:
            /openils/conf/action_trigger_filters.json

    --run-pending
        Run pending events

    --process-hooks
        Create hook events

    --hooks=hook1[,hook2,hook3,...]
        Define which hooks to create events for.  If none are defined,
        it defaults to the list of hooks defined in the --custom-filters option.

    --debug-stdout
        Print server responses to stdout (as JSON) for debugging

    --lock-file=<file_name>
        Lock file

    --help
        Show this help

    Examples:

        # To run all pending events.  This is what you tell CRON to run at
        # regular intervals
        perl $0 --osrf-config /openils/conf/opensrf_core.xml --run-pending

        # To batch create all "checkout.due" events
        perl $0 --osrf-config /openils/conf/opensrf_core.xml --hooks checkout.due

HELP
}


# create events for the specified hooks using the configured filters and context orgs
sub process_hooks {
    return unless $opt_process_hooks;

    my @hooks = ($opt_hooks) ? split(',', $opt_hooks) : keys(%$hook_handlers);
    my $ses = OpenSRF::AppSession->create('open-ils.trigger');

    for my $hook (@hooks) {
    
        my $config = $$hook_handlers{$hook} or next;
        my $method = 'open-ils.trigger.passive.event.autocreate.batch';
        $method =~ s/passive/active/ if $config->{active};
        
        my $req = $ses->request($method, $hook, $config->{context_org}, $config->{filter});
        while(my $resp = $req->recv(timeout => 1800)) {
            if($opt_debug_stdout) {
                print OpenSRF::Utils::JSON->perl2JSON($resp->content) . "\n";
            }
        }
    }
}

sub run_pending {
    return unless $opt_run_pending;
    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    my $req = $ses->request('open-ils.trigger.event.run_all_pending');
    while(my $resp = $req->recv(timeout => 600)) {
        if($opt_debug_stdout) {
            print OpenSRF::Utils::JSON->perl2JSON($resp->content) . "\n";
        }
    }
}

help() and exit if $opt_help;
help() and exit unless ($opt_run_pending or $opt_hooks);

# check / set the lockfile
die "I'm already running with lockfile $opt_lockfile\n" if -e $opt_lockfile;
open(F, ">$opt_lockfile") or die "Unable to open lockfile $opt_lockfile for writing\n";
print F $$;
close F;

try {
    osrf_connect($opt_osrf_config);
    process_hooks();
    run_pending();
} otherwise {
    my $e = shift;
    warn "$e\n";
};

unlink $opt_lockfile;



