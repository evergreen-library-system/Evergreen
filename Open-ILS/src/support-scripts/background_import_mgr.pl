#!/usr/bin/perl
# Copyright (C) 2023 Equinox Software, Inc.
# Author: Mike Rylander <mrylander@gmail.com>
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
$ENV{OSRF_LOG_CLIENT} = 1;

use Data::Dumper;
use File::Temp;
use Getopt::Long qw(:DEFAULT GetOptionsFromArray);
use Pod::Usage;
use File::Spec;

use OpenSRF::System;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::AppSession;
use OpenSRF::MultiSession;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::AppUtils;

my $apputils = 'OpenILS::Application::AppUtils';
my $editor;

my $osrf_config   = '/openils/conf/opensrf_core.xml';
my $parallel      = 1;
my $help          = undef;
my $fixup         = undef;

my $debug = 0;

GetOptions(
    'osrf-config=s'         => \$osrf_config,
    'parallel=i'            => \$parallel,
    'fixup'                 => \$fixup,
    'debug'                 => \$debug,
    'help'                  => \$help,
);

# FEEDBACK

pod2usage(1) if $help;

if ($debug) {
    foreach my $ref (qw/osrf_config help debug/) {
        no strict 'refs';
        printf "%16s => %s\n", $ref, (eval("\$$ref") || '');
    }
}

# -----------------------------------------------------
# subs
# -----------------------------------------------------

# log in
sub new_auth_token {
    my $job_owner_id = shift;
    my $job_ws_id = shift;

    my $login_params = {
        user_id => $job_owner_id,
        login_type => 'staff',
    };

    if ($job_ws_id) {
        my $ws = $editor->retrieve_actor_workstation($job_ws_id);
        $$login_params{workstation} = $ws->name if ($ws);
    }

    my $auth_resp = $apputils->simplereq(
        'open-ils.auth_internal',
        'open-ils.auth_internal.session.create',
        $login_params
    );

    my $authtoken;
    unless (
        $auth_resp &&
        $auth_resp->{payload} &&
        ($authtoken = $auth_resp->{payload}->{authtoken})
    ) {
        $logger->error("Could not create an internal auth session for user $job_owner_id at WS $$job_ws_id");
        $authtoken = undef;
    }

    return $authtoken;
}

# log out
sub clear_auth_token {
    my $token = shift;
    $apputils->simplereq(
        'open-ils.auth',
        'open-ils.auth.session.delete',
        $token
    ) if $token;
}

# gather background imports by state
sub get_imports {
    my $state = shift;
    return [] unless $state;
    return $editor->search_vandelay_background_import({state => $state});
}

sub get_new_imports { return get_imports('new') }
sub get_running_imports { return get_imports('running') }

sub update_job {
    my $job = shift;
    return undef unless $editor->xact_begin;
    unless ($editor->update_vandelay_background_import($job)) {
        $editor->xact_rollback;
        return undef;
    }
    return undef unless $editor->xact_commit;
    return $job;
}

sub finalize_running_imports {
    my $running = get_running_imports();
    for my $job ( @$running ) {
        next unless $job->queue;

        my $basic_type = $job->import_type eq 'auth' ? 'authority' : 'bib';
        my $method = "retrieve_vandelay_${basic_type}_queue";
        my $queue = $editor->$method($job->queue);
        next unless $queue;

        if ($apputils->is_true($queue->complete)) {
            $job->state('complete');
            $job->complete_time('now');
            if (update_job($job)) {
                my $token = new_auth_token($job->owner, $job->workstation);
                create_event($token, $job);
                clear_auth_token($token);
            } else {
                $logger->error("Could not mark background import job ".$job->id." complete");
            }
        }
    }
}

sub resolve_queue {
    my $job = shift;
    my $token = shift;
    my $params = shift;

    return $job->queue if $job->queue;
    return $$params{existing_queue} if $$params{existing_queue};

    my $qname = $$params{new_queue_name};
    return undef unless $qname;

    $logger->info("Creating new queue {$qname} for job ".$job->id."...");
    my $holdings_profile = $$params{holdings_profile};
    my $match_set = $$params{match_set};
    my $match_bucket = $$params{match_bucket};

    my $qtype = $job->import_type eq 'auth' ? 'auth' : 'bib';
    my $method = "open-ils.vandelay.${qtype}_queue.create";

    my $queue = $apputils->simplereq(
            'open-ils.vandelay', $method,
            $token, $qname, undef, $job->import_type,
            $match_set, $holdings_profile, $match_bucket
    );

    if (ref($queue) 
        && (   $queue->isa("Fieldmapper::vandelay::bib_queue")
            || $queue->isa("Fieldmapper::vandelay::authority_queue")
        )
    ) {
        $logger->info("... successfully created queue for job ".$job->id);
        $job->queue($queue->id);
        unless (update_job($job)) {
            $logger->error("Could not update queue of background import job ".$job->id);
            return undef;
        }
        return $queue->id;
    }

    return undef;
}

