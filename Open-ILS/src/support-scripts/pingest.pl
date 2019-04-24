#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright © 2013,2014 Merrimack Valley Library Consortium
# Jason Stephenson <jstephenson@mvlc.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
# TODO: Document with POD.
# This guy parallelizes a reingest.
use strict;
use warnings;
use DBI;
use Getopt::Long;

# Globals for the command line options: --

# You will want to adjust the next two based on your database size,
# i.e. number of bib records as well as the number of cores on your
# database server.  Using roughly number of cores/2 doesn't seem to
# have much impact in off peak times.
my $batch_size = 10000; # records processed per batch
my $max_child  = 8;     # max number of parallel worker processes

my $skip_browse;  # Skip the browse reingest.
my $skip_attrs;   # Skip the record attributes reingest.
my $skip_search;  # Skip the search reingest.
my $skip_facets;  # Skip the facets reingest.
my $skip_display; # Skip the display reingest.
my $start_id;     # start processing at this bib ID.
my $end_id;       # stop processing when this bib ID is reached.
my $max_duration; # max processing duration in seconds
my $help;         # show help text
my $opt_pipe;     # Read record ids from STDIN.
my $record_attrs; # Record attributes for metabib.reingest_record_attributes.

# Database connection options with defaults:
my $db_user = $ENV{PGUSER} || 'evergreen';
my $db_host = $ENV{PGHOST} || 'localhost';
my $db_db = $ENV{PGDATABASE} || 'evergreen';
my $db_password = $ENV{PGPASSWORD} || 'evergreen';
my $db_port = $ENV{PGPORT} || 5432;

GetOptions(
    'user=s'         => \$db_user,
    'host=s'         => \$db_host,
    'db=s'           => \$db_db,
    'password=s'     => \$db_password,
    'port=i'         => \$db_port,
    'batch-size=i'   => \$batch_size,
    'max-child=i'    => \$max_child,
    'skip-browse'    => \$skip_browse,
    'skip-attrs'     => \$skip_attrs,
    'skip-search'    => \$skip_search,
    'skip-facets'    => \$skip_facets,
    'skip-display'   => \$skip_display,
    'start-id=i'     => \$start_id,
    'end-id=i'       => \$end_id,
    'pipe'           => \$opt_pipe,
    'max-duration=i' => \$max_duration,
    'attr=s@'        => \$record_attrs,
    'help'           => \$help
);

sub help {
    print <<HELP;

    $0 --batch-size $batch_size --max-child $max_child \
        --start-id 1 --end-id 500000 --duration 14400

    --batch-size
        Number of records to process per batch

    --max-child
        Max number of worker processes

    --skip-browse
    --skip-attrs
    --skip-search
    --skip-facets
    --skip-display
        Skip the selected reingest component

    --attr
        Specify a record attribute for ingest
        This option can be used more than once to specify multiple
        attributes to ingest.
        This option is ignored if --skip-attrs is also given.

    --start-id
        Start processing at this record ID.

    --end-id
        Stop processing when this record ID is reached

    --pipe
        Read record IDs to reingest from standard input.
        This option conflicts with --start-id and/or --end-id.

    --max-duration
        Stop processing after this many total seconds have passed.

    --help
        Show this help text.

HELP
    exit;
}

help() if $help;

# Check for mutually exclusive options:
if ($opt_pipe && ($start_id || $end_id)) {
    warn('Mutually exclusive options');
    help();
}

my $where = "WHERE deleted = 'f'";
if ($start_id && $end_id) {
    $where .= " AND id BETWEEN $start_id AND $end_id";
} elsif ($start_id) {
    $where .= " AND id >= $start_id";
} elsif ($end_id) {
    $where .= " AND id <= $end_id";
}

# "Gimme the keys!  I'll drive!"
my $q = <<END_OF_Q;
SELECT id
FROM biblio.record_entry
$where
ORDER BY id ASC
END_OF_Q

# Stuffs needed for looping, tracking how many lists of records we
# have, storing the actual list of records, and the list of the lists
# of records.
my ($count, $lists, $records) = (0,0,[]);
my @lol = ();
# To do the browse-only ingest:
my @blist = ();

my $start_epoch = time;

sub duration_expired {
    return 1 if $max_duration && (time - $start_epoch) >= $max_duration;
    return 0;
}

# All of the DBI->connect() calls in this file assume that you have
# configured the PGHOST, PGPORT, PGDATABASE, PGUSER, and PGPASSWORD
# variables in your execution environment.  If you have not, you have
# two options:
#
# 1) configure them
#
# 2) edit the DBI->connect() calls in this program so that it can
# connect to your database.

# Get the input records from either standard input or the database.
my @input;
if ($opt_pipe) {
    while (<STDIN>) {
        # Assume any string of digits is an id.
        if (my @subs = /([0-9]+)/g) {
            push(@input, @subs);
        }
    }
} else {
    my $dbh = DBI->connect("DBI:Pg:database=$db_db;host=$db_host;port=$db_port;application_name=pingest",
                           $db_user, $db_password);
    @input = @{$dbh->selectcol_arrayref($q)};
    $dbh->disconnect();
}

