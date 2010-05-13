#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright (C) 2010 Equinox Software, Inc
# Author: Joe Atzberger <jatzberger@esilibrary.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

use strict;
use warnings;

use Data::Dumper;
use vars qw/$debug/;

use OpenILS::Utils::CStoreEditor;   # needs init() after IDL is loaded (by Cronscript session)
use OpenILS::Utils::Cronscript;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Acq::EDI;
use OpenSRF::Utils::Logger q/$logger/;

INIT {
    $debug = 1;
}

my %opts = (
    'quiet' => 0,
    'max-batch-size=i' => -1
);

my $cs = OpenILS::Utils::Cronscript->new(\%opts);
$cs->session('open-ils.acq') or die "No session created";

OpenILS::Utils::CStoreEditor::init();

sub editor {
    my $ed = OpenILS::Utils::CStoreEditor->new(@_) or die "Failed to get new CStoreEditor";
    return $ed;
}

my $e = editor();
my $hook = 'acqpo.activated';
my $defs = $e->search_action_trigger_event_definition({
    hook => $hook, 
    reactor => 'GeneratePurchaseOrderJEDI',
    active => 't'
});

# print Dumper($defs);
print "\nHook '$hook' is used in ", scalar(@$defs), " event definition(s):\n";

$Data::Dumper::Indent = 1;
my $remaining = $cs->first_defined('max-batch-size');
foreach my $def (@$defs) {
    last if $remaining == 0;
    printf "%3s - '%s'\n", $def->id, $def->name;

    # give me all completed JEDI events that link to purchase_orders 
    # that have not already been delivered to the vendor
    my $query = {
        select => {atev => ['id']},
        from => 'atev',
        where => {
            event_def => $def->id,
            state => 'complete',
            target => {
                in => {
                    select => {acqpo => ['id']},
                    from => 'acqpo',
                    where => {
                        id => {
                            'not in' => {
                                select => {acqedim => ['purchase_order']},
                                from => 'acqedim',
                                where => {purchase_order => {'!=' => undef}}
                            }
                        }
                    }
                }
            }
        },
        order_by => {atev => ['add_time']}
    };

    $query->{limit} = $remaining if $remaining > 0;

    my $events = $e->json_query($query);
    $remaining -= scalar(@$events);

    print "Event definition ", $def->id, " has ", scalar(@$events), " event(s)\n";
    foreach (@$events) {

        my $event = $e->retrieve_action_trigger_event([
            $_->{id}, 
            {flesh => 1, flesh_fields => {atev => ['template_output']}}
        ]);

        my $message = Fieldmapper::acq::edi_message->new;
        $message->create_time('NOW');   # will need this later when we try to update from the object
        print "Event ", $event->id, " targets PO ", $event->target, ":\n";  # target is an opaque identifier, so we cannot flesh it
        print Dumper($event), "\n";
        my $target = $e->retrieve_acq_purchase_order([              # instead we retrieve it separately
            $event->target, {
                flesh => 2,
                flesh_fields => {
                    acqpo  => ['provider'],
                    acqpro => ['edi_default'],
                },
            }
        ]);

        $message->purchase_order($target->id);

        $debug and print "Target: ", Dumper($target), "\n";
        my $logstr = sprintf "provider %s (%s)", $target->provider->id, $target->provider->name;
        unless ($target->provider->edi_default and $message->account($target->provider->edi_default->id)) {
            printf STDERR "ERROR: No edi_default account found for $logstr.  File will not be sent!\n";
        }
        $message->jedi($event->template_output()->data);
        print "\ntarget->provider->edi_default->id: ", $target->provider->edi_default->id, "\n";
        print "\nNow calling attempt_translation\n\n";
        unless (OpenILS::Application::Acq::EDI->attempt_translation($message, 1)) {
            print STDERR "ERROR: attempt_translation failed, skipping message\n";
            next;
            # The premise here is that if the translator failed, it is better to try again later from a "fresh" fetched file
            # than to add a cascade of failing inscrutable copies of the same message(s) to our DB.  
        }
        print "Writing new message + translation to DB\n";
        $e->xact_begin;
        $e->create_acq_edi_message($message) or warn "create_acq_edi_message failed!  $!";
        $e->xact_commit;

        print "Calling send_core(...)\n";
        my $res = OpenILS::Application::Acq::EDI->send_core($target->provider->edi_default, [$message->id]);
        if (@$res) {
            my $message_out = shift @$res;
            print "\tmessage ", $message->id, " status: ", $message_out->status, "\n";
        } else {
            print STDERR "ERROR: send_core failed for message ", $message->id, "\n";
        }
    }
}

print "\ndone\n";
