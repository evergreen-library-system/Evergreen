#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;

# simple test to send an authority record to marc_stream_importer.pl

my $marc = '00208nz  a2200097o  45 0001001400000003000500014005001700019008004100036040001500077100001800092IISGa11554924IISG20021207110052.0021207n| acannaabn          |n aac     d  aIISGcIISG0 aMaloy, Eileen';

my $socket = IO::Socket::INET->new(
    PeerAddr => 'localhost',
    PeerPort => 5544,
    Proto    => 'tcp'
) or die "socket failure $!\n";

$socket->print($marc) or die "socket print failure: $!\n";

while (chomp(my $line = $socket->getline)) {
    print "Read: $line\n";
}

