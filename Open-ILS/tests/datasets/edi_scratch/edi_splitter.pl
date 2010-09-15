#!/usr/bin/perl
#
#
# Purpose here is to break up EDI messages to make them more readable
# (i.e., not all on one line).
#

use warnings;
use strict;


my @unindented = qw( LIN BGM );

my $delim = "'";
while (my $line = <>) {
    foreach (split $delim, $line) {
        '+' eq substr($_,3,1) or warn "Line $. missing '+' delimiter as 4th character: $_";
        my $tag = substr($_,0,3) or warn "Line $. Unexpectedly short: $_";
        unless ($tag =~ /^UN\S/ or grep {$_ eq $tag} @unindented) {
            print "\t";
        }
        print "$_$delim\n";
    }
    print '=' x 70, "\n\n";
}

