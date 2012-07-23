#!/usr/bin/perl
# Copyright (C) 2012 Equinox Software, Inc.
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
use MARC::Record;
use MARC::Batch;
use MARC::File::XML ( BinaryEncoding => 'UTF-8' );
use MARC::File::USMARC;

use Data::Dumper;
use File::Temp;
use Getopt::Long qw(:DEFAULT GetOptionsFromArray);
use Pod::Usage;
use File::Spec;

use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::AppSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;
use OpenILS::Utils::Cronscript;
use OpenILS::Utils::CStoreEditor;
use OpenILS::Utils::Fieldmapper;
require 'oils_header.pl';
use vars qw/$apputils/;

my $acq_ses;
my $authtoken;
my $conf;
my $cache;
my $editor;
my $base_dir;
my $share_dir;
my $providers;
my $debug = 0;

my %defaults = (
    'osrf-config=s' => '/openils/conf/opensrf_core.xml',
    'user=s'        => 'admin',
    'password=s'    => '',
    'nodaemon'      => 0,
    'poll-interval=i' => 10
);

# -----------------------------------------------------
# Command-line args reading / munging
# -----------------------------------------------------
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

my $osrf_config   = $real_opts->{'osrf-config'};
my $oils_username = $real_opts->{user};
my $oils_password = $real_opts->{password};
my $help          = $real_opts->{help};
my $poll_interval = $real_opts->{'poll-interval'};
   $debug         += $real_opts->{debug};

foreach (keys %$real_opts) {
    print("real_opt->{$_} = ", $real_opts->{$_}, "\n") if $real_opts->{debug} or $debug;
}

# FEEDBACK

pod2usage(1) if $help;
unless ($oils_password) {
    print STDERR "\nERROR: password option required for session login\n\n";
}

$debug and print Dumper($o);

if ($debug) {
    foreach my $ref (qw/osrf_config oils_username oils_password help debug/) {
        no strict 'refs';
        printf "%16s => %s\n", $ref, (eval("\$$ref") || '');
    }
}

$debug and print Dumper($real_opts);

# -----------------------------------------------------
# subs
# -----------------------------------------------------

# log in
sub new_auth_token {
    $authtoken = oils_login($oils_username, $oils_password, 'staff') 
        or die "Unable to login to Evergreen as user $oils_username";
    return $authtoken;
}

# log out
sub clear_auth_token {
    $apputils->simplereq(
        'open-ils.auth',
        'open-ils.auth.session.delete',
        $authtoken
    );
}

sub push_file_to_acq {
    my $file = shift;
    my $args = shift;

    $logger->info("acq-or: pushing file '$file' to provider " . $args->{provider});

    # Cache the file name like Vandelay does.  ACQ will 
    # read contents of the cache and then delete them.
    # The key can be any unique value.
    my $key = $$ . time . rand();
    $cache->put_cache("vandelay_import_spool_$key", {path => $file});

    # some arguments are not optional
    $args->{create_po} = 1;

    # don't send our internal args to the service
    my $local = delete $args->{_local};

    my $req = $acq_ses->request(
        'open-ils.acq.process_upload_records',
        $authtoken,
        $key, 
        $args
    );

    while (my $resp = $req->recv(timeout => 600)) {
        if(my $content = $resp->content) {
            $debug and print Dumper($content);
        } else {
            warn "Request returned no data: " . Dumper($resp) . "\n";
        }
    }

    # TODO: delete tmp queue?
}

my %org_cache;
sub org_from_sn {
    my $sn = shift;
    return $org_cache{$sn} if $org_cache{$sn};
    my $org = $editor->search_actor_org_unit({shortname => $sn})->[0];
    if (!$org) {
        warn "No such org unit in acq_order_reader config: '$sn'\n";
        return undef;
    }
    return $org_cache{$sn} = $org;
}

