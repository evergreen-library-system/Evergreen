#!/usr/bin/perl
# Copyright (C) 2008-2014 Equinox Software, Inc.
# Copyright (C) 2014 King County Library System
# Author: Bill Erickson <berickxx@gmail.com>
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
#
# ---------------------------------------------------------------
# Sends MARC records, either from a file or from data delivered
# via the network, to open-ils.vandelay to be imported.
# ---------------------------------------------------------------
use strict; 
use warnings;
use Net::Server::PreFork;
use base qw/Net::Server::PreFork/;

require 'oils_header.pl';
use vars qw/$apputils $authtoken/;

use Getopt::Long;
use MARC::Record;
use MARC::Batch;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::File::USMARC;
use File::Basename qw/fileparse/;
use File::Temp qw/tempfile/;
use OpenSRF::AppSession;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Transport::PeerHandle;
use OpenSRF::Utils::SettingsClient;

use Data::Dumper;
$Data::Dumper::Indent=0; # for logging

# This script will always be an entry point for opensrf, 
# so go ahead and force log client.
$ENV{OSRF_LOG_CLIENT} = 1;

# these are updated with each new batch of records
my $cur_rec_type;
my $cur_rec_source;
my $cur_queue;

# cache these
my $cur_merge_profile; # this is an object
my $bib_merge_profile_obj;
my $auth_merge_profile_obj;

# options
my $help        = 0;
my $osrf_config = '/openils/conf/opensrf_core.xml';
my $username    = '';
my $password    = '';
my $workstation = '';
my $tempdir     = '';
my $spoolfile   = '';
my $wait_time   = 5;
my $verbose     = 0;
my $bib_merge_profile;
my $auth_merge_profile;
my $bib_queue;
my $auth_queue;
my $bib_source;
my $port;
my $bib_import_no_match;
my $bib_auto_overlay_exact;
my $bib_auto_overlay_1match;
my $bib_auto_overlay_best_match;
my $auth_import_no_match;
my $auth_auto_overlay_exact;
my $auth_auto_overlay_1match;
my $auth_auto_overlay_best_match;

# deprecated options;  these map to their bib_* equivalents
my $import_no_match;
my $auto_overlay_exact;
my $auto_overlay_1match;
my $auto_overlay_best_match;
my $deprecated_queue;



my $net_server_conf = fileparse($0, '.pl').'.conf';

GetOptions(
    'osrf-config=s'         => \$osrf_config,
    'verbose'               => \$verbose,
    'username=s'            => \$username,
    'password=s'            => \$password,
    'workstation=s'         => \$workstation,
    'tempdir=s'             => \$tempdir,
    'spoolfile=s'           => \$spoolfile,
    'wait=i'                => \$wait_time,
    'merge-profile=i'       => \$bib_merge_profile,
    'queue=i'               => \$deprecated_queue,
    'bib-queue=i'           => \$bib_queue,
    'source=i'              => \$bib_source,
    'auth-merge-profile=i'  => \$auth_merge_profile,
    'auth-queue=i'          => \$auth_queue,

    # -- deprecated
    'import-no-match'          => \$import_no_match,
    'auto-overlay-exact'       => \$auto_overlay_exact,
    'auto-overlay-1match'      => \$auto_overlay_1match,
    'auto-overlay-best-match'  => \$auto_overlay_best_match,
    # --

    'bib-import-no-match'          => \$bib_import_no_match,
    'bib-auto-overlay-exact'       => \$bib_auto_overlay_exact,
    'bib-auto-overlay-1match'      => \$bib_auto_overlay_1match,
    'bib-auto-overlay-best-match'  => \$bib_auto_overlay_best_match,
    'auth-import-no-match'         => \$auth_import_no_match,
    'auth-auto-overlay-exact'      => \$auth_auto_overlay_exact,
    'auth-auto-overlay-1match'     => \$auth_auto_overlay_1match,
    'auth-auto-overlay-best-match' => \$auth_auto_overlay_best_match,
    'help'                  => \$help,
    'net-server-config=s'   => \$net_server_conf,
    'port=i'                => \$port
);

