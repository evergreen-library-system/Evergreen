#!/usr/bin/perl
# Copyright (C) 2008-2010 Equinox Software, Inc.
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


use strict; use warnings;
use Net::Server::PreFork;
use base qw/Net::Server::PreFork/;
use MARC::Record;
use MARC::Batch;
use MARC::File::XML ( BinaryEncoding => 'UTF-8' );
use MARC::File::USMARC;

use Data::Dumper;
use File::Basename qw/fileparse/;
use File::Temp;
use Getopt::Long qw(:DEFAULT GetOptionsFromArray);
use Pod::Usage;
use Socket;

use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenILS::Utils::Cronscript;
use OpenSRF::Transport::PeerHandle;
require 'oils_header.pl';
use vars qw/$apputils/;

my $vl_ses;

my $debug = 0;

my %defaults = (
    'buffsize=i'    => 4096,
    'merge-profile=i' => 0,
    'source=i'      => 1,
#    'osrf-config=s' => '/openils/conf/opensrf_core.xml',
    'user=s'        => 'admin',
    'password=s'    => '',
    'tempdir=s'     => '',
    'spoolfile=s'   => '',
    'nolockfile'    => 1,
    'queue=i'       => 1,
    'noqueue'       => 0,
    'nodaemon'      => 0,
    'wait=i'        => 5,
    'import-by-queue' => 0
);

$OpenILS::Utils::Cronscript::debug=1 if $debug;
$Getopt::Long::debug=1 if $debug > 1;
my $o = OpenILS::Utils::Cronscript->new(\%defaults);

my @script_args = ();

if (grep {$_ eq '--'} @ARGV) {
    print "Splitting options into groups\n" if $debug;
    while (@ARGV) {
        $_ = shift @ARGV;
        $_ eq '--' and last;    # stop at the first --
        push @script_args, $_;
    }
} else {
    @script_args = @ARGV;
    @ARGV = ();
}

print "Calling MyGetOptions ",
    (@script_args ? "with options: " . join(' ', @script_args) : 'without options from command line'),
    "\n" if $debug;

my $real_opts = $o->MyGetOptions(\@script_args);
$o->bootstrap;
# GetOptionsFromArray(\@script_args, \%defaults, %defaults); # similar to

$real_opts->{tempdir} ||= tempdir_setting();    # This doesn't go in defaults because it reads config, must come after bootstrap

my $bufsize       = $real_opts->{buffsize};
my $bib_source    = $real_opts->{source};
my $osrf_config   = $real_opts->{'osrf-config'};
my $oils_username = $real_opts->{user};
my $oils_password = $real_opts->{password};
my $help          = $real_opts->{help};
my $merge_profile = $real_opts->{'merge-profile'};
my $queue_id      = $real_opts->{queue};
my $tempdir       = $real_opts->{tempdir};
my $import_by_queue  = $real_opts->{'import-by-queue'};
   $debug        += $real_opts->{debug};

foreach (keys %$real_opts) {
    print("real_opt->{$_} = ", $real_opts->{$_}, "\n") if $real_opts->{debug} or $debug;
}
my $wait_time     = $real_opts->{wait};
my $authtoken     = '';

# DEFAULTS for Net::Server
my $filename   = fileparse($0, '.pl');
my $conf_file  = (-r "$filename.conf") ? "$filename.conf" : undef;
# $conf_file is the Net::Server config for THIS script (not EG), if it exists and is readable


# FEEDBACK

pod2usage(1) if $help;
unless ($oils_password) {
    print STDERR "\nERROR: password option required for session login\n\n";
    # pod2usage(1);
}

print Dumper($o) if $debug;

if ($debug) {
    foreach my $ref (qw/bufsize bib_source osrf_config oils_username oils_password help conf_file debug/) {
        no strict 'refs';
        printf "%16s => %s\n", $ref, (eval("\$$ref") || '');
    }
}

print warning();
print Dumper($real_opts);

# SUBS

