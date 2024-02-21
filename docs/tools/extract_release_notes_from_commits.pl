#!/usr/bin/perl

# Copyright (C) 2024 Equinox Open Library Initiative, Inc.
# Author: Galen Charlton
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

use strict;
use warnings;

use Getopt::Long;

my $branch = "HEAD";
my $prev;
my $show_help;

GetOptions(
    'prev-release-branch=s' => \$prev,
    'current-branch=s'      => \$branch,
    'help'                  => \$show_help,
);

my $help = qq($0: extract release note entries from Git

This utility looks for release note, author, committer,
reviewer, and sponsor information from a stream of commits
in the branch specified by the --current-branch option
from the commit that is the common ancestor of the branch
specified by --prev-release-branch, which will normally be
a tag branch for a previous release.

The output (sent to standard output) is AsciiDoc suitable for
pasting in release notes listing the short release notes (as
entered in Release-note tags in the commit messages), the
contributors (defined as patch authors, committers, and reviewers
from the Signed-off-by tags in the commit messages) and sponsors
(from the Sponsored-by tags in the commit messages).

The output of this script should be proofread before publishing 
release notes.

Usage:

--prev-release-branch=<Git commit reference>
    Branch identifying the previous release to compare
    against. Would be something like origin/tags/rel_3_12_0
--current-branch=<Git commit reference>
    Branch to look for commits on. If not specified, defaults
    to "HEAD"
--help
    Print this help message
);

if ($show_help) {
    print $help;
    exit 0;
}

unless ($prev) {
    print STDERR "Error: missing option --prev-release-branch\n\n";
    print STDERR $help;
    exit 1;
}

my $merge_base = `git merge-base $prev $branch`;
chomp $merge_base;
my $commits = `git log ${merge_base}..${branch} -z --pretty=fuller --reverse`;

my %authors = ();
my %committers = ();
my %reviewers = ();
my %sponsors = ();

print "==== Miscellaneous Release Notes ====\n\n";
foreach my $commit (split /\0/, $commits, -1) {
    my @lines = split /\n/, $commit, -1;

    shift @lines; # ignore the first line
    my ($author) = (shift(@lines) =~ /^Author:\s+(.*?) </);
    $authors{$author}++ if $author;
    shift @lines; # ignore the author date
    my ($committer) = (shift(@lines) =~ /^Commit:\s+(.*?) </);
    $committers{$committer}++ if $author;
    shift @lines; # ignore the commit date
    shift @lines; # ignore the next line
    
    my ($bugnum) = (shift(@lines) =~ /(\d+)/);
    $bugnum //= 'unknown';
    my @notes = ();
    foreach my $line (@lines) {
        if ($line =~ /^\s*release-notes*:(.*)/i) {
            my $note = $1;
            $note =~ s/^\s+//;
            $note =~ s/^://;
            $note =~ s/^\s+//;
            $note =~ s/\s+$//;
            push @notes, $note if $note;
        } elsif ($line =~ /^\s*signed-off-by:\s*(.*?)$/i) {
            my $reviewer = $1;
            $reviewer =~ s/\<.*$//;
            $reviewer =~ s/^\s+//;
            $reviewer =~ s/\s+$//;
            $reviewers{$reviewer}++ if $reviewer;
        } elsif ($line =~ /^\s+sponsored-by:\s*(.*?)\s*$/i) {
            $sponsors{$1}++ if $1;
        } elsif ($line =~ /^\s+co-authored-by:\s*(.*?)\s*$/i) {
            my $coauthor = $1;
            $coauthor =~ s/<.*$//;
            $coauthor =~ s/^\s+//;
            $coauthor =~ s/\s+$//;
            $authors{$coauthor}++ if $coauthor;
        } 
    }
    foreach my $note (@notes) {
        if ($bugnum =~ /^\d+$/) {
            print "* $note (https://bugs.launchpad.net/evergreen/+bug/${bugnum}[Bug $bugnum])\n";
        } else {
            print "* $note\n";
        }
    }
}

my %contributors = ();
foreach my $contributor (keys %authors) {
    $contributors{$contributor} += $authors{$contributor};
}
foreach my $contributor (keys %committers) {
    $contributors{$contributor} += $committers{$contributor};
}
foreach my $contributor (keys %reviewers) {
    $contributors{$contributor} += $reviewers{$contributor};
}

if (%contributors) {
    print "\n==== Contributors ====\n\n";
    foreach my $contributor (sort keys %contributors) {
        print "* $contributor\n";
    }
}
if (%sponsors) {
    print "\n==== Sponsors ====\n\n";
    foreach my $sponsor (sort keys %sponsors) {
        print "* $sponsor\n";
    }
}
