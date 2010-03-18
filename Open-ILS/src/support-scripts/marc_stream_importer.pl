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


use strict; use warnings;
use Net::Server::PreFork;
use base qw/Net::Server::PreFork/;
use MARC::Record;
use MARC::Batch;
use MARC::File::XML;
use MARC::File::USMARC;

use Data::Dumper;
use File::Basename qw/fileparse/;
use File::Temp;
use Getopt::Long qw(:DEFAULT GetOptionsFromArray);
use Pod::Usage;

use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::Cronscript;
require 'oils_header.pl';
use vars qw/$apputils/;

my $debug = 0;

my %defaults = (
    'buffsize=i'    => 4096,
    'merge=i'       => 0,
    'source=i'      => 1,
#    'osrf-config=s' => '/openils/conf/opensrf_core.xml',
    'user=s'        => 'admin',
    'password=s'    => '',
    'tempdir=s'     => '',
    'nolockfile'    => 1,
    'queue'         => 1,
    'noqueue'       => 0,
    'wait=i'        => 5,
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
my $merge_profile = $real_opts->{merge_profile};
my $queue_id      = $real_opts->{queue};
my $tempdir       = $real_opts->{tempdir};
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
    $data or return;

    my $handle;
    open $handle, '<', \$data; 
    my $batch = MARC::Batch->new('USMARC', $handle);
    $batch->strict_off;

    my $index = 0;
    while (1) {
        my $rec;
        $index++;

        eval { $rec = $batch->next; };

        if ($@) {
            $logger->error("Failed parsing MARC record $index");
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
    }
    return $index;
}

sub process_spool {     # filename
    $apputils->simplereq('open-ils.vandelay', 'open-ils.vandelay.bib.process_spool', $authtoken, undef,
                         $queue_id, 'import', shift, $bib_source );
}
sub bib_queue_import {
    my $extra = {auto_overlay_exact => 1};
    $extra->{merge_profile} = $merge_profile if $merge_profile;
    $apputils->simplereq('open-ils.vandelay', 'open-ils.vandelay.bib_queue.import', $authtoken,
                         $queue_id, $extra );
}

sub process_batch_data {
    my $data = shift or $logger->error("process_batch_data called without any data");
    $data or return;

    my ($handle, $tempfile) = File::Temp(DIR => $tempdir) or die "Cannot write tempfile in $tempdir";
    print $handle $data;
    close $handle;
       
    my $resp = process_spool($tempfile);

    if (oils_event_equals($resp, 'NO_SESSION')) {  # has the session timed out?
        new_auth_token();
        $resp = process_spool($tempfile);                # try again w/ new token
    }

    $resp = bib_queue_import();

    if (oils_event_equals($resp, 'NO_SESSION')) {  # has the session timed out?
        new_auth_token();
        $resp = bib_queue_import();                # try again w/ new token
    }
    oils_event_die($resp);
}

sub process_request {   # The core Net::Server method
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
    if ($real_opts->{noqueue}) {
        old_process_batch_data($data);
    } else {
        process_batch_data($data);
    }
}


# the authtoken will timeout after the configured inactivity period.
# When that happens, get a new one.
sub new_auth_token {
    $authtoken = oils_login($oils_username, $oils_password, 'staff') 
        or die "Unable to login to Evergreen as user $oils_username";
    return $authtoken;
}

##### MAIN ######

osrf_connect($osrf_config);
new_auth_token();
print "Calling Net::Server run ", (@ARGV ? "with command-line options: " . join(' ', @ARGV) : ''), "\n";
__PACKAGE__->run(conf_file => $conf_file);

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

Typical execution will include a trailing C<&> to run in the background.

=head1 DESCRIPTION

This script is a L<Net::Server::PreFork> instance for shoving records into Evergreen from a remote system.

=head1 OPTIONS

The only required option is --password

 --password =<eg_password>
 --user     =<eg_username>   default: admin
 --source   =<bib_source>    default: 1         Integer
 --merge    =<i>             default: 0
 --tempdir  =</temp/dir/>    default: from L<opensrf.conf> <open-ils.vandelay/app_settings/databases/importer>
 --source   =<i>             default: 1

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

=head1 SEE ALSO

L<Net::Server::PreFork>, L<marc_stream_importer.conf>

=head1 AUTHORS

    Bill Erickson <erickson@esilibrary.com>
    Joe Atzberger <jatzberger@esilibrary.com>

=cut