sub tempdir_setting {
    my $ret = $apputils->simplereq( qw# opensrf.settings opensrf.settings.xpath.get
        /opensrf/default/apps/open-ils.vandelay/app_settings/databases/importer # );
    return $ret->[0] || '/tmp';
}

sub warning {
    return <<WARNING;

WARNING:  This script provides no security layer.  Any client that has 
access to the server+port can inject MARC records into the system.  

WARNING
}

sub xml_import {
    return $apputils->simplereq(
        'open-ils.cat', 
        'open-ils.cat.biblio.record.xml.import',
        @_
    );
}

sub old_process_batch_data {
    my $data = shift or $logger->error("process_batch_data called without any data");
    my $isfile = shift;
    $data or return;

    my $handle;
    if ($isfile) {
        $handle = $data;
    } else {
        open $handle, '<', \$data; 
    }

    my $batch = MARC::Batch->new('USMARC', $handle);
    $batch->strict_off;

    my $index = 0;
    my $imported = 0;
    my $failed = 0;

    while (1) {
        my $rec;
        $index++;

        eval { $rec = $batch->next; };

        if ($@) {
            $logger->error("Failed parsing MARC record $index");
            $failed++;
            next;
        }
        last unless $rec;   # The only way out

        my $resp = xml_import($authtoken, $rec->as_xml_record, $bib_source);

        # has the session timed out?
        if (oils_event_equals($resp, 'NO_SESSION')) {
            new_auth_token();
            $resp = xml_import($authtoken, $rec->as_xml_record, $bib_source);   # try again w/ new token
        }
        oils_event_die($resp);
        $imported++;
    }

    return ($imported, $failed);
}

sub process_spool { # filename

    my $marcfile = shift;
    my @rec_ids;

    if($import_by_queue) {

        # don't collect the record IDs, just spool the queue

        $apputils->simplereq(
            'open-ils.vandelay', 
            'open-ils.vandelay.bib.process_spool', 
            $authtoken, 
            undef, 
            $queue_id, 
            'import', 
            $marcfile,
            $bib_source 
        );

    } else {

        # collect the newly queued record IDs for processing

        my $req = $vl_ses->request(
            'open-ils.vandelay.bib.process_spool.stream_results',
            $authtoken, 
            undef, # cache key not needed
            $queue_id, 
            'import', 
            $marcfile, 
            $bib_source 
        );
    
        while(my $resp = $req->recv) {

            if($req->failed) {
                $logger->error("Error spooling MARC data: $resp");

            } elsif($resp->content) {
                push(@rec_ids, $resp->content);
            }
        }
    }

    return \@rec_ids;
}

sub bib_queue_import {
    my $rec_ids = shift;
    my $extra = {auto_overlay_exact => 1};
    $extra->{merge_profile} = $merge_profile if $merge_profile;

    my $req;
    my @cleanup_recs;

    if($import_by_queue) {
        # import by queue

        $req = $vl_ses->request(
            'open-ils.vandelay.bib_queue.import', 
            $authtoken, 
            $queue_id, 
            $extra 
        );

    } else {
        # import explicit record IDs

        $req = $vl_ses->request(
            'open-ils.vandelay.bib_record.list.import', 
            $authtoken, 
            $rec_ids, 
            $extra 
        );
    }

    # collect the successfully imported vandelay records
    my $failed = 0;
    while(my $resp = $req->recv) {
         if($req->failed) {
            $logger->error("Error importing MARC data: $resp");

        } elsif(my $data = $resp->content) {

            if($data->{err_event}) {

                $logger->error(Dumper($data->{err_event}));
                $failed++;

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

    foreach (@cleanup_recs) {

        try { 

            $pcrud->request('open-ils.pcrud.delete.vqbr', $authtoken, $_)->recv;

        } catch Error with {
            $err = shift;
            $logger->error("Error deleteing queued bib record $_: $err");
        };
    }

    $pcrud->request('open-ils.pcrud.transaction.commit', $authtoken)->recv unless $err;
    $pcrud->disconnect;

    $logger->info("imported queued vandelay records: @cleanup_recs");
    return (scalar(@cleanup_recs), $failed);
}

sub process_batch_data {
    my $data = shift or $logger->error("process_batch_data called without any data");
    my $isfile = shift;
    $data or return;

    $vl_ses = OpenSRF::AppSession->create('open-ils.vandelay');

    my ($handle, $tempfile);
    if (!$isfile) {
        ($handle, $tempfile) = File::Temp->tempfile("$0_XXXX", DIR => $tempdir) or die "Cannot write tempfile in $tempdir";
        print $handle $data;
        close $handle;
    } else {
        $tempfile = $data;
    }
       
    $logger->info("Calling process_spool on tempfile $tempfile (queue: $queue_id; source: $bib_source)");
    my $rec_ids = process_spool($tempfile);

    if (oils_event_equals($rec_ids, 'NO_SESSION')) {  # has the session timed out?
        new_auth_token();
        $rec_ids = process_spool($tempfile);                # try again w/ new token
    }

    my ($imported, $failed) = bib_queue_import($rec_ids);

    if (oils_event_equals($imported, 'NO_SESSION')) {  # has the session timed out?
        new_auth_token();
        ($imported, $failed) = bib_queue_import();                # try again w/ new token
    }

    oils_event_die($imported);

    return ($imported, $failed);
}

sub process_request {   # The core Net::Server method
    my $self = shift;
    my $client = $self->{server}->{client};

    my $sockname = getpeername($client);
    my ($port, $ip_addr) = unpack_sockaddr_in($sockname);
    $logger->info("stream parser received contact from ".inet_ntoa($ip_addr));

    my $ph = OpenSRF::Transport::PeerHandle->retrieve;
    if(!$ph->flush_socket()) {
        $logger->error("We received a request, bu we are no longer connected to opensrf.  ".
            "Exiting and dropping request from $client");
        exit;
    }

    my $data = '';
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $wait_time; # prevent accidental tie ups of backend processes
        local $/ = "\x1D"; # MARC record separator
        while (my $newline = <STDIN>) {
            $data .= $newline;
            alarm $wait_time; # prevent accidental tie ups of backend processes
        }
        alarm 0;
    };

    if($@) {
        $logger->error("reading from STDIN failed or timed out: $@");
        return;
    } 

    $logger->info("stream parser read " . length($data) . " bytes");

    my ($imported, $failed) = (0, 0);

    new_auth_token(); # login

    if ($real_opts->{noqueue}) {
        ($imported, $failed) = old_process_batch_data($data);
    } else {
        ($imported, $failed) = process_batch_data($data);
    }

    my $profile = (!$merge_profile) ? '' :
        $apputils->simplereq(
            'open-ils.pcrud', 
            'open-ils.pcrud.retrieve.vmp', 
            $authtoken, 
            $merge_profile)->name;

    my $msg = '';
    $msg .= "Successfully imported $imported records using merge profile '$profile'\n" if $imported;
    $msg .= "Failed to import $failed records\n" if $failed;
    $msg .= "\x00";
    print $client $msg;

    clear_auth_token(); # logout
}

sub standalone_process_request {   # The command line version
    my $file = shift;
    
    $logger->info("stream parser received file processing request for $file");

    my $ph = OpenSRF::Transport::PeerHandle->retrieve;
    if(!$ph->flush_socket()) {
        $logger->error("We received a request, bu we are no longer connected to opensrf.  ".
            "Exiting and dropping request for $file");
        exit;
    }

    my ($imported, $failed) = (0, 0);

    new_auth_token(); # login

    if ($real_opts->{noqueue}) {
        ($imported, $failed) = old_process_batch_data($file, 1);
    } else {
        ($imported, $failed) = process_batch_data($file, 1);
    }

    my $profile = (!$merge_profile) ? '' :
        $apputils->simplereq(
            'open-ils.pcrud', 
            'open-ils.pcrud.retrieve.vmp', 
            $authtoken, 
            $merge_profile)->name;

    my $msg = '';
    $msg .= "Successfully imported $imported records using merge profile '$profile'\n" if $imported;
    $msg .= "Failed to import $failed records\n" if $failed;
    $msg .= "\x00";
    print $msg;

    clear_auth_token(); # logout
}


# the authtoken will timeout after the configured inactivity period.
# When that happens, get a new one.
sub new_auth_token {
    $authtoken = oils_login($oils_username, $oils_password, 'staff') 
        or die "Unable to login to Evergreen as user $oils_username";
    return $authtoken;
}

sub clear_auth_token {
    $apputils->simplereq(
        'open-ils.auth',
        'open-ils.auth.session.delete',
        $authtoken
    );
}

##### MAIN ######

osrf_connect($osrf_config);
if ($real_opts->{nodaemon}) {
    if (!$real_opts->{spoolfile}) {
        print " --nodaemon mode requested, but no --spoolfile supplied!\n";
        exit;
    }
    standalone_process_request($real_opts->{spoolfile});
} else {
    print "Calling Net::Server run ", (@ARGV ? "with command-line options: " . join(' ', @ARGV) : ''), "\n";
    __PACKAGE__->run(conf_file => $conf_file);
}

__END__

=head1 NAME

marc_stream_importer.pl - Import MARC records via bare socket connection.

=head1 SYNOPSIS

./marc_stream_importer.pl [common opts ...] [script opts ...] -- [Net::Server opts ...] &

This script uses the EG common options from B<Cronscript>.  See --help output for those.

Run C<perldoc marc_stream_importer.pl> for full documentation.

Note the extra C<--> to separate options for the script wrapper from options for the
underlying L<Net::Server> options.  

Note: this script has to be run in the same directory as B<oils_header.pl>.

Typical server-style execution will include a trailing C<&> to run in the background.

=head1 DESCRIPTION

This script is a L<Net::Server::PreFork> instance for shoving records into Evergreen from a remote system.

=head1 OPTIONS

The only required option is --password

 --password         =<eg_password>
 --user             =<eg_username>  default: admin
 --source           =<bib_source>   default: 1         Integer
 --merge-profile    =<i>            default: 0
 --tempdir          =</temp/dir/>   default: from L<opensrf.conf> <open-ils.vandelay/app_settings/databases/importer>
 --source           =<i>            default: 1
 --import-by-queue  =<i>            default: 0
 --spoolfile        =<import_file>  default: NONE      File to import in --nodaemon mode
 --nodaemon                         default: OFF       When used with --spoolfile, turns off Net::Server mode and runs this utility in the foreground


=head2 Old style: --noqueue and associated options

To bypass vandelay queue processing and push directly into the database (as the old style)

 --noqueue         default: OFF
 --buffsize =<i>   default: 4096    Buffer size.  Only used by --noqueue
 --wait     =<i>   default: 5       Seconds to read socket before processing.  Only used by --noqueue

=head2 Net::Server Options

By default, the script will use the Net::Server configuration file B<marc_stream_importer.conf>.  You can 
override this by passing a filepath with the --conf_file option.

Other Net::Server options include: --port=<port> --min_servers=<X> --max_servers=<Y> and --log_file=[path/to/file]

See L<Net::Server> for a complete list.

=head2 Configuration

=head3 OCLC Connexion

To use this script with OCLC Connexion, configure the client as follows:

Under Tools -> Options -> Export (tab)
   Create -> Choose Connection -> OK -> Leave translation at "None" 
       -> Create -> Create -> choose TCP/IP (internet) 
       -> Enter hostname and Port, leave 'Use Telnet Protocol' checked 
       -> Create/OK your way out of the dialogs
   Record Characteristics (button) -> Choose 'UTF-8 Unicode' for the Character Set
   

OCLC and Connexion are trademark/service marks of OCLC Online Computer Library Center, Inc.

=head1 CAVEATS

WARNING: This script provides no inherent security layer.  Any client that has 
access to the server+port can inject MARC records into the system.  
Use the available options (like allow/deny) in the Net::Server config file 
or via the command line to restrict access as necessary.

=head1 EXAMPLES

./marc_stream_importer.pl  \
    admin open-ils connexion --port 5555 --min_servers 2 \
    --max_servers=20 --log_file=/openils/var/log/marc_net_importer.log &

./marc_stream_importer.pl  \
    admin open-ils connexion --port 5555 --min_servers 2 \
    --max_servers=20 --log_file=/openils/var/log/marc_net_importer.log &

=head1 SEE ALSO

L<Net::Server::PreFork>, L<marc_stream_importer.conf>

=head1 AUTHORS

    Bill Erickson <erickson@esilibrary.com>
    Joe Atzberger <jatzberger@esilibrary.com>
    Mike Rylander <miker@esilibrary.com> (nodaemon+spoolfile mode)

=cut