sub usage {
    print <<USAGE;
    --osrf-config
        Path to OpenSRF configuration file. 

    --net-server-conf
        Path to Net::Server configuration file.  Defaults to $net_server_conf.
        Only required if --spoolfile is not set.

    --verbose               
        Log additional details

    --username
        Evergreen user account which performs the import actions.

    --password
        Evergreen user account password

    --workstation
        Evergreen workstation

    --tempdir
        MARC data received via the network is stored in a temporary
        file so Vandelay can access it.  This must be a directory
        the open-ils.vandelay service can access.  If you want the
        file deleted after completion, be sure open-ils.vandelay
        has write access to the directory and the file.
        This value defaults to the Vandelay data directory, however
        this configuratoin value is only accessible when run from 
        the private opensrf domain, which you may not want to do.

    --spoolfile
        Path to a MARC file to load.  When a --spoolfile is specified,
        this script will send the file to vandelay for processing,
        then exit when complete.  In other words, it does not stay
        alive to accept requests from the network.

    --wait
        Amount of time in seconds this script will wait after receiving
        a connection on the socket and before recieving a complete
        MARC record.  This prevents unintentional denial of service by 
        clients connecting and never sending anything.

    --merge-profile
        ID of the vandelay bib record merge profile

    --queue
        ID of the vandelay bib record queue

    --source
        ID of the bib source

    --auth-merge-profile
        ID of the vandelay authority record merge profile

    --auth-queue
        ID of the vandelay authority record queue

    --bib-import-no-match
    --bib-auto-overlay-exact
    --bib-auto-overlay-1match
    --bib-auto-overlay-best-match
    --auth-import-no-match
    --auth-auto-overlay-exact
    --auth-auto-overlay-1match
    --auth-auto-overlay-best-match

        Bib and auth import options which map directly to Vandelay import 
        options.  

        For example: 
            Apply import-no-match to bibs and auto-overlay-exact to auths.

            $0 --bib-import-no-match --auth-auto-overlay-exact

    --help                  
        Show this help message
USAGE
    exit;
}

usage() if $help;

if ($import_no_match) {
    warn "\nimport-no-match is deprecated; use bib-import-no-match\n";
    $bib_import_no_match = $import_no_match;
}
if ($auto_overlay_exact) {
    warn "\nauto-overlay-exact is deprecated; use bib-auto-overlay-exact\n";
    $bib_auto_overlay_exact = $auto_overlay_exact;
}
if ($auto_overlay_1match) {
    warn "\nauto-overlay-1match is deprecated; use bib-auto-overlay-1match\n";
    $bib_auto_overlay_1match = $auto_overlay_1match;
}
if ($auto_overlay_best_match) {
    warn "\nauto-overlay-best-match is deprecated; use bib-auto-overlay-best-match\n";
    $bib_auto_overlay_best_match = $auto_overlay_best_match;
}
if ($deprecated_queue) {
    warn "\n--queue is deprecated; use --bib-queue\n";
    $bib_queue = $deprecated_queue;
}


die "--username, --password, AND --workstation required.  --help for more info.\n" 
    unless $username and $password and $workstation;
die "--bib-queue OR --auth-queue required.  --help for more info.\n" 
    unless $bib_queue or $auth_queue;

sub set_tempdir {
    return if $tempdir; # already read or user provided
    $tempdir = OpenSRF::Utils::SettingsClient->new->config_value(
        qw/apps open-ils.vandelay app_settings databases importer/
    ) || '/tmp';
}

# Sets cur_rec_type to 'auth' if leader/06 of the first 
# parseable record is 'z', otherwise 'bib'.
sub set_record_type {
    my $file_name = shift;

    my $marctype = 'USMARC';
    open(F, $file_name) or
        die "Unable to open MARC file $file_name : $!\n";
    $marctype = 'XML' if (getc(F) =~ /^\D/o);
    close F;

    my $batch = new MARC::Batch ($marctype, $file_name);
    $batch->strict_off;

    my $rec;
    my $ldr_06 = '';
    while (1) {
        eval {$rec = $batch->next};
        next if $@; # record parse failure
        last unless $rec;
        $ldr_06 = substr($rec->leader(), 6, 1) || '';
        last;
    }

    $cur_rec_type = $ldr_06 eq 'z' ? 'auth' : 'bib';

    $cur_queue = $cur_rec_type eq 'auth' ? $auth_queue : $bib_queue;
    $cur_rec_source = $cur_rec_type eq 'auth' ?  '' : $bib_source;
    set_merge_profile();
}

