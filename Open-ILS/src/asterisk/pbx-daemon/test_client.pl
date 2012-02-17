#!/usr/bin/perl


# 17 Feb 2012:
# A lot has changed with the other files in this directory, and regrettably
# I don't know to what extent this script works anymore.
#   - senator

use warnings;
use strict;

use Getopt::Long;
use RPC::XML::Client;
use Data::Dumper;

# DEFAULTS
my $host = 'http://localhost';
my $verbose = 0;

GetOptions(
    'host=s'  => \$host,
    'verbose' => \$verbose,
);

# CLEANUP
$host =~ /^\S+:\/\// or $host  = 'http://' . $host;
$host =~ /:\d+$/     or $host .= ':10080';

# MAIN
print "Trying host: $host\n";

my $client = new RPC::XML::Client($host);

my $insertblock = <<END_OF_CHUNK ;
Channel: zap1/614260xxxx
Context: overdue-test
MaxRetries: 1
RetryTime: 60
WaitTime: 30
Extension: 10
Archive: 1
Set: items=2
Set: titlestring=Akira, Huckleberry Finn
END_OF_CHUNK

my @commands;
if (scalar(@ARGV)) {
    foreach(@ARGV) {
        push @commands, $_;
        $_ eq 'inject' and push @commands, $insertblock;
    }
} else {
    push @commands, 'retrieve';    # default
}

print "Sending request: \n    ", join("\n    ", @commands), "\n\n";
my $resp = $client->send_request(@commands);

if (ref $resp) {
    print "Return is " . ref($resp), "\n";
    # print "Code: ", ($resp->{code}->as_string || 'UNKNOWN'), "\n";
    foreach (qw(code faultcode)) {
        my $code = $resp->{$_};
        if ($code) {
            print "    ", ucfirst($_), ": ";
            print $code ? $code->value : 'UNKNOWN';
        }
        print "\n";
    }
} else {
    print "ERROR: unrecognized response:\n\n", Dumper($resp), "\n";
}
$verbose and print Dumper($resp);
$verbose and print "\nKEYS (level 1):\n",
    map {sprintf "%12s: %s\n", $_, scalar $resp->{$_}->value} sort keys %$resp;

# print "spooled_filename: ", $resp->{spooled_filename}->value, "\n";
