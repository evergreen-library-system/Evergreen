#!/usr/bin/perl

# Copyright (C) 2011 Equinox Software, Inc.
# Galen Charlton <gmc@esilibrary.com>
#
# Extract 'comment on' statements from Evergreen's SQL initialization
# scripts.  Useful for updating the comments after an upgrade.
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

unless ($#ARGV == 0) {
    print "usage: $0 sql_file_manifest\n";
    print "output is a set of SQL statements to be run\n";
    print "in an Evergreen database to update schema comments.\n";
    exit(1);
}

open MANIFEST, '<', $ARGV[0];
while (<MANIFEST>) {
    chomp;
    my $file = $_;
    $file =~ s/\s+$//;
    $file =~ s/^\s+//;
    next unless $file ne '' and $file !~ /^#/ and $file ne 'FTS_CONFIG_FILE';
    open IN, '<', $file or next; # errors blithely ignored
    my $contents = join('', <IN>);
    print "$_\n\n" foreach $contents =~ /(comment on .*? is \$\$.*?\$\$;)/sig;
    #my @comments =  $contents =~ /(comment on .*? is \$\$.*?\$\$;)/sig;
    #foreach my $comment (@comments) {
        #print $comment, "\n\n";
    #}
    close IN;
}
close MANIFEST;