# set vandelay options based on command line ops and the type of record
# currently in process.
sub compile_vandelay_ops {

    my $vl_ops = {
        report_all => 1,
        merge_profile => $cur_merge_profile ? $cur_merge_profile->id : undef
    };

    if ($cur_rec_type eq 'auth') {
        $vl_ops->{import_no_match} = $auth_import_no_match;
        $vl_ops->{auto_overlay_exact} = $auth_auto_overlay_exact;
        $vl_ops->{auto_overlay_1match} = $auth_auto_overlay_1match;
        $vl_ops->{auto_overlay_best_match} = $auth_auto_overlay_best_match;
    } else {
        $vl_ops->{import_no_match} = $bib_import_no_match;
        $vl_ops->{auto_overlay_exact} = $bib_auto_overlay_exact;
        $vl_ops->{auto_overlay_1match} = $bib_auto_overlay_1match;
        $vl_ops->{auto_overlay_best_match} = $bib_auto_overlay_best_match;
    }

    # Default to exact match only if not other strategy is selected.
    $vl_ops->{auto_overlay_exact} = 1
        if not (
            $vl_ops->{auto_overlay_1match} or 
            $vl_ops->{auto_overlay_best_match}
        );

    $logger->info("VL options: ".Dumper($vl_ops)) if $verbose;
    return $vl_ops;
}

sub process_spool { 
    my $file_name = shift; # filename

    set_record_type($file_name);

    my $ses = OpenSRF::AppSession->create('open-ils.vandelay');
    my $req = $ses->request(
        "open-ils.vandelay.$cur_rec_type.process_spool.stream_results",
        $authtoken, undef, # cache key not needed
        $cur_queue, 'import', $file_name, $cur_rec_source 
    );

    my @rec_ids;
    while(my $resp = $req->recv) {

        if($req->failed) {
            $logger->error("Error spooling MARC data: $resp");

        } elsif($resp->content) {
            push(@rec_ids, $resp->content);
        }
    }

    return \@rec_ids;
}

sub import_queued_records {
    my $rec_ids = shift;
    my $vl_ops = compile_vandelay_ops();

    my $ses = OpenSRF::AppSession->create('open-ils.vandelay');
    my $req = $ses->request(
        "open-ils.vandelay.${cur_rec_type}_record.list.import",
        $authtoken, $rec_ids, $vl_ops 
    );

    # collect the successfully imported vandelay records
    my $failed = 0;
    my @cleanup_recs;
    while(my $resp = $req->recv) {
         if($req->failed) {
            $logger->error("Error importing MARC data: $resp");

        } elsif(my $data = $resp->content) {

            if($data->{err_event}) {

                $logger->error(Dumper($data->{err_event}));
                $failed++;

            } elsif ($data->{no_import}) {
                # no errors, just didn't import, because of rules.

                $failed++;
                $logger->info(
                    "record failed to satisfy Vandelay merge/quality/etc. ".
                    "requirements: " . ($data->{imported} || ''));

            } else {
                push(@cleanup_recs, $data->{imported}) if $data->{imported};
            }
        }
    }

    # clean up the successfully imported vandelay records to prevent queue bloat
    my $pcrud = OpenSRF::AppSession->create('open-ils.pcrud');
    $pcrud->connect;
    $pcrud->request('open-ils.pcrud.transaction.begin', $authtoken)->recv;
    my $err;

    my $api = 'open-ils.pcrud.delete.';
    $api .= $cur_rec_type eq 'auth' ? 'vqar' : 'vqbr';

    foreach (@cleanup_recs) {
        eval {
            $pcrud->request($api, $authtoken, $_)->recv;
        };

        if ($@) {
            $logger->error("Error deleting queued $cur_rec_type record $_: $@");
            last;
        }
    }

    $pcrud->request('open-ils.pcrud.transaction.commit', $authtoken)->recv unless $err;
    $pcrud->disconnect;

    $logger->info("imported queued vandelay records: @cleanup_recs");
    return (scalar(@cleanup_recs), $failed);
}