# translate config info into a request arguments structure
sub args_from_provider_conf {
    my $conf = shift;
    my %args;

    my $pcode = $conf->{code};
    my $orgsn = $conf->{owner};

    $debug and print "Extracting request args for provider $pcode at $orgsn\n";

    my $org = org_from_sn($conf->{owner}) or return undef;

    my $provider = $editor->search_acq_provider({
        code => $pcode,
        owner => $org->id
    })->[0];

    if (!$provider) {
        warn "No such provider in acq_order_reader config: '$pcode'\n";
        return undef;
    }

    my $oa = org_from_sn($conf->{ordering_agency}) or return undef;

    $args{provider} = $provider->id;
    $args{ordering_agency} = $oa->id;
    $args{activate_po} = ($conf->{activate_po} || '') =~ /true/i;
    
    # vandelay import options
    my $vconf = $conf->{vandelay} || {};
    $args{vandelay} = {};

    # value options
    for my $opt (
        qw/
            match_quality_ratio 
            match_set 
            bib_source 
            merge_profile / ) {

        $args{vandelay}->{$opt} = $vconf->{$opt} 
    }

    # bool options
    for my $opt (
        qw/
            create_assets
            import_no_match 
            auto_overlay_exact 
            auto_overlay_1match 
            auto_overlay_best_match/ ) {

        $args{vandelay}->{$opt} = 1 if ($vconf->{$opt} || '') =~ /true/i;
    }

    if ($vconf->{queue}) {
        $args{vandelay}->{queue_name} = $vconf->{queue};
        $args{vandelay}->{existing_queue} = $vconf->{queue};

    } else {

        # create a temporary queue
        $args{vandelay}->{queue_name} = sprintf("acq-order-reader-%s-%s-%s", 
            $org->shortname, $provider->code, $apputils->epoch2ISO8601(time));
    }

    $args{_local} = {
        provider_code => $pcode, # good for debugging
        dirname => File::Spec->catfile($base_dir, $conf->{subdir})
    };

    return \%args;
}

# returns the list of new order record files that
# need to be processed for this vendor
sub check_provider_files {
    my $args = shift;
    my $dirname = $args->{_local}->{dirname};
    my $dh;
    my @files;

    $debug and print "Searching for new files at $dirname\n";

    if ( !opendir($dh, $dirname) ) {
        warn "Couldn't open dir '$dirname': $!";
        return @files;
    }

    @files = readdir $dh;
    # ignore '.', '..', and hidden files
    @files = grep {$_ !~ /^\./} @files;

    $logger->info("acq-or: found " . scalar(@files) . " ACQ order files at $dirname");

    # return the file names w/ full path
    return map {File::Spec->catfile($dirname, $_)} @files;
}

# -----------------------------------------------------
# Main script
# -----------------------------------------------------

osrf_connect($osrf_config);

$conf = OpenSRF::Utils::SettingsClient->new;
$cache = OpenSRF::Utils::Cache->new;
$editor = OpenILS::Utils::CStoreEditor->new;
$acq_ses = OpenSRF::AppSession->create('open-ils.acq');

my $user = $editor->search_actor_user({usrname => $oils_username})->[0];
if (!$user) {
    warn "Invalid user: $oils_username\n";
    exit;
}

# read configs
$base_dir = $conf->config_value(acq_order_reader => 'base_dir');
$share_dir = $conf->config_value(acq_order_reader => 'shared_subdir');
$providers = $conf->config_value(acq_order_reader => 'provider');
$providers = [$providers] unless ref $providers eq 'ARRAY';

$debug and print Dumper($providers);

# -----------------------------------------------------
# main loop
# for each provider directory, plus the shared directory, check
# to see if there are any files pending.  For any files found, push
# them up to the ACQ service, then delete the file
while (1) {

    new_auth_token();
    my $processed = 0;

    # explicit providers
    for my $provider_conf (@$providers) {
        my $args = args_from_provider_conf($provider_conf) or next;
        my @files = check_provider_files($args);
        push_file_to_acq($_, $args) for @files;
        $processed += scalar(@files);
    }
    
    # shared directory
    # TODO

    clear_auth_token();

    $logger->info("acq-or: loop processed $processed files");

    $SIG{INT} = sub { 
        print "Cleaning up...\n";
        exit; # allows lockfile cleanup
    };

    # processing takes time.  If we processed any records
    # during the current iteration, immediately check again
    # for more work.  Otherwise, wait $poll_interval seconds
    sleep $poll_interval if $processed == 0;
}

__END__

=head1 NAME

acq_order_reader.pl - Collect MARC order record files and pass them onto the ACQ service

=head1 SYNOPSIS

./acq_order_reader.pl [script opts ...]

This script uses the EG common options from B<Cronscript>.  See --help output for those.

Run C<perldoc marc_stream_importer.pl> for full documentation.

Note: this script has to be run in the same directory as B<oils_header.pl>.

Typical server-style execution will include a trailing C<&> to run in the background.

=head1 OPTIONS

The only required option is --password

 --password         =<eg_password>
 --user             =<eg_username>  default: admin
 --nodaemon                         default: OFF       When used with --spoolfile, turns off Net::Server mode and runs this utility in the foreground


=head2 Old style: --noqueue and associated options

=head1 EXAMPLES

./acq_order_reader.pl --user admin --password demo123

./acq_order_reader.pl --user admin --password demo123 -poll-interval 3 --debug --nodaemon

=head1 AUTHORS

    Bill Erickson <erickson@esilibrary.com>
    Code liberally copied from marc_stream_importer.pl

=cut
