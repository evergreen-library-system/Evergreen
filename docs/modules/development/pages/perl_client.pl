#/usr/bin/perl
use strict;
use OpenSRF::AppSession;
use OpenSRF::System;
use Data::Dumper;

OpenSRF::System->bootstrap_client(config_file => '/openils/conf/opensrf_core.xml');

my $session = OpenSRF::AppSession->create("opensrf.simple-text");

print "substring: Accepts a string and a number as input, returns a string\n";
my $request = $session->request("opensrf.simple-text.substring", "foobar", 3);

my $response;
while ($response = $request->recv()) {
    print "Substring: " . $response->content . "\n\n";
}

print "split: Accepts two strings as input, returns an array of strings\n";
$request = $session->request("opensrf.simple-text.split", "This is a test", " ")->gather();
my $output = "Split: [";
foreach my $element (@$request) {
    $output .= "$element, ";
}
$output =~ s/, $/]/;
print $output . "\n\n";

print "statistics: Accepts an array of strings as input, returns a hash\n";
my @many_strings = [
    "First I think I'll have breakfast",
    "Then I think that lunch would be nice",
    "And then seventy desserts to finish off the day"
];

$request = $session->request("opensrf.simple-text.statistics", @many_strings)->gather();
print "Length: " . $request->{'length'} . "\n";
print "Word count: " . $request->{'word_count'} . "\n";

$session->disconnect();