sub run_new_imports {
    my $new_jobs = get_new_imports();

    my $multi_vand = OpenSRF::MultiSession->new(
        app => 'open-ils.vandelay',
        cap => $parallel,
        api_level => 1,
        success_handler => sub {
            my $me = shift;
            my $req = shift;

            # list of imported ids
            $req->{hash}->{process_spool_response} = [
                map {$_->content} @{$req->{response}}
            ];

            $logger->info("Queued record IDs processed for job ".$req->{hash}->{job}->id.": ".join(',',@{$req->{hash}->{process_spool_response}}));
        }
    );

    my $multi_acq = OpenSRF::MultiSession->new(
        app => 'open-ils.acq',
        cap => $parallel,
        api_level => 1,
        success_handler => sub {
            my $me = shift;
            my $req = shift;

            # list of imported ids
            my ($import_queue) = map {
                $_->id
            } grep {
                defined
            } map {
                $_->content->{queue}
            } @{$req->{response}};

            my $job = $req->{hash}->{job};

            $job->queue($import_queue);
            $job->state('complete');
            $job->complete_time('now');

            $logger->info("ACQ processing complete for job ".$job->id);

            if (update_job($job)) {
                create_event($req->{hash}->{token}, $job);
            } else {
                $logger->error("Could not mark background import job ".$job->id." complete");
            }

            clear_auth_token($req->{hash}->{token});
                $logger->info("ACQ imported records processed for job ".$job->id);
        }
    );

    my %running_vjobs;
    my %running_ajobs;
    NEWJOB: for my $job ( @$new_jobs ) { # process spools, or pull overlay maps out of the param blob
        next unless $job->params; # we can't do anything without instructions

        my $p = OpenSRF::Utils::JSON->JSON2perl($job->params);
        next unless ($$p{spool_filename}); # we only operate on new uploaded files, for now
        next unless ($job->import_type eq 'acq' || $job->queue || $$p{selected_queue} || $$p{new_queue_name}); # and we need a queue for bib import

        # "log in" as the job owner
        my $token = new_auth_token($job->owner, $job->workstation);
        next unless $token;

        if ($job->import_type eq 'acq') {
            $logger->info("Processing {$$p{spool_filename}} via ACQ for job ".$job->id);
        
            my $jid = $job->id;
            $running_ajobs{$jid} = {
                job => $job, token => $token,
                params => $p
            };

            # ok, we can claim we're running it now....
            $job->state('running');
            unless (update_job($job)) {
                $logger->error("Could not update background import job $jid\n");
                delete $running_ajobs{$jid};
                clear_auth_token($token);
                next NEWJOB;
            }

            $$p{vandelay} = { %$p }; # duplicate the flat params as the API expects

            $multi_acq->request(
                $running_ajobs{$jid}, # passed into handlers
                "open-ils.acq.process_upload_records",
                $token, '', $p
            );
        } else {
            my $queue_id = resolve_queue($job, $token, $p);

            if ($queue_id) { # if we got this far, we are almost ready to set the state to running
                $logger->info("Processing {$$p{spool_filename}} into queue $queue_id for job ".$job->id);
            
                my $jid = $job->id;
                $running_vjobs{$jid} = {
                    job => $job, token => $token,
                    queue => $queue_id, params => $p
                };

                # ok, we can claim we're running it now....
                $job->state('running');
                unless (update_job($job)) {
                    $logger->error("Could not update background import job $jid\n");
                    delete $running_vjobs{$jid};
                    clear_auth_token($token);
                    next NEWJOB;
                }

                my $basic_type = $job->import_type eq 'auth' ? 'auth' : 'bib';
                $multi_vand->request(
                    $running_vjobs{$jid}, # passed into handlers
                    "open-ils.vandelay.$basic_type.process_spool.stream_results",
                    $token,
                    '',
                    $queue_id,
                    $$p{upload_purpose} || undef,
                    $$p{spool_filename},
                    $$p{bib_source} || undef,
                    $$p{session_name} || undef
                );
            }
        }
    }

    # now we wait for any spools to process
    $multi_vand->session_wait(1) if (keys %running_vjobs);
    $multi_acq->session_wait(1) if (keys %running_ajobs);
    $multi_acq->disconnect;

    # new handler, just marking the job complete
    $multi_vand->{success_handler} = sub {
        my $me = shift;
        my $req = shift;
        my $job = $req->{hash}->{job};

        $job->state('complete');
        $job->complete_time('now');

        $logger->info("Additional queue processing complete for job ".$job->id);

        if (update_job($job)) {
            create_event($req->{hash}->{token}, $job);
        } else {
            $logger->error("Could not mark background import job ".$job->id." complete");
        }

        clear_auth_token($req->{hash}->{token});
    };

    # Now process queues overlay maps, as the case may be
    my @processing;
    for my $jid (keys %running_vjobs) {
        my $j = $running_vjobs{$jid};
        my $job = $$j{job};
        my $p = $$j{params};

        if (import_action_supplied($p)) { # process records!
            push @processing, $jid;
            my $basic_type = $job->import_type eq 'auth' ? 'auth' : 'bib';
            $multi_vand->request(
                $j, "open-ils.vandelay.${basic_type}_queue.import",
                $$j{token}, $$j{queue}, $p
            );
            
        } else {

            $logger->info("Basic queue processing complete for job ".$job->id);
            $job->state('complete');
            $job->complete_time('now');

            if (update_job($job)) {
                create_event($$j{token}, $job);
            } else {
                $logger->error("Could not mark background import job $jid complete");
            }
            clear_auth_token($$j{token});
        }
    }

    # now wait for any record processing to complete
    $multi_vand->session_wait(1) if @processing;
    $multi_vand->disconnect;
}