foreach my $record (@input) {
    push(@blist, $record); # separate list of browse-only ingest
    push(@$records, $record);
    if (++$count == $batch_size) {
        $lol[$lists++] = $records;
        $count = 0;
        $records = [];
    }
}
$lol[$lists++] = $records if ($count); # Last batch is likely to be
                                       # small.

# We're going to reuse $count to keep track of the total number of
# batches processed.
$count = 0;

# @running keeps track of the running child processes.
my @running = ();

# We start the browse-only ingest before starting the other ingests.
browse_ingest(@blist) unless ($skip_browse);

# We loop until we have processed all of the batches stored in @lol
# or the maximum processing duration has been reached.
while ($count < $lists) {
    my $duration_expired = duration_expired();

    if (scalar(@lol) && scalar(@running) < $max_child && !$duration_expired) {
        # Reuse $records for the lulz.
        $records = shift(@lol);
        if ($skip_search && $skip_facets && $skip_attrs && $skip_display) {
            $count++;
        } else {
            reingest($records);
        }
    } else {
        my $pid = wait();
        if (grep {$_ == $pid} @running) {
            @running = grep {$_ != $pid} @running;
            $count++;
            print "$count of $lists processed\n";
        }
    }

    if ($duration_expired && scalar(@running) == 0) {
        warn "Exiting on max_duration ($max_duration)\n";
        exit(0);
    }
}

# This subroutine forks a process to do the browse-only ingest on the
# @blist above.  It cannot be parallelized, but can run in parrallel
# to the other ingests.
sub browse_ingest {
    my @list = @_;
    my $pid = fork();
    if (!defined($pid)) {
        die "failed to spawn child";
    } elsif ($pid > 0) {
        # Add our browser to the list of running children.
        push(@running, $pid);
        # Increment the number of lists, because this list was not
        # previously counted.
        $lists++;
    } elsif ($pid == 0) {
        my $dbh = DBI->connect("DBI:Pg:database=$db_db;host=$db_host;port=$db_port;application_name=pingest",
                               $db_user, $db_password);
        my $sth = $dbh->prepare('SELECT metabib.reingest_metabib_field_entries(bib_id := ?, skip_facet := TRUE, skip_browse := FALSE, skip_search := TRUE, skip_display := TRUE)');
        foreach (@list) {
            if ($sth->execute($_)) {
                my $crap = $sth->fetchall_arrayref();
            } else {
                warn ("Browse ingest failed for record $_");
            }
            if (duration_expired()) {
                warn "browse_ingest() stopping on record $_ ".
                    "after max duration reached\n";
                last;
            }
        }
        $dbh->disconnect();
        exit(0);
    }
}

# Fork a child to do the other reingests:

sub reingest {
    my $list = shift;
    my $pid = fork();
    if (!defined($pid)) {
        die "Failed to spawn a child";
    } elsif ($pid > 0) {
        push(@running, $pid);
    } elsif ($pid == 0) {
        my $dbh = DBI->connect("DBI:Pg:database=$db_db;host=$db_host;port=$db_port;application_name=pingest",
                               $db_user, $db_password);
        reingest_attributes($dbh, $list) unless ($skip_attrs);
        reingest_field_entries($dbh, $list)
            unless ($skip_facets && $skip_search && $skip_display);
        $dbh->disconnect();
        exit(0);
    }
}

# Reingest metabib field entries on a list of records.
sub reingest_field_entries {
    my $dbh = shift;
    my $list = shift;
    my $sth = $dbh->prepare('SELECT metabib.reingest_metabib_field_entries(bib_id := ?, skip_facet := ?, skip_browse := TRUE, skip_search := ?, skip_display := ?)');
    # Because reingest uses "skip" options we invert the logic of do variables.
    $sth->bind_param(2, ($skip_facets) ? 1 : 0);
    $sth->bind_param(3, ($skip_search) ? 1 : 0);
    $sth->bind_param(4, ($skip_display) ? 1: 0);
    foreach (@$list) {
        $sth->bind_param(1, $_);
        if ($sth->execute()) {
            my $crap = $sth->fetchall_arrayref();
        } else {
            warn ("metabib.reingest_metabib_field_entries failed for record $_");
        }
    }
}

# Reingest record attributes on a list of records.
sub reingest_attributes {
    my $dbh = shift;
    my $list = shift;
    my $sth = $dbh->prepare(<<END_OF_INGEST
SELECT metabib.reingest_record_attributes(rid := id, prmarc := marc, pattr_list := ?)
FROM biblio.record_entry
WHERE id = ?
END_OF_INGEST
    );
    $sth->bind_param(1, $record_attrs);
    foreach (@$list) {
        $sth->bind_param(2, $_);
        if ($sth->execute()) {
            my $crap = $sth->fetchall_arrayref();
        } else {
            warn ("metabib.reingest_record_attributes failed for record $_");
        }
    }
}
