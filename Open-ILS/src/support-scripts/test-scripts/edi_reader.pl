#!/usr/bin/perl
use strict; use warnings;
use OpenILS::Utils::EDIReader;
use Data::Dumper;

my $reader = OpenILS::Utils::EDIReader->new;
my $msgs = $reader->read_file(shift());
print Dumper($msgs);

