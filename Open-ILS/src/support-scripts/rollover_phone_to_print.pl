#!/usr/bin/perl

# This script asks the Evergreen Telephony mediator (eg-pbx-mediator) via
# XML-RPC call for the A/T event IDs involved in failed notifications.
#
# With those IDs in hand, it uses cstore to find the events and make new,
# similar events with a different event_defintion.  The idea is to make it
# possible to "rollover" failed telephony notification events as, say, print
# or email notification events.
#
# Search further in this file for 'CONFIGURE HERE'.

require "/openils/bin/oils_header.pl";

use strict;
use warnings;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils::SettingsClient;

use RPC::XML;
use RPC::XML::Client;
use Data::Dumper;

# Keys and values should both be event defintion IDs.  The keys should be
# the original event defintions, the values should be the rolled-over event
# definitions.
my %rollover_map = (
    # CONFIGURE HERE. e.g.   24 => 1    # telephone overdue => email overdue
);

sub create_event_for_object {
    my ($editor, $event_def, $target) = @_;

    # there is no consideration of usr opt_in_settings, and no consideration of 
    # delay_field here

    my $event = Fieldmapper::action_trigger::event->new();
    $event->target($target);
    $event->event_def($event_def);
    $event->run_time("now");

    # state will be 'pending' by default

    $editor->create_action_trigger_event($event);
    return $event->id;
}

sub rollover_events_phone_to_print {
    my ($editor, $event_ids) = @_;
    my $finished = [];

    foreach my $id (@$event_ids) {
        my $event = $editor->retrieve_action_trigger_event($id);

        if (not $event) {
            $logger->warn("couldn't find event $id for rollover");
            next;
        } elsif (not exists $rollover_map{$event->event_def}) {
            $logger->warn(
                sprintf(
                    "event %d has event_def %d which is not in rollover map",
                    $id, $event->event_def
                )
            );
            next;
        } elsif (not $event->target) {
            $logger->warn("event $id has no target, cannot rollover");
            next;
        }

        if (my $new_id = create_event_for_object(
            $editor,
            $rollover_map{$event->event_def},
            $event->target
        )) {
            $logger->info("rollover created event $new_id from event " . $event->id);
            push @$finished, $new_id;
        }
    }

    return $finished;
}

#############################################################################
### main

if (not scalar keys %rollover_map) {
    die("You must first define some mappings in \%rollover_map (see source)\n");
}

osrf_connect($ENV{SRF_CORE} || "/openils/conf/opensrf_core.xml");

my $settings = OpenSRF::Utils::SettingsClient->new;
my $mediator_host = $settings->config_value(notifications => telephony => "host");
my $mediator_port = $settings->config_value(notifications => telephony => "port");

my $url = "http://$mediator_host:$mediator_port/";

my $rpc_client = new RPC::XML::Client($url);
my $event_ids = $rpc_client->simple_request("get_failures");

my $editor =  new OpenILS::Utils::CStoreEditor("xact" => 1);

my $done = rollover_events_phone_to_print($editor, $event_ids);

$editor->commit;
my $acked = $rpc_client->simple_request("ack_failures", $done);
$logger->info("after rollover, mediator acknowledged $acked callfiles");

0;
