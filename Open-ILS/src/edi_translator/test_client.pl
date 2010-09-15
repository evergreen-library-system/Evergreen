#!/usr/bin/perl
#

use warnings;
use strict;

use Getopt::Long;
use RPC::XML::Client;
use JSON::XS;
use Data::Dumper;

# DEFAULTS
$Data::Dumper::Indent = 1;
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
    print STDERR "Getting " . (shift) . " from input\n";
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

sub JSONObject2Perl {
    my $obj = shift;
    if ( ref $obj eq 'HASH' ) { # is a hash w/o class marker; simply revivify innards
        for my $k (keys %$obj) {
            $obj->{$k} = JSONObject2Perl($obj->{$k}) unless ref $obj->{$k} eq 'JSON::XS::Boolean';
        }
    } elsif ( ref $obj eq 'ARRAY' ) {
        for my $i (0..scalar(@$obj) - 1) {
            $obj->[$i] = JSONObject2Perl($obj->[$i]) unless ref $obj->[$i] eq 'JSON::XS::Boolean';
        }
    }
    # ELSE: return vivified non-class hashes, all arrays, and anything that isn't a hash or array ref
    return $obj;
}

# MAIN
print "Trying host: $host\n";

my $parser;

my $client = new RPC::XML::Client($host);
$client->request->header('Content-Type' => 'text/xml;charset=utf-8');

if ($verbose) {
    print "User-agent: ", Dumper($client->useragent);
    print "Request: ", Dumper($client->request);
    print "Headers: \n";
    foreach ($client->request->header_field_names) {
        print "\t$_ =>", $client->request->header($_), "\n";
    }
}

my @commands = @ARGV ? @ARGV : 'system.listMethods';
my $command  = lc $commands[0];
if ($command eq 'json2edi' or $command eq 'edi2json' or $command eq 'edi2perl') {
    shift;
    @commands > 1 and print STDERR "Ignoring commands after $command\n";
    my $string;
    my $type = $command eq 'json2edi' ? 'JSON' : 'EDI';
    while ($string = get_in($type)) {  # assignment
        my $resp;
        if ($command eq 'json2edi') {
            $resp = $client->send_request('json2edi', $string);
            print "# $command Response: \n", Dumper($resp);
        } else {
            $string =~ s/ORDRSP:0(:...:UN::)/ORDRSP:D$1/ and print STDERR "Corrected broken data 'ORDRSP:0' ==> 'ORDRSP:D'\n";
            $resp = $client->send_request('edi2json', $string);
        }
        unless ($resp) {
            warn "Response does not have a payload value!";
            next;
        }
        if ($resp->is_fault) {
            print "\n\nERROR code ", $resp->code, " received:\n", nice_string($resp->string) . "\n...\n";
            next;
        }
        if ($command ne 'json2edi') {   # like the else of the first conditional
            $parser ||= JSON::XS->new()->pretty(1)->ascii(1)->allow_nonref(1)->space_before(0);    # get it once
            $verbose and print Dumper($resp);
            my $parsed = $parser->decode($resp->value) or warn "Failed to decode response payload value";
            my $perl   = JSONObject2Perl($parsed)      or warn "Failed to decode and create perl object from JSON";
            if ($perl) {
                print STDERR "\n########## We were able to decode and perl-ify the JSON\n";
            } else {
                print STDERR "\n########## ERROR: Failed to decode and perl-ify the JSON\n";
            }
            print "# $command Response: \n", $command eq 'edi2perl' ? Dumper($perl) : $parser->encode($parsed);
        }
    }
    exit;
} 

print STDERR "Sending request: \n    ", join("\n    ", @commands), "\n\n";
my $resp = $client->send_request(@commands);

print Dumper($resp);
exit;

if (ref $resp) {
    print STDERR "Return is " . ref($resp), "\n";
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
    print STDERR "ERROR: unrecognized response:\n\n", Dumper($resp), "\n";
}
$verbose and print Dumper($resp);
$verbose and print "\nKEYS (level 1):\n",
    map {sprintf "%12s: %s\n", $_, scalar $resp->{$_}->value} sort keys %$resp;

# print "spooled_filename: ", $resp->{spooled_filename}->value, "\n";

