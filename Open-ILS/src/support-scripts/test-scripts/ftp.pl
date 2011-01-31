#!/usr/bin/perl -IOpen-ILS/src/perlmods/lib/

use strict; use warnings;

use Data::Dumper;

use OpenILS::Utils::RemoteAccount;

my $delay = 1;

my %config = (
    remote_host => 'example.org',
    remote_user => 'some_user',
    remote_password => 'some_user',
    remote_file => './out/testfile',
);

sub content {
    my $time = localtime;
    return <<END_OF_CONTENT;

This is a test file sent at:
$time

END_OF_CONTENT
}

my $x = OpenILS::Utils::RemoteAccount->new(
    remote_host => $config{remote_host},
    remote_user => $config{remote_user},
    content => content(),
);

$Data::Dumper::Indent = 1;
print Dumper($x);

$delay and print "Sleeping $delay seconds\n" and sleep $delay;

$x->put({
    remote_file => $config{remote_file} . "1.$$",
    content     => content(),
}) or die "ERROR: $x->error";

print "\n\n", Dumper($x);

my $file = $x->local_file;
open TEMP, "< $file" or die "Cannot read tempfile $file: $!";
print "\n\ncontent from tempfile $file:\n";
while (my $line = <TEMP>) {
    print $line;
}
close TEMP;

print "\n\nls :\n", join "\n", $x->ls;
print "\n\nls ('out'):\n", join "\n", $x->ls('out');

print "\nThis one should fail (at put)\n";
my $y;

$y = OpenILS::Utils::RemoteAccount->new(
    remote_host     => $config{remote_host},
    remote_user     => $config{remote_user},
    remote_password => 'some_junk',
    content => content(),
    type => 'FTP',
);
print STDERR "ERROR: $@ $! : \n", $y->error, "\n";

print "\n\n", Dumper($y);

$delay and print "Sleeping $delay seconds\n" and sleep $delay;
$y->put({
    remote_file => $config{remote_file} . "2.$$",
    content     => content(),
}) or warn "ERROR with put: " . $y->error;

print "\nThis one might succeed\n";
$y->put({
    remote_file => $config{remote_file} . "3.$$",
    content     => content(),
    remote_password => $config{remote_password},
}) or warn "ERROR with put: " . $y->error;

