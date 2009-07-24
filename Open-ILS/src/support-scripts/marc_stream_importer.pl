#!/usr/bin/perl
# Copyright (C) 2008 Equinox Software, Inc.
# Author: Bill Erickson <erickson@esilibrary.com>
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

# ----------------------------------------------------------------------------
# WARNING:  This script provides no security layer.  Any client that has 
# access to the server+port can inject MARC records into the system.  
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# marc_stream_importer.pl -- Import MARC records via bare socket connection
#
# Usage:
# ./marc_stream_importer.pl /openils/conf/opensrf_core.xml \
#   <eg_username> <eg_password> <bib_source> --port <port> --min_servers 2 \
#   --max_servers 20 --log_file /openils/var/log/marc_net_importer.log &
#
# Note: this script has to be run in the same directory as $oils_header.pl
# 

# ----------------------------------------------------------------------------
# To use this script with OCLC Connexion:
#
# Under Tools -> Options -> Export (tab)
#   Create -> Choose Connection -> OK -> Leave translation at "None" 
#       -> Create -> Create -> choose TCP/IP (internet) 
#       -> Enter hostname and Port, leave 'Use Telnet Protocol' checked 
#       -> Create/OK your way out of the dialogs
#   Record Characteristics (button) -> Choose 'UTF-8 Unicode' for 
#   the Character Set
#
# OCLC and Connexion are trademark/service marks of OCLC Online Computer 
# Library Center, Inc.
# ----------------------------------------------------------------------------

use strict; use warnings;
use Net::Server::PreFork;
use base qw/Net::Server::PreFork/;
use MARC::Record;
use MARC::Batch;
use MARC::File::XML;
use MARC::File::USMARC;
use OpenSRF::Utils::Logger qw/$logger/;
require 'oils_header.pl';
use vars qw/$apputils/;

my $bufsize = 4096;
my $wait_time = 5;
my $osrf_config = shift;
my $oils_username = shift;
my $oils_password = shift;
my $bib_source = shift;
my $authtoken;

print <<WARNING;

WARNING:  This script provides no security layer.  Any client that has 
access to the server+port can inject MARC records into the system.  

WARNING

$0 = 'Evergreen MARC Stream Listener';

sub process_request {
    my $self = shift;
    my $socket = $self->{server}->{client};
    my $data = '';
    my $buf;

    # Reading <STDIN> blocks until the client is closed.  Instead of waiting 
    # for that, give each inbound record $wait_time seconds to fully arrive
    # and pull the data directly from the socket
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" }; 
        do {
            alarm $wait_time;
            last unless $socket->sysread($buf, $bufsize);
            $data .= $buf;
        } while(1);
        alarm 0;
    };

    my $handle;
    open $handle, '<', \$data; 
    my $batch = MARC::Batch->new('USMARC', $handle);
    $batch->strict_off;

    my $index = 0;
    while(1) {

        my $rec;
        $index++;

        eval { $rec = $batch->next; };

        if($@) {
            $logger->error("Failed parsing MARC record $index");
            next;
        }

        last unless $rec;

        my $resp = $apputils->simplereq(
            'open-ils.cat', 
            'open-ils.cat.biblio.record.xml.import',
            $authtoken, 
            $rec->as_xml_record, 
            $bib_source
        );

        # has the session timed out?
        if(oils_event_equals($resp, 'NO_SESSION')) {
            set_auth_token();
            my $resp = $apputils->simplereq(
                'open-ils.cat', 
                'open-ils.cat.biblio.record.xml.import',
                $authtoken, 
                $rec->as_xml_record, 
                $bib_source
            );
            oils_event_die($resp);
        } else {
            oils_event_die($resp);
        }
    }
}


# the authtoken will timeout after the configured inactivity period.
# When that happens, get a new one.
sub set_auth_token {
    $authtoken = oils_login($oils_username, $oils_password, 'staff') 
        or die "Unable to login to Evergreen";
}

osrf_connect($osrf_config);
set_auth_token();
__PACKAGE__->run();

