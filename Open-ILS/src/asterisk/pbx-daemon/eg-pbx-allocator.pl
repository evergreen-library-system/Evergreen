#!/usr/bin/perl -w
#
# Copyright (C) 2009 Equinox Software, Inc.
#
# License:
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

=head1 NAME

allocator.pl

=head1 SYNOPSIS

allocator.pl [-h] [-t] [-v] [-c <file>]

 Options:
   -h         display help message
   -t         test mode, no files are moved (impies -v)
   -v         give verbose feedback
   -c <file>  specify config file to be used

=head1 DESCRIPTION

This script is designed to run from crontab on a very frequent basis, perhaps
every minute.  It has two purposes:

=over 8

=item B<1>
Prevent the asterisk server from being overwhelmed by a large number of
Evergreen callfiles in the queue at once.

=item B<2>
Allow call window custom scheduling via crontab.  The guarantee is that
no more than queue_limit calls will be scheduled at the last scheduled run.

=back

By default no output is produced on successful operation.  Error conditions are
output, which should result in email to the system user via crontab.
Reads the same config file as the mediator, looks at the
staging directory for any pending callfiles.  If they exist, checks queue_limit

=head1 CONFIGURATION

See the eg-pbx-daemon.conf.  In particular, set use_allocator to 1 to indicate to
both processes (this one and the mediator) that the allocator is scheduled to run.

=head1 USAGE EXAMPLES

allocator.pl

allocator.pl -c /path/to/eg-pbx-daemon.conf

allocator.pl -t -c /some/other/config.txt

=head1 TODO

=over 8

=item LOAD TEST!!

=back

=head1 AUTHOR

Joe Atzberger,
Equinox Software, Inc.

=cut

package RevalidatorClient;

use strict;
use warnings;

use Sys::Syslog qw/:standard :macros/;
use RPC::XML;
use RPC::XML::Client;
use Data::Dumper;

sub new {
    my $self = bless {}, shift;

    $self->setup(@_);
    return $self;
}

sub setup {
    my ($self, %config) = @_;

    # XXX error_handler, fault_handler, combined_handler
    # such handlers should syslog and die

    $self->{client} = new RPC::XML::Client($config{revalidator_uri});
    $self->{config} = \%config;
}

sub get_event_ids {
    my ($self, $filename) = @_;

    if (not open FH, "<$filename") {
        syslog LOG_ERR, "revalidator client could not open $filename";
        die "revalidator client could not open $filename";
    }

    my $result = 0;
    while (<FH>) {
        next unless /event_ids = ([\d,]+)$/;

        $result = [ map int, split(/,/, $1) ];
    }

    close FH;
    return $result;
}

sub still_valid {
    my ($self, $filename) = @_;
    # Here we want to contact Evergreen's open-ils.trigger service and get
    # a revalidation of the event described in a given file.
    # We'll return 1 for valid, 0 for invalid.

    my $event_ids = $self->get_event_ids($filename) or return 0;

    print STDERR (Dumper($event_ids), "\n") if $self->{config}->{t};

    my $valid_list = $self->{client}->simple_request(
        "open-ils.justintime.events.revalidate", $event_ids
    );

    # NOTE: we require all events to be valid
    return (scalar(@$valid_list) == scalar(@$event_ids)) ? 1 : 0;
}

1;

package main;

use warnings;
use strict;

use Config::General qw/ParseConfig/;
use Getopt::Std;
use Pod::Usage;
use File::Basename qw/basename fileparse/;
use File::Spec;
use Sys::Syslog qw/:standard :macros/;
use Cwd qw/getcwd/;

my %config;
my %opts = (
    c => "/etc/eg-pbx-daemon.conf",
    v => 0,
    t => 0,
);
my $universal_prefix = 'EG';

sub load_config {
    %config = ParseConfig($opts{c});
    # validate
    foreach my $opt (qw/staging_path spool_path/) {
        if (not -d $config{$opt}) {
            die $config{$opt} . " ($opt): no such directory";
        }
    }

    if (!($config{owner} = getpwnam($config{owner})) > 0) {
        die $config{owner} . ": invalid owner";
    }

    if (!($config{group} = getgrnam($config{group})) > 0) {
        die $config{group} . ": invalid group";
    }

    if ($config{universal_prefix}) {
        $universal_prefix = $config{universal_prefix};
        $universal_prefix =~ /^\D/
            or die "Config error: universal_prefix ($universal_prefix) must start with non-integer character";
    }
    unless ($config{use_allocator} or $opts{t}) {
        die "use_allocator not enabled in config file (mediator thinks allocator is not in use).  " .
            "Run in test mode (-t) or enable use_allocator config";
    }
}

sub match_files {
# argument: directory to check for files (default cwd)
# returns: array of pathnames from a given dir
    my $root = @_ ? shift : getcwd();
    my $pathglob = "$root/${universal_prefix}*.call";
    my @matches  = grep {-f $_} <${pathglob}>;    # don't use <$pathglob>, that looks like ref to HANDLE
    $opts{v} and             print scalar(@matches) . " match(es) for path: $pathglob\n";
    $opts{t} or syslog LOG_NOTICE, scalar(@matches) . " match(es) for path: $pathglob";
    return @matches;
}

sub prefixer {
    # guarantee universal prefix on string (but don't add it again)
    my $string = @_ ? shift : '';
    $string =~ /^$universal_prefix\_/ and return $string;
    return $universal_prefix . '_' . $string;
}

