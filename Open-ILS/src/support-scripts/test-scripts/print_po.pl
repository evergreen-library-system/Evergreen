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

use OpenILS::Utils::Fieldmapper;
$e->xact_begin;
my $bt = $e->retrieve_acq_currency_type('USD');
$bt->label('vvvv');
my $resp = $e->update_acq_currency_type($bt);
print Dumper($resp);
$e->xact_rollback;


my $po = $e->retrieve_acq_purchase_order($po_id) or oils_event_die($e->event);
my $orgs = $apputils->get_org_ancestors($po->ordering_agency);
$orgs = $e->search_actor_org_unit([{id => $orgs}, {flesh => 1, flesh_fields => {aou => ['ou_type']}}]);
$orgs = [ sort { $a->ou_type->depth cmp $b->ou_type->depth } @$orgs ];
my $def;
for my $org (reverse @$orgs) { 
    $def = $e->search_action_trigger_event_definition({hook => $hook, owner => $org->id})->[0];
    last if $def;
}

die "No event_definition found with hook $hook\n" unless $def;
print "using def " . $def->id . " at org_unit " . $def->owner . "\n";

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

print "$event\n";

if($event->template_output) {
    print $event->template_output->data . "\n";
}
if($event->error_output) {
    print $event->error_output->data . "\n";
}

