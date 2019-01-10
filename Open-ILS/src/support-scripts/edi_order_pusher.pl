#!/usr/bin/perl
# ---------------------------------------------------------------
# Copyright (C) 2016 King County Library System
# Author: Bill Erickson <berickxx@gmail.com>
#
# Copied heavily from edi_pusher.pl
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------
use strict;
use warnings;
use Getopt::Long;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Acq::EDI;
use OpenILS::Utils::EDIWriter;

my $osrf_config = '/openils/conf/opensrf_core.xml';
my $po_id;
my $test_mode;
my $verbose;
my $help;

my $ops = GetOptions(
    'osrf-config=s' => \$osrf_config,
    'test-mode'     => \$test_mode,
    'po-id=i'       => \$po_id,
    'verbose'       => \$verbose,
    'help'          => \$help
);

sub help {
    print <<HELP;

    Synopsis:

        Generate and deliver 'ORDERS' EDI for purchase orders.  Unless a
        specific PO is provided (via --po-id), EDI messages will be 
        generated for all PO's that meet the following conditions:
        
        1. PO must be activated.
        2. PO provider must be active.
        3. PO must use a provider that supports EDI delivery (via edi_default)
        4. EDI account linked to provider must have 'use_attrs' set to true.
        5. PO must have no EDI ORDERS messages attached or, if it does, 
           the message has a status of "retry".

    Usage:

        $0

        --osrf-config [/openils/conf/opensrf_core.xml]

        --test-mode
            Prints EDI that would be sent to STDOUT.  No files are sent
            and no edi_message's are created.

        --po-id <po-id-value>
            Process a specific PO instead of processing all available PO's

        --verbose
            Log debug info to STDOUT.  This script logs various information
            via \$logger regardless of this option.

        --help
            Show this message.
HELP
    exit 0;
}

help() if $help or !$ops;

# $lvl should match a $logger logging function.  E.g. 'info', 'error', etc.
sub announce {
    my $lvl = shift;
	my $msg = shift;
    $logger->$lvl($msg);

    # always announce errors and warnings
    return unless $verbose || $lvl =~ /error|warn/;

    my $date_str = DateTime->now(time_zone => 'local')->strftime('%F %T');
    print "$date_str $msg\n";
}

# connect to osrf...
OpenSRF::System->bootstrap_client(config_file => $osrf_config);
Fieldmapper->import(IDL => 
    OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
OpenILS::Utils::CStoreEditor::init();
my $e = OpenILS::Utils::CStoreEditor->new;

announce('debug', "FTP_PASSIVE is ".($ENV{FTP_PASSIVE} ? "ON" : "OFF"));

my $po_ids;

if ($po_id) {
    # Caller provided a specific PO to process.
    $po_ids = [$po_id];

} else {
    # Find PO's that have an order date set (i.e. are activated) and are 
    # linked to active providers that support EDI orders, but has no 
    # successful "ORDERS" edi_message attached.
    
    my $ids = $e->json_query({
        select => {acqpo => ['id']},
        from => {
            acqpo => {
                acqedim => {
                    type => 'left',
                    filter => {message_type => 'ORDERS'}
                },
                acqpro => {
                    join => {
                        acqedi => {
                        }
                    }
                }
            }
        },
        where => {
            '+acqpo' => {
                state => 'on-order', # on-order only
                order_date => {'!=' => undef} # activated
            },
            '+acqpro' => {
                active => 't', 
                edi_default => {'!=' => undef}
            },
            '+acqedi' => {
                use_attrs => 't'
            },
            '+acqedim' => {
                '-or' => [
                    {id => undef}, # no ORDERS message exists
                    {status => 'retry'} # ORDERS needs re-sending
                ]
            }
        }
    });

    $po_ids = [map {$_->{id}} @$ids];
}

if (!@$po_ids) {
    announce('info', "No purchase orders to process");
    exit 0;
}

for $po_id (@$po_ids) {

    my $edi = OpenILS::Utils::EDIWriter->new->write($po_id);

    if (!$edi) {
        announce('error', "Unable to generate EDI for PO $po_id");
        next;
    }

    if ($test_mode) {
        # Caller just wants the EDI printed to STDOUT
        print "EDI for PO $po_id:\n$edi\n";
        next;
    }

    # this may be a retry attempt.  if so, reuse the original edi_message
    my $message = $e->search_acq_edi_message({
        purchase_order => $po_id,
        message_type => 'ORDERS', 
        status => 'retry'
    })->[0];

    if (!$message) {
        $message = Fieldmapper::acq::edi_message->new;
        $message->create_time('NOW');
        $message->purchase_order($po_id);
        $message->message_type('ORDERS');
        $message->isnew(1);

        my $po = $e->retrieve_acq_purchase_order([$po_id, {
            flesh => 2,
            flesh_fields => {
                acqpo  => ['provider'],
                acqpro => ['edi_default'],
            }
        }]);

        if (!$po->provider->edi_default) {
            announce('error', "Provider for PO $po_id has no default EDI ".
                "account, EDI message will not be sent.");
            next;
        }

        $message->account($po->provider->edi_default->id);
    }

    $message->edi($edi);

    $e->xact_begin;
    if ($message->isnew) {
        unless($e->create_acq_edi_message($message)) {
            announce('error', 
                "Error creating acq.edi_message for PO $po_id: ".$e->die_event);
            next;
        }
    } else {
        unless($e->update_acq_edi_message($message)) {
            announce('error', 
                "Error updating acq.edi_message for PO $po_id: ".$e->die_event);
            next;
        }
    }
    $e->xact_commit;

    my $po = $e->retrieve_acq_purchase_order([
        $po_id, {
            flesh => 2,
            flesh_fields => {
                acqpo  => ['provider'],
                acqpro => ['edi_default'],
            }
        }
    ]);

    if (!$po->provider->edi_default) {
        # Caller has provided a PO ID for a provider that does not
        # support EDI.  
        announce('error', "Cannot send EDI for PO $po_id, because the ".
            "provider (".$po->provider->id.") is not configured to use EDI");
        next;
    }

    my $res = OpenILS::Application::Acq::EDI->send_core(
        $po->provider->edi_default, [$message->id]);

    if (my $out = $res->[0]) {
        announce('info', "message ".$message->id." status: ".$out->status);
    } else {
        announce('error', "send_core failed for message ".$message->id);
    }
}