sub create_event {
    my $auth = shift;
    my $job = shift;
    return unless $job->email;

    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    $apputils->simplereq(
        'open-ils.trigger', 'open-ils.trigger.event.autocreate',
        'vandelay.background_import.completed', $job, $e->requestor->ws_ou
    );
}

sub import_action_supplied {
    my $p = shift;
    return $$p{import_no_match}
        || $$p{auto_overlay_exact}
        || $$p{auto_overlay_1match}
        || $$p{auto_overlay_best_match};
}

# These were stolen from oils_header.pl
sub _caller {
    my ($pkg, $file, $line, $sub)  = caller(2);
    if(!$line) {
        ($pkg, $file, $line)  = caller(1);
        $sub = "";
    }
    return ($pkg, $file, $line, $sub);
}

sub err {
    my ($pkg, $file, $line, $sub)  = _caller();
    no warnings;
    die "Script halted with error ".
        "($pkg : $file : $line : $sub):\n" . shift() . "\n";
}

sub osrf_connect {
    my $config = shift;
    err("Bootstrap config required") unless $config;
    OpenSRF::System->bootstrap_client( config_file => $config );
    Fieldmapper->import(IDL =>
        OpenSRF::Utils::SettingsClient->new->config_value("IDL"));
    reset_cstore();
}

sub reset_cstore {
    my ($key) = grep { $_ =~ /OpenILS.*CStoreEditor/o } keys %INC;
    return unless $key;
    delete $INC{$key};
    my $h = $SIG{__WARN__};
    $SIG{__WARN__} = sub {};
    require OpenILS::Utils::CStoreEditor;
    $SIG{__WARN__} = $h;
}

# -----------------------------------------------------
# Main script
# -----------------------------------------------------

osrf_connect($osrf_config);
$editor = OpenILS::Utils::CStoreEditor->new;

if ($fixup) {
    finalize_running_imports();
} else {
    run_new_imports();
}

$editor->disconnect;

exit 0;

=head1 NAME

background_import_mgr.pl - Process requested Vandelay background imports

=head1 SYNOPSIS

./background_import_mgr.pl [script opts ...]

=head1 OPTIONS

 --osrf-config=<OpenSRF config file location>   Default: /openils/conf/opensrf_core.xml
                Configuration file used to connect to the OpenSRF
                network hosting an Evergreen instance.

 --parallel=<max parallel Vandelay sessions>    Default: 1
                Maximum concurrent Vandelay sessions used to process
                outstanding background import job requests.

 --fixup        Mark completed Vandelay processing jobs if this management
                script fails or is killed for some reason.

 --help         Show this help.

 --debug        Show additional debugging output.

=head1 EXAMPLES

# Run if regular processing failed for some reason, to clean up completed queues.
./background_import_mgr.pl --osrf-config=/openils/conf/opensrf.xml --fixup

# Run regularly from cron, up to 5 concurrent jobs per step.
./background_import_mgr.pl --osrf-config=/openils/conf/opensrf.xml --parallel=5

=head1 AUTHORS

    Mike Rylander <mrylander@gmail.com>

=cut

