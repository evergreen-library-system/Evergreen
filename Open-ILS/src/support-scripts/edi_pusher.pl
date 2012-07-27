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

use OpenILS::Utils::Cronscript;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Acq::EDI;
use OpenSRF::Utils::Logger q/$logger/;

INIT {
    $debug = 1;
}

my %defaults = (
    'quiet' => 0,
    'test'  => 0,   # TODO
    'max-batch-size=i' => -1,

    # if true, print final EDI to STDOUT, send nothign to the vendor, write nothing to the DB
    'debug-only' => 0
);

my $cs = OpenILS::Utils::Cronscript->new(\%defaults);

my $opts = $cs->MyGetOptions();
my $e    = $cs->editor() or die "Failed to get new CStoreEditor";
my $hook = 'acqpo.activated';
my $defs = $e->search_action_trigger_event_definition({
    hook    => $hook,
    reactor => 'GeneratePurchaseOrderJEDI',
    active  => 't'
});

$opts->{verbose} = 0 if $opts->{quiet};

print "FTP_PASSIVE is ", ($ENV{FTP_PASSIVE} ? "ON" : "OFF"),  "\n";

print "\nHook '$hook' is used in ", scalar(@$defs), " event definition(s):\n";

$Data::Dumper::Indent = 1;
my $remaining = $opts->{'max-batch-size'};

# FIXME: this is the disclusion subquery.  It discludes any PO that has
# a non-retry edi_message linked to it.  But that means that if there are
# mutliple EDI messages (say, some failed translation) and one marked retry,
# the PO is still discluded!  Perhaps there should never be multiple messages,
# but that makes testing much trickier (and is not DB-enforced).
#
# One approach might be to supplementally query for any "retry" messages that 
# are on active providers (and deduplicate).  

my $subq = {
    select => { acqedim => ['purchase_order'] },
    from   => 'acqedim',
    where  => {
        message_type   => 'ORDERS',
        status         => {'!=' => 'retry' },
        purchase_order => {'!=' => undef   }
    }
};

foreach my $def (@$defs) {
    last if $remaining == 0;
    printf "%3s - '%s'\n", $def->id, $def->name;

    # give me all completed JEDI events that link to purchase_orders 
    # that have no delivery attempts or are in the retry state

    my $query = {
        select => {atev => ['id']},
        from   => 'atev',
        where  => {
            event_def => $def->id,
            state  => 'complete',
            target => {
                'not in' => $subq
            }
        },
        order_by => {atev => ['add_time']}
    };

    $query->{limit} = $remaining if $remaining > 0;

    if ($opts->{verbose}) {
        # $subq->{'select'}->{'acqedim'} = ['id', 'purchase_order', 'message_type', 'status'];
        my $excluded = $e->json_query($subq);
        print "Excluded: ", scalar(@$excluded), " purchase order(s):\n";
        my $z = 0;
        print map {sprintf "%7d%s", $_, (++$z % 5) ? '' : "\n"} sort {$a <=> $b} map {$_->{purchase_order}} @$excluded;
        print "\n";
    }

    my $events = $e->json_query($query);

    if(!$events) {
        print STDERR   "error querying JEDI events for event definition ", $def->id, "\n";
        $logger->error("error querying JEDI events for event definition ". $def->id);
        next;
    }

    $remaining -= scalar(@$events);

    print "Event definition ", $def->id, " has ", scalar(@$events), " (completed) event(s)\n";
    foreach (@$events) {

        my $event = $e->retrieve_action_trigger_event([
            $_->{id}, 
            {flesh => 1, flesh_fields => {atev => ['template_output']}}
        ]);


        my $target = $e->retrieve_acq_purchase_order([              # instead we retrieve it separately
            $event->target, {
                flesh => 2,
                flesh_fields => {
                    acqpo  => ['provider'],
                    acqpro => ['edi_default'],
                },
            }
        ]);

        # this may be a retry attempt.  if so, reuse the original edi_message
        my $message = $e->search_acq_edi_message({
            purchase_order => $target->id,
            message_type => 'ORDERS', 
            status => 'retry'
        })->[0];

        if(!$message) {
            $message = Fieldmapper::acq::edi_message->new;
            $message->create_time('NOW');   # will need this later when we try to update from the object
            $message->purchase_order($target->id);
            $message->message_type('ORDERS');
            $message->isnew(1);
        }

        my $logstr = sprintf "provider %s (%s)", $target->provider->id, $target->provider->name;
        unless ($target->provider->edi_default and $message->account($target->provider->edi_default->id)) {
            printf STDERR "ERROR: No edi_default account found for $logstr.  File will not be sent!\n";
        }

        $message->jedi($event->template_output()->data);

        print "\ntarget->provider->edi_default->id: ", $target->provider->edi_default->id, "\n";
        my $logstr2 = sprintf "event %s, PO %s, template_output %s", $_->{id}, $message->purchase_order, $event->template_output->id;
        if ($opts->{test}) {
            print "Test mode, skipping translation/send\n";
            next;
        }

        printf "\nNow calling attempt_translation for $logstr2\n\n";

        unless (OpenILS::Application::Acq::EDI->attempt_translation($message, 1)) {
            print STDERR "ERROR: attempt_translation failed for $logstr2\n";
            next;
            # The premise here is that if the translator failed, it is better to try again later from a "fresh" fetched file
            # than to add a cascade of failing inscrutable copies of the same message(s) to our DB.  
        }

        if ($opts->{'debug-only'}) {
            print OpenILS::Application::Acq::EDI->attempt_translation($message, 1)->edi . "\n";
            print "\ndebug-only => skipping FTP\n";
            next;
        }

        print "Writing new message + translation to DB for $logstr2\n";

        $e->xact_begin;
        if($message->isnew) {
            unless($e->create_acq_edi_message($message)) {
                $logger->error("Error creating acq.edi_message for $logstr2: ".$e->die_event);
                next;
            }
        } else {
            unless($e->update_acq_edi_message($message)) {
                $logger->error("Error updating acq.edi_message for $logstr2: ".$e->die_event);
                next;
            }
        }
        $e->xact_commit;

        print "Calling send_core(...) for message (", $message->id, ")\n";
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

__END__

=head1 NAME

edi_pusher.pl - A script for generating and sending EDI files to remote accounts.

=head1 DESCRIPTION

This script is expected to be run via crontab, for the purpose of retrieving vendor EDI files.

=head1 OPTIONS

  --max-batch-size=i  Limit the processing to a set number of events.

=head1 TODO

More docs here.

=head1 USAGE

B<FTP_PASSIVE=1> is recommended.  Depending on your vendors' and your own network environments, you may want to set/export
the environmental variable FTP_PASSIVE like:

    export FTP_PASSIVE=1
    # or
    FTP_PASSIVE=1 Open-ILS/src/support-scripts/edi_pusher.pl

=head1 SEE ALSO

    OpenILS::Utils::Cronscript
    edi_fetcher.pl

=head1 AUTHOR

Joe Atzberger <jatzberger@esilibrary.com>

=cut
