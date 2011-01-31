#!/usr/bin/perl -IOpen-ILS/src/perlmods/lib

use strict; use warnings;

use Net::SSH2;
use Data::Dumper;

my $delay = 1;

my %config = (
    remote_host => 'example.org',
    remote_user => 'some_user',
    remote_password => 'whatever',
);

$config{remote_file} = '/home/' . $config{remote_user};

my $x = Net::SSH2->new();

$x->connect($config{remote_host}) or die "Could not connect to $config{remote_host}: " . $x->error;
$x->auth(
    publickey  => '/home/opensrf/.ssh/id_rsa.pub',
    privatekey => '/home/opensrf/.ssh/id_rsa',
    username   => $config{remote_user},
#    password   => $config{remote_password},
    rank => [ qw/ publickey hostbased password / ],
) or die "Auth failed for $config{remote_host}: " . $x->error;

print "Reading directory: $config{remote_file}\n";
my $sftp = $x->sftp;
my $dir = $sftp->opendir($config{remote_file}) or die $sftp->error;

print "Directory listing:\n";
my $i = 0;
while (my $line = $dir->read()) {
    printf "%3s)\n", ++$i;
    foreach (sort keys %$line) {
        printf "   %20s => %s\n", $_, $line->{$_};
    }
}

exit;

