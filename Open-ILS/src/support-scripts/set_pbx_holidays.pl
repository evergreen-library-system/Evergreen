#!/usr/bin/perl

require "/openils/bin/oils_header.pl";

use strict;
use warnings;
use OpenSRF::Utils qw/cleanse_ISO8601/;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsClient;

use RPC::XML;
use RPC::XML::Client;
use DateTime;
use Getopt::Std;

sub unixify {
    my ($stringy_ts) = @_;
    return (new DateTime::Format::ISO8601)->parse_datetime(
        cleanse_ISO8601($stringy_ts)
    )->epoch;
}

sub get_closed_dates {
    my ($ou) = @_;
    my $editor =  new OpenILS::Utils::CStoreEditor;

    my $rows = $editor->json_query({
        "select" => {"aoucd" => ["close_start", "close_end"]},
        "from" => "aoucd",
        "where" => {"org_unit" => $ou},
        "order_by" => [{class => "aoucd", field => "close_start", direction => "desc"}]
    });

    if (!$rows) {
        $logger->error("get_closed_dates json_query failed for ou $ou !");
        my $textcode = $editor->die_event->{textcode};
        $logger->error("get_closed_dates json_query die_event: $textcode");
        die;
    }

    $editor->disconnect;

    my $result = [];
    foreach (@$rows) {
        push @$result, [
            unixify($_->{"close_start"}), unixify($_->{"close_end"})
        ];
    }

    return $result;
}


#############################################################################
### main

my $opts = {};
getopts('c:o:u:', $opts);

my ($ou, $url);

if (!($ou = int($opts->{o}))) {
    die("no ou specified.\n$0 -o 123     # where 123 is org unit id");
}

osrf_connect($opts->{c} || $ENV{SRF_CORE} || "/openils/conf/opensrf_core.xml");

if (!($url = $opts->{u})) {
    my $settings = OpenSRF::Utils::SettingsClient->new;
    my $mediator_host = $settings->config_value(notifications => telephony => "host");
    my $mediator_port = $settings->config_value(notifications => telephony => "port");

    $url = "http://$mediator_host:$mediator_port/";
}

my $closed_dates = get_closed_dates($ou);
my $rpc_client = new RPC::XML::Client($url);
my $result = $rpc_client->simple_request("set_holidays", $closed_dates);

my $logmeth = "info";
if ($result < 0) {
    $logmeth = "error";
} elsif ($result != @$closed_dates) {
    $logmeth = "warn"
}

$logger->$logmeth(
    "after set_holidays() for " . scalar(@$closed_dates) .
    " dates, mediator returned $result"
);

0;
