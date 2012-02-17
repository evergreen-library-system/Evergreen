#!/usr/bin/perl -w

use strict;

use Getopt::Std;

my %result_names = (OK => 0, WARNING => 1, CRITICAL => 2, UNKNOWN => 3);

sub result {
    my ($result_name, $msg) = @_;

    my $code = $result_names{$result_name};

    printf("ASTSPOOL %s - %s\n", $result_name, $msg);
    exit($code);
}

####### main
# command-line options:
# c is for count. more than this number of files
#   in the directory means a critical status. less is ok. there is no warning.
# d is for directory.

my (%opts) = (
    "c" => 8,
    "d" => "/var/spool/asterisk/outgoing"
);

getopts("c:d:", \%opts);

opendir DIR, $opts{d} or result("UNKNOWN", "$opts{d}: $!");
my $count = grep { $_ ne '.' && $_ ne '..' } (readdir DIR);
closedir DIR;

if ($count > $opts{c}) {
    result("CRITICAL", "$count file(s) in $opts{d}");
} else {
    result("OK", "$count file(s) in $opts{d}");
}
