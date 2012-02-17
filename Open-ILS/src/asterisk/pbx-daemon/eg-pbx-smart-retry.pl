#!/usr/bin/perl -w
use strict;

# Even though this program looks like a daemon, you don't actually want to
# run it as one.  It's meant to be called (with -d option) from an Asterisk
# dialplan and return immediately, doing its work in the background.
#
# That's why it *looks* like a daemon, but you don't run this from your
# system init scripts or anything.
#
# This script's purpose is to remove callfiles from the spool after each
# attempt Asterisk makes with it.  If the callfile dictates, say, 5 attempts
# and the first attempt results in a busy signal or something, Asterisk will
# update the callfile (within smart_retry_delay seconds) to reduce the number
# of remaining attempts, and then we take this callfile out of the spool
# and put it back in the staging path so that we can use Asterisk to make
# some other phone calls while we wait for the retry timeout on this call
# to expire.

use Getopt::Std;
use File::Basename;
use Config::General qw/ParseConfig/;
use POSIX 'setsid';

sub daemonize {
   chdir '/'               or die "Can't chdir to /: $!";
   open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
   open STDOUT, '>/dev/null'
                           or die "Can't write to /dev/null: $!";
   defined(my $pid = fork) or die "Can't fork: $!";
   exit if $pid;
   setsid                  or die "Can't start a new session: $!";
   open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
}

sub smart_retry {
    my ($config, $filename) = @_;

    my $delay = $config->{smart_retry_delay} || 5;
    my $padding = $config->{smart_retry_padding} || 5;

    my $src = $config->{spool_path} . '/' . $filename;
    my $dest = $config->{staging_path} . '/' . $filename;

    return 3 unless -r $src;

    sleep($delay);

    my $src_mtime = (stat($src))[9];

    # next retry is about to happen, no need to remove from spool
    return 2 unless $src_mtime > (time + $padding);

    print STDERR "rename($src, $dest)\n";
    rename($src, $dest) or return 1;
    return 0;
}

sub main {
    my %opts = (
        'c' => '/etc/eg-pbx-daemon.conf',   # config file
        'd' => 0    # daemon?
    );
    getopts('dc:f:', \%opts);

    my $usage = "usage: $0 -c config_filename -f spooled_filename";
    die $usage unless $opts{f};
    die "$opts{c}: $!\n$usage" unless -r $opts{c};

    my %config = ParseConfig($opts{c});

    daemonize if $opts{d};
    return smart_retry(\%config, $opts{f});
}

exit main;
