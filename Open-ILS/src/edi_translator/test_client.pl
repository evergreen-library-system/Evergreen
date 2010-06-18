#!/usr/bin/perl
#

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
$host =~ /:\d+$/     or $host .= ':9191';
$host .= '/EDI';

sub get_in {
    print "Getting " . (shift) . " from input\n";
    my $json = join("", <STDIN>);
    $json or return;
    print $json, "\n";
    chomp $json;
    return $json;
}

sub nice_string {
    my $string = shift or return '';
    my $head   = @_ ? shift : 100;
    my $tail   = @_ ? shift : 25;
    (length($string) < $head + $tail) and return $string;
    return substr($string,0,$head) . " ...\n... " . substr($string, -1*$tail);
}

# MAIN
print "Trying host: $host\n";

my $client = new RPC::XML::Client($host);
$client->request->header('Content-Type' => 'text/xml;charset=utf-8');
print "User-agent: ", Dumper($client->useragent);
print "Request: ", Dumper($client->request);
print "Headers: \n";
foreach ($client->request->header_field_names) {
    print "\t$_ =>", $client->request->header($_), "\n";
}

my @commands = @ARGV ? @ARGV : 'system.listMethods';
if ($commands[0] eq 'json2edi' or $commands[0] eq 'edi2json') {
    shift;
    @commands > 1 and print "Ignoring commands after $commands[0]\n";
    my $string;
    my $type = $commands[0] eq 'json2edi' ? 'JSON' : 'EDI';
    while ($string = get_in($type)) {  # assignment
        if ($commands[0] ne 'json2edi') {
            $string =~ s/ORDRSP:0(:...:UN::)/ORDRSP:D$1/ and print "Corrected broken data 'ORDRSP:0' ==> 'ORDRSP:D'\n";
        }
        my $resp = $commands[0] eq 'json2edi' ?
                   $client->send_request('json2edi', $string) :
                   $client->send_request('edi2json', $string) ;
        print "Response: ", Dumper($resp);
        $resp or next;
        if ($resp->is_fault) {
            print "\n\nERROR code ", $resp->code, " received:\n", nice_string($resp->string) . "\n...\n";
            next;
        }
    }
    exit;
} 

print "Sending request: \n    ", join("\n    ", @commands), "\n\n";
my $resp = $client->send_request(@commands);

print Dumper($resp);
exit;

if (ref $resp) {
    print "Return is " . ref($resp), "\n";
    # print "Code: ", ($resp->{code}->as_string || 'UNKNOWN'), "\n";
    foreach (@$resp) {
        print Dumper ($_), "\n";
    }
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
