#!/usr/bin/perl

#----------------------------------------------------------------
# Print PO
#----------------------------------------------------------------

require '../oils_header.pl';
use vars qw/$apputils/;
use strict;
use Data::Dumper;
my $config		= shift; 
my $username	= shift || 'admin';
my $password	= shift || 'open-ils';
my $po_id       = shift;
my $hook        = shift || 'format.po.jedi';

osrf_connect($config);
oils_login($username, $password);
my $e = OpenILS::Utils::CStoreEditor->new;

my $po = $e->retrieve_acq_purchase_order($po_id) or oils_event_die($e->event);
my $orgs = $apputils->get_org_ancestors($po->ordering_agency);
my $defs = $e->search_action_trigger_event_definition({hook => $hook, owner => $orgs});
$defs = [sort { $a->id cmp $b->id } @$defs ]; # this is a brittle hack, but.. meh
my $def = pop @$defs;
print "using def " . $def->id . " at org_unit " . $def->owner . "\n";

die "No event_definition found with hook $hook\n" unless $def;

my $event_id = $apputils->simplereq(
    'open-ils.trigger', 
    'open-ils.trigger.event.autocreate.by_definition',
    $def->id, $po, $po->ordering_agency);


my $result = $apputils->simplereq(
    'open-ils.trigger',
    'open-ils.trigger.event.fire', $event_id);


print "Event state is " . $result->{event}->state . "\n";

my $event = $e->retrieve_action_trigger_event(
    [
        $event_id, 
        {flesh => 1, flesh_fields => {atev => ['template_output', 'error_output']}}
    ]
);

if($event->template_output) {
    print $event->template_output->data . "\n";
}
if($event->error_output) {
    print $event->error_output->data . "\n";
}

