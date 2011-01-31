#!/usr/bin/perl -IOpen-ILS/src/perlmods/lib

use strict; use warnings;

use Data::Dumper;

use OpenILS::Utils::RemoteAccount;
use IO::Scalar;
use IO::File;
use Text::Glob qw( match_glob );
$Text::Glob::strict_leading_dot    = 0;
$Text::Glob::strict_wildcard_slash = 0;

my $delay = 1;

my %config = (
    remote_host => 'example.org',
    remote_user => 'some_user',
    remote_password => 'some_user',
    remote_file => '/home/some_user/out/zzz_testfile',
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
# print Dumper($x);

$delay and print "Sleeping $delay seconds\n" and sleep $delay;

$x->put({
    remote_file => $config{remote_file} . "1.$$",
    content     => content(),
}) or die "ERROR: $x->error";

# print "\n\n", Dumper($x);

my $file  = $x->local_file;
my $rfile = $x->remote_file;
open TEMP, "< $file" or die "Cannot read tempfile $file: $!";
print "\n\ncontent from tempfile $file:\n";
while (my $line = <TEMP>) {
    print $line;
}
close TEMP;

my $dir = '/home/' . $config{remote_user} . '/out';
$delay and print "Sleeping $delay seconds\n" and sleep $delay;

my $glob6 = $dir . '/*Q*';

my @res1 = grep {! /\/\.?\.$/} $x->ls({remote_file => $dir});
my @res2 = grep {! /\/\.?\.$/} $x->ls($dir);
my @res3 = grep {! /\/\.?\.$/} $x->ls();
my @res4 = grep {! /\/\.?\.$/} $x->ls('.');
my @res6 = $x->ls($glob6);

my $mismatch = 0;
my $found    = 0;
my $i=0;
print "\n\n";
printf "      %50s | %s\n", "ls ({remote_file => '$dir'})", "ls ('$dir')";
foreach (@res1) {
    my $partner = @res2 ? shift @res2 : '';
    $mismatch++ unless ($_ eq $partner);
    $_ eq $rfile and $found++;
    printf "%4d)%1s%50s %s %s\n", ++$i, ($_ eq $rfile ? '*' : ' '), $_, ($_ eq $partner ? '=' : '!'), $partner;
}

print "\n";
print ($found ? "* The file we just sent" : sprintf("Did not find the file we just sent: \n%58s", $rfile));
print "\nNumber of mismatches: $mismatch\n";
$mismatch and warn "Different style calls to ls got different results.  Please check again.";

$mismatch = $found = $i = 0;
print "\n\n";
printf "      %50s | %s\n", "ls ('.')", "ls ()";
foreach (@res4) {
    my $partner = @res3 ? shift @res3 : '';
    $mismatch++ unless ($_ eq $partner);
    printf "%4d)%1s%50s %s %s\n", ++$i, ($_ eq $rfile ? '*' : ' '), $_, ($_ eq $partner ? '=' : '!'), $partner;
}
print "\n";
print "\nNumber of mismatches: $mismatch\n";
$mismatch and warn "Different style calls to ls got different results.  Please check again.";

$x->debug(1);
my $target = $res1[0] || $res3[0];
my $slurp;

my $io = IO::Scalar->new(\$slurp);
print "Trying to read $target into an IO::Scalar\n";
$x->get({remote_file => $target, local_file => $io});

my $iofile = IO::File->new(">/tmp/io_file_sftp_test.tmp");
print "Trying to read $target into an IO::File\n";
$x->get({remote_file => $target, local_file => $iofile});

my $glob = '*t*';
my @res5 = (match_glob($glob, @res4));
print scalar(@res5) . " of " . scalar(@res4) . " files matching $glob :\n";
$i = 0;
foreach my $orig (@res4) {
    printf "%4d)%1s %s\n", ++$i, ((grep {$orig eq $_} @res5 )? '*' : ' '), $orig;
}
scalar(@res5) and print "\n* Matching file\n";

print scalar(@res6) . " of " . scalar(@res1) . " files matching $glob6 :\n";
$i = 0;
foreach my $orig (@res1) {
    printf "%4d)%1s %s\n", ++$i, ((grep {$orig eq $_} @res6 )? '*' : ' '), $orig;
}
scalar(@res6) and print "\n* Matching file\n";

print join("\n", @res6), "\n";
print "\n\ndone\n";
exit;