# Each child needs its own opensrf connection.
sub child_init_hook {
    OpenSRF::System->bootstrap_client(config_file => $osrf_config);
    Fieldmapper->import(IDL => 
        OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
}


# The core Net::Server method
# Reads streams of MARC data from the network, saves the data as a file,
# then processes the file via vandelay.
sub process_request { 
    my $self = shift;
    my $client = $self->{server}->{peeraddr}.':'.$self->{server}->{peerport};

    $logger->info("$client opened a new connection");

    my $ph = OpenSRF::Transport::PeerHandle->retrieve;
    if(!$ph->flush_socket()) {
        $logger->error("We received a request, but we are no longer connected".
            " to opensrf.  Exiting and dropping request from $client");
        exit;
    }

    my $data = '';
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $wait_time; # prevent accidental tie ups of backend processes
        local $/ = "\x1D"; # MARC record separator
        $data = <STDIN>;
        alarm 0;
    };

    if($@) {
        $logger->error("reading from STDIN failed or timed out: $@");
        return;
    } 

    $logger->info("stream parser read " . length($data) . " bytes");

    set_tempdir();

    # copy data to a temporary file so vandelay can scoop it up
    my ($handle, $tempfile) = tempfile("$0_XXXX", DIR => $tempdir) 
        or die "Cannot create tempfile in $tempdir : $!";

    print $handle $data or die "Error writing to tempfile $tempfile : $!\n";
    close $handle;

    process_file($tempfile);
}

sub set_merge_profile {

    # serve from cache

    return $cur_merge_profile = $bib_merge_profile_obj
        if $bib_merge_profile_obj and $cur_rec_type eq 'bib';

    return $cur_merge_profile = $auth_merge_profile_obj
        if $auth_merge_profile_obj and $cur_rec_type eq 'auth';

    # fetch un-cached profile
    
    my $profile_id = $cur_rec_type eq 'bib' ?
        $bib_merge_profile : $auth_merge_profile;

    return $cur_merge_profile = undef unless $profile_id;

    $cur_merge_profile = $apputils->simplereq(
        'open-ils.pcrud', 
        'open-ils.pcrud.retrieve.vmp', 
        $authtoken, $profile_id);

    # cache profile for later
   
    $auth_merge_profile_obj = $cur_merge_profile if $cur_rec_type eq 'auth';
    $bib_merge_profile_obj = $cur_merge_profile if $cur_rec_type eq 'bib';
}

sub process_file {
    my $file = shift;

    new_auth_token(); # login
    my $rec_ids = process_spool($file);
    my ($imported, $failed) = import_queued_records($rec_ids);

    if (oils_event_equals($imported, 'NO_SESSION')) {  
        # did the session expire while spooling?
        new_auth_token(); # retry with new authtoken
        ($imported, $failed) = import_queued_records($rec_ids);
    }

    oils_event_die($imported);

    my $profile = $cur_merge_profile ? $cur_merge_profile->name : '';
    my $msg = '';
    $msg .= "Successfully imported $imported $cur_rec_type records ".
        "using merge profile '$profile'\n" if $imported;
    $msg .= "Failed to import $failed $cur_rec_type records\n" if $failed;
    $msg .= "\x00" unless $spoolfile;
    print $msg;

    clear_auth_token(); # logout
}

# the authtoken will timeout after the configured inactivity period.
# When that happens, get a new one.
sub new_auth_token {
    oils_login($username, $password, 'staff', $workstation)
        or die "Unable to login to Evergreen as user $username";
}

sub clear_auth_token {
    $apputils->simplereq(
        'open-ils.auth',
        'open-ils.auth.session.delete',
        $authtoken
    );
    $authtoken = undef;
}

# -- execution starts here

if ($spoolfile) {
    # individual files are processed in standalone mode.
    # No Net::Server innards are necessary.

    child_init_hook(); # force an opensrf connection
    process_file($spoolfile);
    exit;
}

# No spoolfile, run in Net::Server mode

warn <<WARNING;

WARNING:  This script provides no security layer.  Any client that has 
access to the server+port can inject MARC records into the system.  

WARNING

my %args;
$args{conf_file} = $net_server_conf if -r $net_server_conf;
$args{port} = $port if $port;

__PACKAGE__->run(%args);