sub queue {
    my $stage_name = shift or return;
    $opts{t} or chown($config{owner}, $config{group}, $stage_name) or warn "error changing $stage_name to $config{owner}:$config{group}: $!";

    # if ($timestamp and $timestamp > 0) {
    #     utime $timestamp, $timestamp, $stage_name or warn "error utime'ing $stage_name to $timestamp: $!";
    # }
    my $goodname = prefixer((fileparse($stage_name))[0]);
    my $finalized_filename = File::Spec->catfile($config{spool_path}, $goodname);
    my $msg = sprintf "%40s --> %s", $stage_name, $finalized_filename;
    unless ($opts{t}) {
        unless (rename $stage_name, $finalized_filename) {
            print   STDERR  "$msg  FAILED: $!\n";
            syslog LOG_ERR, "$msg  FAILED: $!";
            return;
        }
        syslog LOG_NOTICE, $msg;
    }
    $opts{v} and print $msg . "\n";
}

sub lock_file_create {
    if (not open FH, ">$config{lock_file}") {
        syslog LOG_ERR, "could not create lock file $config{lock_file}: $!";
        die "could not create lock file!";
    }
    print FH $$, "\n";
    close FH;
}

sub lock_file_release {
    if (not unlink $config{lock_file}) {
        syslog LOG_ERR, "could not remove lock file $config{lock_file}: $!";
        die "could not remove lock file";
    }
}

sub lock_file_test {
    if (open FH, $config{lock_file}) {
        my $pid = <>;
        chomp $pid;
        close FH;

        # process still running?
        if (-d "/proc/$pid") {
            syslog(
                LOG_ERR,
                "lock file present ($config{lock_file}), $pid still running"
            );
            die "lock file present!";
        } else {
            syslog(
                LOG_INFO,
                "lock file present ($config{lock_file}), but $pid no longer running"
            );
            lock_file_release;
        }
    } 
}

sub holiday_test {
    if (exists $config{holidays}) {
        my $now = time;

        if (not open FH, "<" . $config{holidays}) {
            syslog LOG_ERR, "could not open holidays file $config{holidays}: $!";
            die "could not open holidays file $config{holidays}: $!";
        }

        while (<FH>) {
            chomp;
            my ($from, $to) = map(int, split(/,/));

            if ($now >= $from && $now <= $to) {
                close FH;
                syslog LOG_NOTICE, "$config{holidays} says it's a holiday, so i'm quitting";
                exit 0;
            }
        }
        close FH;
    }
}

###  MAIN  ###

getopts('htvc:', \%opts) or pod2usage(2);
pod2usage( -verbose => 2 ) if $opts{h};

$opts{t} and $opts{v} = 1;
$opts{t} and print "TEST MODE\n";
$opts{v} and print "verbose output ON\n";
load_config;    # dies on invalid/incomplete config
openlog basename($0), 'ndelay', LOG_USER;
lock_file_test;
holiday_test;

# there seems to be no potential die()ing or exit()ing after this, failures with the revalidator
# excepting failures with the revalidator
lock_file_create;

my $now = time;
# incoming files sorted by mtime (stat element 9): OLDEST first
my @incoming = sort {(stat($a))[9] <=> (stat($b))[9]} match_files($config{staging_path});
my @outgoing = match_files($config{spool_path});
my @future   = ();

my $raw_count = scalar @incoming;
for (my $i=0; $i<$raw_count; $i++) {
    if ((stat($incoming[$i]))[9] - $now > 0 ) { # if this file is from the future, then so are the subsequent ones
        @future = splice(@incoming,$i);         # i.e., take advantage of having sorted them already
        last;
    }
}

# note: elements of @future not currently used beyond counting them

my  $in_count = scalar @incoming;
my $out_count = scalar @outgoing;
my $limit     = $config{queue_limit} || 0;
my $available = 0;

my @actually  = ();

if ($limit) {
    $available = $limit - $out_count;
    if ($available == 0) {
        $opts{t} or syslog LOG_NOTICE, "Queue is full ($limit)";
    }

    if ($config{revalidator_uri}) { # USE REVALIDATOR
        # Take as many files from @incoming as it takes to fill up @actually
        # with files whose contents describe still-valid events.

        my $revalidator = new RevalidatorClient(%config, %opts);

        for (my $i = 0; $i < $available; $i++) {
            while (@incoming) {
                my $candidate = shift @incoming;

                if ($revalidator->still_valid($candidate)) {
                    unshift @actually, $candidate;
                    last;
                } else {
                    my $newpath = ($config{done_path} || "/tmp") .
                        "/SKIPPED_" . basename($candidate);

                    if ($opts{t}) {
                        print "rename $candidate $newpath\n";
                    } else {
                        rename($candidate, $newpath);
                    }
                }
            }
        }
    } else { # DON'T USE REVALIDATOR
        if ($in_count > $available) {
            # slice down to correct size
            @actually = @incoming[0..($available-1)];
        }
    }
}

# XXX Even without a limit we could still filter by still_valid() in theory,
# but in practive the user should always use a limit.

if ($opts{v}) {
     printf "incoming (total)   : %3d\n", $raw_count;
     printf "incoming (future)  : %3d\n", scalar @future;
     printf "incoming (active)  : %3d\n", $in_count;
     printf "incoming (filtered): %3d\n", scalar @actually;
     printf "queued already     : %3d\n", $out_count;
     printf "queue_limit        : %3d\n", $limit;
     printf "available spots    : %3s\n", ($limit ? $available : 'unlimited');
}

foreach (@actually) {
    queue($_);
}

lock_file_release;

0;
