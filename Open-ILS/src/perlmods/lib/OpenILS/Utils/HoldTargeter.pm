package OpenILS::Utils::HoldTargeter;
# ---------------------------------------------------------------
# Copyright (C) 2016 King County Library System
# Author: Bill Erickson <berickxx@gmail.com>
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
use DateTime;
use OpenSRF::AppSession;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::JSON;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

our $U = "OpenILS::Application::AppUtils";
our $dt_parser = DateTime::Format::ISO8601->new;

# See open-ils.hold-targeter API docs for runtime arguments.
sub new {
    my ($class, %args) = @_;
    my $self = {
        editor => new_editor(),
        ou_setting_cache => {},
        targetable_statuses => [],
        %args,
    };
    return bless($self, $class);
}

# Returns a list of hold ID's
sub find_holds_to_target {
    my $self = shift;

    if ($self->{hold}) {
        # $self->{hold} can be a single hold ID or an array ref of hold IDs
        return @{$self->{hold}} if ref $self->{hold} eq 'ARRAY';
        return ($self->{hold});
    }

    my $query = {
        select => {ahr => ['id']},
        from => 'ahr',
        where => {
            capture_time => undef,
            fulfillment_time => undef,
            cancel_time => undef,
            frozen => 'f'
        },
        order_by => [
            {class => 'ahr', field => 'selection_depth', direction => 'DESC'},
            {class => 'ahr', field => 'request_time'},
            {class => 'ahr', field => 'prev_check_time'}
        ]
    };

    # Target holds that have no prev_check_time or those whose re-target
    # time has come.  If a soft_retarget_time is specified, that acts as
    # the boundary.  Otherwise, the retarget_time is used.
    my $start_time = $self->{soft_retarget_time} || $self->{retarget_time};
    $query->{where}->{'-or'} = [
        {prev_check_time => undef},
        {prev_check_time => {'<=' => $start_time->strftime('%F %T%z')}}
    ];

    # parallel < 1 means no parallel
    my $parallel = ($self->{parallel_count} || 0) > 1 ? 
        $self->{parallel_count} : 0;

    if ($parallel) {
        # In parallel mode, we need to also grab the metarecord for each hold.
        $query->{from} = {
            ahr => {
                rhrr => {
                    fkey => 'id',
                    field => 'id',
                    join => {
                        mmrsm => {
                            field => 'source',
                            fkey => 'bib_record'
                        }
                    }
                }
            }
        };

        # In parallel mode, only process holds within the current process
        # whose metarecord ID modulo the parallel targeter count matches
        # our paralell targeting slot.  This ensures that no 2 processes
        # will be operating on the same potential copy sets.
        #
        # E.g. Running 5 parallel and we are slot 3 (0-based slot 2) of 5, 
        # process holds whose metarecord ID's are 2, 7, 12, 17, ...
        # WHERE MOD(mmrsm.id, 5) = 2

        # Slots are 1-based at the API level, but 0-based for modulo.
        my $slot = $self->{parallel_slot} - 1;

        $query->{where}->{'+mmrsm'} = {
            metarecord => {
                '=' => {
                    transform => 'mod',
                    value => $slot,
                    params => [$parallel]
                }
            }
        };
    }

    # Newest-first sorting cares only about hold create_time.
    $query->{order_by} =
        [{class => 'ahr', field => 'request_time', direction => 'DESC'}]
        if $self->{newest_first};

    my $holds = $self->editor->json_query($query, {substream => 1});

    return map {$_->{id}} @$holds;
}

sub editor {
    my $self = shift;
    return $self->{editor};
}

# Load startup data required by all targeter actions.
sub init {
    my $self = shift;
    my $e = $self->editor;

    # See if the caller provided an interval
    my $interval = $self->{retarget_interval};

    if (!$interval) { 
        # See if we have a global flag value for the interval

        $interval = $e->search_config_global_flag({
            name => 'circ.holds.retarget_interval',
            enabled => 't'
        })->[0];

        # If no flag is present, default to a 24-hour retarget interval.
        $interval = $interval ? $interval->value : '24h';
    }

    my $retarget_seconds = interval_to_seconds($interval);

    $self->{retarget_time} = DateTime->now(time_zone => 'local')
        ->subtract(seconds => $retarget_seconds);

    $logger->info("Using retarget time: ".
        $self->{retarget_time}->strftime('%F %T%z'));

    if ($self->{soft_retarget_interval}) {

        my $secs = OpenILS::Utils::DateTime->interval_to_seconds(
            $self->{soft_retarget_interval});

        $self->{soft_retarget_time} = 
            DateTime->now(time_zone => 'local')->subtract(seconds => $secs);

        $logger->info("Using soft retarget time: " .
            $self->{soft_retarget_time}->strftime('%F %T%z'));
    }

    # Holds targeted in the current targeter instance not be retargeted
    # until the next check date.  If a next_check_interval is provided
    # it overrides the retarget_interval.
    my $next_check_secs = 
        $self->{next_check_interval} ?
        OpenILS::Utils::DateTime->interval_to_seconds($self->{next_check_interval}) :
        $retarget_seconds;

    my $next_check_date = 
        DateTime->now(time_zone => 'local')->add(seconds => $next_check_secs);

    my $next_check_time = $next_check_date->strftime('%F %T%z');

    $logger->info("Next check time: $next_check_time");

    # An org unit is considered closed for retargeting purposes
    # if it's closed both now and at the next re-target date.
    my $closed = $self->editor->search_actor_org_unit_closed_date({
        '-and' => [{   
            close_start => {'<=', 'now'},
            close_end => {'>=', 'now'}
        }, {
            close_start => {'<=', $next_check_time},
            close_end => {'>=', $next_check_time}
        }]
    });

    my @closed_orgs = map {$_->org_unit} @$closed;
    $logger->info("closed org unit IDs: @closed_orgs");

    # Map of org id to 1. Any org in the map is closed.
    $self->{closed_orgs} = {map {$_ => 1} @closed_orgs};

    my $hopeless_prone = $self->editor->search_config_copy_status({
        hopeless_prone => 't'
    });
    $self->{hopeless_prone_status_ids} = { map { $_->id => 1} @{ $hopeless_prone } };
}


# Org unit setting fetch+cache
# $e is the OpenILS::Utils::HoldTargeter::Single editor.  Use it if
# provided to avoid timeouts on the in-transaction child editor.
sub get_ou_setting {
    my ($self, $org_id, $setting, $e) = @_;
    my $c = $self->{ou_setting_cache};

    $e ||= $self->{editor};
    $c->{$org_id} = {} unless $c->{$org_id};

    $c->{$org_id}->{$setting} =
        $U->ou_ancestor_setting_value($org_id, $setting, $e)
        unless exists $c->{$org_id}->{$setting};

    return $c->{$org_id}->{$setting};
}

# Fetches settings for a batch of org units.  Useful for pre-caching
# setting values across a wide variety of org units without having to
# make a lookup call for every org unit.
# First checks to see if a value exists in the cache.
# For all non-cached values, looks up in DB, then caches the value.
sub precache_batch_ou_settings {
    my ($self, $org_ids, $setting, $e) = @_;

    $e ||= $self->{editor};
    my $c = $self->{ou_setting_cache};

    my @orgs;
    for my $org_id (@$org_ids) {
        next if exists $c->{$org_id}->{$setting};
        push (@orgs, $org_id);
    }

    return unless @orgs; # value aready cached for all requested orgs.

    my %settings = 
        $U->ou_ancestor_setting_batch_by_org_insecure(\@orgs, $setting, $e);

    for my $org_id (keys %settings) {
        $c->{$org_id}->{$setting} = $settings{$org_id}->{value};
    }
}

# Get the list of statuses able to target a hold, i.e. allowed for the
# current_copy.  Default to 0 and 7 if there ia a failure.
sub get_targetable_statuses {
    my $self = shift;
    unless (ref($self->{tagetable_statuses}) eq 'ARRAY' && @{$self->{targetable_statuses}}) {
        my $e = $self->{editor};
        $self->{targetable_statuses} = $e->search_config_copy_status({holdable => 't', is_available => 't'},
                                                                     {idlist => 1});
        unless (ref($self->{targetable_statuses}) eq 'ARRAY' && @{$self->{targetable_statuses}}) {
            $self->{targetable_statuses} = [0,7];
        }
    }
    return $self->{targetable_statuses};
}

# -----------------------------------------------------------------------
# Knows how to target a single hold.
# -----------------------------------------------------------------------
package OpenILS::Utils::HoldTargeter::Single;
use strict;
use warnings;
use DateTime;
use OpenSRF::AppSession;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Const qw/:const/;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

sub new {
    my ($class, %args) = @_;
    my $self = {
        %args,
        editor => new_editor(),
        error => 0,
        success => 0
    };
    return bless($self, $class);
}

# Parent targeter object.
sub parent {
    my ($self, $parent) = @_;
    $self->{parent} = $parent if $parent;
    return $self->{parent};
}

sub hold_id {
    my ($self, $hold_id) = @_;
    $self->{hold_id} = $hold_id if $hold_id;
    return $self->{hold_id};
}

sub hold {
    my ($self, $hold) = @_;
    $self->{hold} = $hold if $hold;
    return $self->{hold};
}

sub inside_hard_stall_interval {
    my ($self) = @_;
    if (defined $self->{inside_hard_stall_interval}) {
        $self->log_hold('already looked up hard stalling state: '.$self->{inside_hard_stall_interval});
        return $self->{inside_hard_stall_interval};
    }

    my $hard_stall_interval =
        $self->parent->get_ou_setting(
            $self->hold->pickup_lib, 'circ.pickup_hold_stalling.hard', $self->editor) || '0 seconds';

    $self->log_hold('hard stalling interval '.$hard_stall_interval);

    my $hold_request_time = $dt_parser->parse_datetime(clean_ISO8601($self->hold->request_time));
    my $hard_stall_time = $hold_request_time->clone->add(
        seconds => OpenILS::Utils::DateTime->interval_to_seconds($hard_stall_interval)
    );

    if (DateTime->compare($hard_stall_time, DateTime->now(time_zone => 'local')) > 0) {
        $self->{inside_hard_stall_interval} = 1
    } else {
        $self->{inside_hard_stall_interval} = 0
    }

    $self->log_hold('hard stalling state: '.$self->{inside_hard_stall_interval});
    return $self->{inside_hard_stall_interval};
}

# Debug message
sub message {
    my ($self, $message) = @_;
    $self->{message} = $message if $message;
    return $self->{message} || '';
}

# True if the hold was successfully targeted.
sub success {
    my ($self, $success) = @_;
    $self->{success} = $success if defined $success;
    return $self->{success};
}

# True if targeting exited early on an unrecoverable error.
sub error {
    my ($self, $error) = @_;
    $self->{error} = $error if defined $error;
    return $self->{error};
}

sub editor {
    my $self = shift;
    return $self->{editor};
}

sub result {
    my $self = shift;

    return {
        hold    => $self->hold_id,
        error   => $self->error,
        success => $self->success,
        message => $self->message,
        target  => $self->hold ? $self->hold->current_copy : undef,
        old_target => $self->{previous_copy_id},
        found_copy => $self->{found_copy},
        eligible_copies => $self->{eligible_copy_count}
    };
}

# List of potential copies in the form of slim hashes.  This list
# evolves as copies are filtered as they are deemed non-targetable.
sub copies {
    my ($self, $copies) = @_;
    $self->{copies} = $copies if $copies;
    return $self->{copies};
}

# Final set of potential copies, including those that may not be
# currently targetable, that may be eligible for recall processing.
sub recall_copies {
    my ($self, $recall_copies) = @_;
    $self->{recall_copies} = $recall_copies if $recall_copies;
    return $self->{recall_copies};
}

sub in_use_copies {
    my ($self, $in_use_copies) = @_;
    $self->{in_use_copies} = $in_use_copies if $in_use_copies;
    return $self->{in_use_copies};
}

# Maps copy ID's to their hold proximity
sub copy_prox_map {
    my ($self, $copy_prox_map) = @_;
    $self->{copy_prox_map} = $copy_prox_map if $copy_prox_map;
    return $self->{copy_prox_map};
}

sub log_hold {
    my ($self, $msg, $err) = @_;
    my $level = $err ? 'error' : 'info';
    $logger->$level("targeter: [hold ".$self->hold_id."] $msg");
}

# Captures the exit message, rolls back the cstore transaction/connection,
# and returns false.
# is_error : log the final message and editor event at ERR level.
sub exit_targeter {
    my ($self, $msg, $is_error) = @_;

    $self->message($msg);
    my $log = "exiting => $msg";

    if ($is_error) {
        # On error, roll back and capture the last editor event for logging.

        my $evt = $self->editor->die_event;
        $log .= " [".$evt->{textcode}."]" if $evt;

        $self->error(1);
        $self->log_hold($log, 1);

    } else {
        # Attempt a rollback and disconnect when each hold exits
        # to avoid the possibility of leaving cstore's pinned.
        # Note: ->rollback is a no-op when a ->commit has already occured.

        $self->editor->rollback;
        $self->log_hold($log);
    }

    return 0;
}

# Cancel expired holds and kick off the A/T no-target event.  Returns
# true (i.e. keep going) if the hold is not expired.  Returns false if
# the hold is canceled or a non-recoverable error occcurred.
sub handle_expired_hold {
    my $self = shift;
    my $hold = $self->hold;

    return 1 unless $hold->expire_time;

    my $ex_time =
        $dt_parser->parse_datetime(clean_ISO8601($hold->expire_time));
    return 1 unless 
        DateTime->compare($ex_time, DateTime->now(time_zone => 'local')) < 0;

    # Hold is expired --

    $hold->cancel_time('now');
    $hold->cancel_cause(1); # == un-targeted expiration

    $self->editor->update_action_hold_request($hold)
        or return $self->exit_targeter("Error canceling hold", 1);

    $self->editor->commit;

    # Fire the A/T handler, but don't wait for a response.
    OpenSRF::AppSession->create('open-ils.trigger')->request(
        'open-ils.trigger.event.autocreate',
        'hold_request.cancel.expire_no_target',
        $hold, $hold->pickup_lib
    );

    return $self->exit_targeter("Hold is expired");
}

# Find potential copies for hold mapping and targeting.
sub get_hold_copies {
    my $self = shift;
    my $e = $self->editor;
    my $hold = $self->hold;

    my $hold_target = $hold->target;
    my $hold_type   = $hold->hold_type;
    my $org_unit    = $hold->selection_ou;
    my $org_depth   = $hold->selection_depth || 0;

    my $query = {
        select => {
            acp => ['id', 'status', 'circ_lib'],
            ahr => ['current_copy']
        },
        from => {
            acp => {
                # Tag copies that are in use by other holds so we don't
                # try to target them for our hold.
                ahr => {
                    type => 'left',
                    fkey => 'id', # acp.id
                    field => 'current_copy',
                    filter => {
                        fulfillment_time => undef,
                        cancel_time => undef,
                        id => {'!=' => $self->hold_id}
                    }
                }
            }
        },
        where => {
            '+acp' => {
                deleted => 'f',
                circ_lib => {
                    in => {
                        select => {
                            aou => [{
                                transform => 'actor.org_unit_descendants',
                                column => 'id',
                                result_field => 'id',
                                params => [$org_depth]
                            }],
                            },
                        from => 'aou',
                        where => {id => $org_unit}
                    }
                }
            }
        }
    };

    unless ($hold_type eq 'R' || $hold_type eq 'F') {
        # Add the holdability filters to the copy query, unless
        # we're processing a Recall or Force hold, which bypass most
        # holdability checks.

        $query->{from}->{acp}->{acpl} = {
            field => 'id',
            filter => {holdable => 't', deleted => 'f'},
            fkey => 'location'
        };

        $query->{from}->{acp}->{ccs} = {
            field => 'id',
            filter => {holdable => 't'},
            fkey => 'status'
        };

        $query->{where}->{'+acp'}->{holdable} = 't';
        $query->{where}->{'+acp'}->{mint_condition} = 't'
            if $U->is_true($hold->mint_condition);
    }

    unless ($hold_type eq 'C' || $hold_type eq 'I' || $hold_type eq 'P') {
        # For volume and higher level holds, avoid targeting copies that
        # act as instances of monograph parts.
        $query->{from}->{acp}->{acpm} = {
            type => 'left',
            field => 'target_copy',
            fkey => 'id'
        };

        $query->{where}->{'+acpm'}->{id} = undef;
    }

    if ($hold_type eq 'C' || $hold_type eq 'R' || $hold_type eq 'F') {

        $query->{where}->{'+acp'}->{id} = $hold_target;

    } elsif ($hold_type eq 'V') {

        $query->{where}->{'+acp'}->{call_number} = $hold_target;

    } elsif ($hold_type eq 'P') {

        $query->{from}->{acp}->{acpm} = {
            field  => 'target_copy',
            fkey   => 'id',
            filter => {part => $hold_target},
        };

    } elsif ($hold_type eq 'I') {

        $query->{from}->{acp}->{sitem} = {
            field  => 'unit',
            fkey   => 'id',
            filter => {issuance => $hold_target},
        };

    } elsif ($hold_type eq 'T') {

        $query->{from}->{acp}->{acn} = {
            field  => 'id',
            fkey   => 'call_number',
            'join' => {
                bre => {
                    field  => 'id',
                    filter => {id => $hold_target},
                    fkey   => 'record'
                }
            }
        };

    } else { # Metarecord hold

        $query->{from}->{acp}->{acn} = {
            field => 'id',
            fkey  => 'call_number',
            join  => {
                bre => {
                    field => 'id',
                    fkey  => 'record',
                    join  => {
                        mmrsm => {
                            field  => 'source',
                            fkey   => 'id',
                            filter => {metarecord => $hold_target},
                        }
                    }
                }
            }
        };

        if ($hold->holdable_formats) {
            # Compile the JSON-encoded metarecord holdable formats
            # to an Intarray query_int string.
            my $query_int = $e->json_query({
                from => [
                    'metabib.compile_composite_attr',
                    $hold->holdable_formats
                ]
            })->[0];
            # TODO: ^- any way to add this as a filter in the main query?

            if ($query_int) {
                # Only pull potential copies from records that satisfy
                # the holdable formats query.
                my $qint = $query_int->{'metabib.compile_composite_attr'};
                $query->{from}->{acp}->{acn}->{join}->{bre}->{join}->{mravl} = {
                    field  => 'source',
                    fkey   => 'id',
                    filter => {vlist => {'@@' => $qint}}
                }
            }
        }
    }

    my $copies = $e->json_query($query);
    $self->{eligible_copy_count} = scalar(@$copies);

    $self->log_hold($self->{eligible_copy_count}." potential copies");

    # Let the caller know we encountered the copy they were interested in.
    $self->{found_copy} = 1 if $self->{find_copy}
        && grep {$_->{id} eq $self->{find_copy}} @$copies;

    $self->copies($copies);

    return 1;
}

# Delete and rebuild copy maps
sub update_copy_maps {
    my $self = shift;
    my $e = $self->editor;

    my $resp = $e->json_query({from => [
        'action.hold_request_regen_copy_maps',
        $self->hold_id,
        '{' . join(',', map {$_->{id}} @{$self->copies}) . '}'
    ]});

    # The above call can fail if another process is updating
    # copy maps for this hold at the same time.
    return 1 if $resp && @$resp;

    return $self->exit_targeter("Error creating hold copy maps", 1);
}

# Hopeless Date logic based on copy map
sub handle_hopeless_date {
    my ($self) = @_;
    my $e = $self->editor;
    my $hold = $self->hold;
    my $need_update = 0;

    # If copy map is empty and hopeless date is not already set,
    # then set it. Otherwise, let's check the items for Hopeless
    # Prone statuses.  If all are hopeless then set the hopeless
    # date if needed.  If at least one is not hopeless, then
    # clear the the hopeless date if not already unset.

    if (scalar(@{$self->copies}) == 0) {
        $logger->debug('Hopeless Holds logic (hold id ' . $hold->id . '): no copies');
        if (!$hold->hopeless_date) {
            $logger->debug('Hopeless Holds logic (hold id ' . $hold->id . '): setting hopeless_date');
            $hold->hopeless_date('now');
            $need_update = 1;
        }
    } else {
        my $all_hopeless = 1;
        foreach my $copy_hash (@{$self->copies}) {
            if (!$self->parent->{hopeless_prone_status_ids}->{$copy_hash->{status}}) {
                $all_hopeless = 0;
            }
        }
        if ($all_hopeless) {
            $logger->debug('Hopeless Holds logic (hold id ' . $hold->id . '): all copies have hopeless prone status');
            if (!$hold->hopeless_date) {
                $logger->debug('Hopeless Holds logic (hold id ' . $hold->id . '): setting hopeless_date');
                $hold->hopeless_date('now');
                $need_update = 1;
            }
        } else {
            $logger->debug('Hopeless Holds logic (hold id ' . $hold->id . '): at least one copy without a hopeless prone status');
            if ($hold->hopeless_date) {
                $logger->debug('Hopeless Holds logic (hold id ' . $hold->id . '): clearing hopeless_date');
                $hold->clear_hopeless_date;
                $need_update = 1;
            }
        }
    }

    if ($need_update) {
        $logger->debug('Hopeless Holds logic (hold id ' . $hold->id . '): attempting update');
        $e->update_action_hold_request($hold)
            or return $self->exit_targeter(
                "Error updating Hopeless Date for hold request", 1);
        # FIXME: sanity-check, will a commit happen further down the line for all use cases?
    }
}

# unique set of circ lib IDs for all in-progress copy blobs.
sub get_copy_circ_libs {
    my $self = shift;
    my %orgs = map {$_->{circ_lib} => 1} @{$self->copies};
    return [keys %orgs];
}


# Returns a map of proximity values to arrays of copy hashes.
# The copy hash arrays are weighted consistent with the org unit hold
# target weight, meaning that a given copy may appear more than once
# in its proximity list.
sub compile_weighted_proximity_map {
    my $self = shift;

    my %copy_reset_map = ();
    my %copy_timeout_map = ();
    eval {
        my $pt_interval =
        $self->parent->get_ou_setting(
            $self->hold->pickup_lib,
            'circ.hold_retarget_previous_targets_interval',
            $self->editor
        ) || 0;
        if(int($pt_interval)) {
            my $reset_cutoff_time = DateTime->now(time_zone => 'local')
                ->subtract(days => $pt_interval);

            # Collect reset reason info and previous copies.
            # for this hold within the last time interval
            my $reset_entries = $self->editor->json_query({
                select => {ahrrre => ['reset_reason','reset_time','previous_copy']},
                from => 'ahrrre',
                where => {
                    hold => $self->hold_id,
                    previous_copy => {'!=' => undef},
                    reset_time => {'>=' => $reset_cutoff_time->strftime('%F %T%z')},
                    reset_reason => [OILS_HOLD_TIMED_OUT, OILS_HOLD_MANUAL_RESET]
                }
            });

            # count how many times each copy
            # was reset or timed out
            for(@$reset_entries) {
                my $pc = $_->{previous_copy};
                my $rr = $_->{reset_reason};
                if($rr == OILS_HOLD_MANUAL_RESET) {
                    $copy_reset_map{$pc} = 0 if !$copy_reset_map{$pc};
                    $copy_reset_map{$pc} += 1;
                }
                elsif($rr == OILS_HOLD_TIMED_OUT) {
                    $copy_timeout_map{$pc} += 1;
                }
            }
        }
    };

    # Collect copy proximity info (generated via DB trigger)
    # from our newly create copy maps.
    my $hold_copy_maps = $self->editor->json_query({
        select => {ahcm => ['target_copy', 'proximity']},
        from => 'ahcm',
        where => {hold => $self->hold_id}
    });

    my %copy_prox_map =
        map {$_->{target_copy} => $_->{proximity}} @$hold_copy_maps;

    # calculate the maximum proximity to make adjustments
    my $max_prox = 0;
    foreach(@$hold_copy_maps) {
        $max_prox = $_->{proximity} > $max_prox ? $_->{proximity} : $max_prox;
    }

    # Pre-fetch the org setting value for all circ libs so that
    # later calls can reference the cached value.
    $self->parent->precache_batch_ou_settings($self->get_copy_circ_libs, 
        'circ.holds.org_unit_target_weight', $self->editor);

    my %prox_map;
    for my $copy_hash (@{$self->copies}) {
        my $copy_id = $copy_hash->{id};
        my $prox = $copy_prox_map{$copy_id};
        my $reset_count = $copy_reset_map{$copy_id} || 0;
        my $timeout_count = $copy_timeout_map{$copy_id} || 0;
        undef $copy_id;

        # make adjustments to proximity based on reset reason.
        # manual resets get +max_prox each time
        # this moves them to the end of the hold copy map.
        # timeout resets only add one level of proximity
        # so that copies can be inspected again later.
        $prox += ($reset_count * $max_prox) + $timeout_count;

        $copy_hash->{proximity} = $prox;
        $prox_map{$prox} ||= [];

        my $weight = $self->parent->get_ou_setting(
            $copy_hash->{circ_lib},
            'circ.holds.org_unit_target_weight', $self->editor) || 1;

        # Each copy is added to the list once per target weight.
        push(@{$prox_map{$prox}}, $copy_hash) foreach (1 .. $weight);
    }

    # We need to grab the proximity for copies targeted by other holds
    # that belong to this pickup lib for hard-stalling tests later. We'll
    # just grab them all in case it's useful later.
    for my $copy_hash (@{$self->in_use_copies}) {
        my $prox = $copy_prox_map{$copy_hash->{id}};
        $copy_hash->{proximity} = $prox;
    }

    # We also need the proximity for the previous target.
    if ($self->{valid_previous_copy}) {
        my $prox = $copy_prox_map{$self->{valid_previous_copy}->{id}};
        $self->{valid_previous_copy}->{proximity} = $prox;
    }

    return $self->{weighted_prox_map} = \%prox_map;
}

# Returns true if filtering completed without error, false otherwise.
sub filter_closed_date_copies {
    my $self = shift;

    # Pre-fetch the org setting value for all represented circ libs that
    # are closed, minuse the pickup_lib, since it has its own special setting.
    my $circ_libs = $self->get_copy_circ_libs;
    $circ_libs = [
        grep {
            $self->parent->{closed_orgs}->{$_} && 
            $_ ne $self->hold->pickup_lib
        } @$circ_libs
    ];

    # If none of the represented circ libs are closed, we're done here.
    return 1 unless @$circ_libs;

    $self->parent->precache_batch_ou_settings(
        $circ_libs, 'circ.holds.target_when_closed', $self->editor);

    my @filtered_copies;
    for my $copy_hash (@{$self->copies}) {
        my $clib = $copy_hash->{circ_lib};

        if ($self->parent->{closed_orgs}->{$clib}) {
            # Org unit is currently closed.  See if it matters.

            my $ous = $self->hold->pickup_lib eq $clib ?
                'circ.holds.target_when_closed_if_at_pickup_lib' :
                'circ.holds.target_when_closed';

            unless (
                $self->parent->get_ou_setting($clib, $ous, $self->editor)) {
                # Targeting not allowed at this circ lib when its closed

                $self->log_hold("skipping copy ".
                    $copy_hash->{id}." at closed org $clib");

                next;
            }

        }

        push(@filtered_copies, $copy_hash);
    }

    # Update our in-progress list of copies to reflect the filtered set.
    $self->copies(\@filtered_copies);

    return 1;
}

# Limit the set of potential copies to those that are
# in a targetable status.
# Returns true if filtering completes without error, false otherwise.
sub filter_copies_by_status {
    my $self = shift;

    # Track checked out copies for later recall
    $self->recall_copies([grep {$_->{status} == 1} @{$self->copies}]);

    my $targetable_statuses = $self->parent->get_targetable_statuses();
    $self->copies([
        grep {
            my $c = $_;
            grep {$c->{status} == $_} @{$targetable_statuses}
        } @{$self->copies}
    ]);

    return 1;
}

# Remove copies that are currently targeted by other holds.
# Returns true if filtering completes without error, false otherwise.
sub filter_copies_in_use {
    my $self = shift;

    # Copies that are targeted, but could contribute to pickup lib
    # hard (foreign) stalling.  These are Available-status copies.
    $self->in_use_copies([grep {$_->{current_copy}} @{$self->copies}]);

    # A copy with a 'current_copy' value means it's in use by another hold.
    $self->copies([
        grep {!$_->{current_copy}} @{$self->copies}
    ]);

    return 1;
}

# Returns true if inspection completed without error, false otherwise.
sub inspect_previous_target {
    my $self = shift;
    my $hold = $self->hold;
    my @copies = @{$self->copies};

    # no previous target
    return 1 unless my $prev_id = $hold->current_copy;

    $self->{previous_copy_id} = $prev_id;

    # See if the previous copy is in our list of valid copies.
    my ($prev) = grep {$_->{id} eq $prev_id} @copies;

    # exit if previous target is no longer valid.
    return 1 unless $prev;

    my $soft_retarget = 0;

    if ($self->parent->{soft_retarget_time}) {
        # A hold is soft-retarget-able if its prev_check_time is
        # later then the retarget_time, i.e. it sits between the
        # soft_retarget_time and the retarget_time.

        my $pct = $dt_parser->parse_datetime(
            clean_ISO8601($hold->prev_check_time));

        $soft_retarget =
            DateTime->compare($pct, $self->parent->{retarget_time}) > 0;
    }

    if ($soft_retarget) {

        # In soft-retarget mode, if the existing copy is still a valid
        # target for the hold, exit early.
        if ($self->copy_is_permitted($prev)) {

            # Commit to persist the updated action.hold_copy_map's
            $self->editor->commit;

            return $self->exit_targeter(
                "Exiting early on soft-retarget with viable copy = $prev_id");

        } else {
            $self->log_hold("soft retarget failed because copy $prev_id is ".
                "no longer targetable for this hold.  Retargeting...");
        }

    } else {

        # Previous copy /may/ be targetable.  Keep it around for later
        # in case we need to confirm its viability and re-use it.
        $self->{valid_previous_copy} = $prev;
    }

    # Remove the previous copy from the working set of potential copies.
    # It will be revisited later if needed.
    $self->copies([grep {$_->{id} ne $prev_id} @copies]);

    return 1;
}

# Returns true if we have at least one potential copy remaining, thus
# targeting should continue.  Otherwise, the hold is updated to reflect
# that there is no target and returns false to stop targeting.
sub handle_no_copies {
    my ($self, %args) = @_;

    if (!$args{force}) {
        # If 'force' is set, the caller is saying that all copies have
        # failed.  Otherwise, see if we have any copies left to inspect.
        return 1 if @{$self->copies} || $self->{valid_previous_copy};
    }

    # At this point, all copies have been inspected and none
    # have yielded a targetable item.

    if ($args{process_recalls}) {
        # See if we have any copies/circs to recall.
        return unless $self->process_recalls;
    }

    my $hold = $self->hold;
    $hold->clear_current_copy;
    $hold->prev_check_time('now');

    $self->editor->update_action_hold_request($hold)
        or return $self->exit_targeter("Error updating hold request", 1);

    $self->editor->commit;
    return $self->exit_targeter("Hold has no targetable copies");
}

# Force and recall holds bypass validity tests.  Returns the first
# (and presumably only) copy in our list of valid copies when a
# F or R hold is encountered.  Returns undef otherwise.
sub attempt_force_recall_target {
    my $self = shift;
    return $self->copies->[0] if
        $self->hold->hold_type eq 'R' || $self->hold->hold_type eq 'F';
    return undef;
}

sub attempt_to_find_copy {
    my $self = shift;

    $self->log_hold("attempting to find a copy normally");

    my $max_loops = $self->parent->get_ou_setting(
        $self->hold->pickup_lib,
        'circ.holds.max_org_unit_target_loops',
        $self->editor
    );

    return $self->target_by_org_loops($max_loops) if $max_loops;

    # When not using target loops, targeting is based solely on
    # proximity and org unit target weight.
    $self->compile_weighted_proximity_map;

    return $self->find_nearest_copy;
}

# Returns 2 arrays.  The first is a list of copies whose circ lib's
# unfulfilled target count matches the provided $iter value.  The 
# second list is all other copies, returned for convenience.
sub get_copies_at_loop_iter {
    my ($self, $targeted_libs, $iter) = @_;

    my @iter_copies; # copies to try now.
    my @remaining_copies; # copies to try later

    for my $copy (@{$self->copies}) {
        my $match = 0;

        if ($iter == 0) {
            # Start with copies at circ libs that have never been targeted.
            $match = 1 unless grep {
                $copy->{circ_lib} eq $_->{circ_lib}} @$targeted_libs;

        } else {
            # Find copies at branches whose target count
            # matches the current (non-zero) loop depth.

            $match = 1 if grep {
                $_->{count} eq $iter &&
                $_->{circ_lib} eq $copy->{circ_lib}
            } @$targeted_libs;
        }

        if ($match) {
            push(@iter_copies, $copy);
        } else {
            push(@remaining_copies, $copy);
        }
    }

    $self->log_hold(
        sprintf("%d potential copies at max-loops iteration level $iter. ".
            "%d remain to be tested at a higher loop iteration level.",
            scalar(@iter_copies), 
            scalar(@remaining_copies)
        )
    );

    return (\@iter_copies, \@remaining_copies);
}

# Find libs whose unfulfilled target count is less than the maximum
# configured loop count.  Target copies in order of their circ_lib's
# target count (starting at 0) and moving up.  Copies within each
# loop count group are weighted based on configured hold weight.  If
# no copies in a given group are targetable, move up to the next
# unfulfilled target level.  Keep doing this until all potential
# copies have been tried or max targets loops is exceeded.
# Returns a targetable copy if one is found, undef otherwise.
sub target_by_org_loops {
    my ($self, $max_loops) = @_;

    my $targeted_libs = $self->editor->json_query({
        select => {aufhl => ['circ_lib', 'count']},
        from => 'aufhl',
        where => {hold => $self->hold_id},
        order_by => [{class => 'aufhl', field => 'count'}]
    });

    my $max_tried = 0; # Highest per-lib target attempts.
    foreach (@$targeted_libs) {
        $max_tried = $_->{count} if $_->{count} > $max_tried;
    }

    $self->log_hold("Max lib attempts is $max_tried. ".
        scalar(@$targeted_libs)." libs have been targeted at least once.");

    # $loop_iter represents per-lib target attemtps already made.
    # When loop_iter equals max loops, all libs with targetable copies
    # have been targeted the maximum number of times.  loop_iter starts
    # at 0 to pick up libs that have never been targeted.
    my $loop_iter = -1;
    while (++$loop_iter < $max_loops) {

        # Ran out of copies to try before exceeding max target loops.
        # Nothing else to do here.
        return undef unless @{$self->copies};

        my ($iter_copies, $remaining_copies) = 
            $self->get_copies_at_loop_iter($targeted_libs, $loop_iter);

        next unless @$iter_copies;

        $self->copies($iter_copies);

        # Update the proximity map to only include the copies
        # from this loop-depth iteration.
        $self->compile_weighted_proximity_map;

        my $copy = $self->find_nearest_copy;
        return $copy if $copy; # found one!

        # No targetable copy at the current target loop.
        # Update our current copy set to the not-yet-tested copies.
        $self->copies($remaining_copies);
    }

    # Avoid canceling the hold with exceeds-loops unless at least one
    # lib has been targeted max_loops times.  Otherwise, the hold goes
    # back to waiting for another copy (or retargets its current copy).
    return undef if $max_tried < $max_loops;

    # At least one lib has been targeted max-loops times and zero 
    # other copies are targetable.  All options have been exhausted.
    return $self->handle_exceeds_target_loops;
}

# Cancel the hold, fire the no-target A/T event handler, and exit.
sub handle_exceeds_target_loops {
    my $self = shift;
    my $e = $self->editor;
    my $hold = $self->hold;

    $hold->cancel_time('now');
    $hold->cancel_cause(1); # = un-targeted expiration

    $e->update_action_hold_request($hold)
        or return $self->exit_targeter("Error updating hold request", 1);

    $e->commit;

    # Fire the A/T handler, but don't wait for a response.
    OpenSRF::AppSession->create('open-ils.trigger')->request(
        'open-ils.trigger.event.autocreate',
        'hold_request.cancel.expire_no_target',
        $hold, $hold->pickup_lib
    );

    return $self->exit_targeter("Hold exceeded max target loops");
}

# When all else fails, see if we can reuse the previously targeted copy.
sub attempt_prev_copy_retarget {
    my $self = shift;

    # earlier target logic can in some cases cancel the hold.
    return undef if $self->hold->cancel_time;

    my $prev_copy = $self->{valid_previous_copy};
    return undef unless $prev_copy;

    $self->log_hold("attempting to re-target previously ".
        "targeted copy for hold ".$self->hold_id);

    if ($self->copy_is_permitted($prev_copy)) {
        $self->log_hold("retargeting the previously ".
            "targeted copy [".$prev_copy->{id}."]" );
        return $prev_copy;
    }

    return undef;
}

# Returns the closest copy by proximity that is a confirmed valid
# targetable copy.
sub find_nearest_copy {
    my $self = shift;
    my %prox_map = %{$self->{weighted_prox_map}};
    my $hold = $self->hold;
    my %seen;

    # See if there are in-use (targeted) copies "here".
    my $have_local_copies = 0;
    if ($self->inside_hard_stall_interval) { # But only if we're inside the hard age.
        if (grep { $_->{proximity} <= 0 } @{$self->in_use_copies}) {
            $have_local_copies = 1;
        }
        $self->log_hold("inside hard stall interval and does ".
            ($have_local_copies ? "" : "not "). "have in-use local copies");
    }

    # Pick a copy at random from each tier of the proximity map,
    # starting at the lowest proximity and working up, until a
    # copy is found that is suitable for targeting.
    my $no_copies = 1;
    for my $prox (sort {$a <=> $b} keys %prox_map) {
        my @copies = @{$prox_map{$prox}};
        next unless @copies;

        $no_copies = 0;
        $have_local_copies = 1 if ($prox <= 0);

        $self->log_hold("inside hard stall interval and does ".
            ($have_local_copies ? "" : "not "). "have testable local copies")
                if ($self->inside_hard_stall_interval && $prox > 0);

        if ($have_local_copies and $self->inside_hard_stall_interval) {
            # Unset valid_previous_copy if it's not local and we have local copies now
            $self->{valid_previous_copy} = undef if (
                $self->{valid_previous_copy}
                and $self->{valid_previous_copy}->{proximity} > 0
            );
            last if ($prox > 0); # No point in looking further "out".
        }

        my $rand = int(rand(scalar(@copies)));

        while (my ($c) = splice(@copies, $rand, 1)) {
            $rand = int(rand(scalar(@copies)));
            next if $seen{$c->{id}};

            return $c if $self->copy_is_permitted($c);
            $seen{$c->{id}} = 1;

            last unless(@copies);
        }
    }

    if ($no_copies and $have_local_copies and $self->inside_hard_stall_interval) {
        # Unset valid_previous_copy if it's not local and we have local copies now
        $self->{valid_previous_copy} = undef if (
            $self->{valid_previous_copy}
            and $self->{valid_previous_copy}->{proximity} > 0
        );
    }

    return undef;
}

# Returns true if the provided copy passes the hold permit test for our
# hold and can be used for targeting.
# When a copy fails the test, it is removed from $self->copies.
sub copy_is_permitted {
    my ($self, $copy) = @_;
    return 0 unless $copy;

    my $resp = $self->editor->json_query({
        from => [
            'action.hold_retarget_permit_test',
            $self->hold->pickup_lib,
            $self->hold->request_lib,
            $copy->{id},
            $self->hold->usr,
            $self->hold->requestor
        ]
    });

    return 1 if $U->is_true($resp->[0]->{success});

    # Copy is confirmed non-viable.
    # Remove it from our potentials list.
    $self->copies([
        grep {$_->{id} ne $copy->{id}} @{$self->copies}
    ]);

    return 0;
}

# Sets hold.current_copy to the provided copy.
sub apply_copy_target {
    my ($self, $copy) = @_;
    my $e = $self->editor;
    my $hold = $self->hold;

    $hold->current_copy($copy->{id});
    $hold->prev_check_time('now');

    $e->update_action_hold_request($hold)
        or return $self->exit_targeter("Error updating hold request", 1);

    $e->commit;
    $self->{success} = 1;
    return $self->exit_targeter("successfully targeted copy ".$copy->{id});
}

# Creates a new row in action.unfulfilled_hold_list for our hold.
# Returns 1 if all is OK, false on error.
sub log_unfulfilled_hold {
    my $self = shift;
    return 1 unless my $prev_id = $self->{previous_copy_id};
    my $e = $self->editor;

    $self->log_hold(
        "hold was not fulfilled by previous targeted copy $prev_id");

    my $circ_lib;
    if ($self->{valid_previous_copy}) {
        $circ_lib = $self->{valid_previous_copy}->{circ_lib};

    } else {
        # We don't have a handle on the previous copy to get its
        # circ lib.  Fetch it.
        $circ_lib = $e->retrieve_asset_copy($prev_id)->circ_lib;
    }

    my $unful = Fieldmapper::action::unfulfilled_hold_list->new;
    $unful->hold($self->hold_id);
    $unful->circ_lib($circ_lib);
    $unful->current_copy($prev_id);

    $e->create_action_unfulfilled_hold_list($unful) or
        return $self->exit_targeter("Error creating unfulfilled_hold_list", 1);

    return 1;
}

sub process_recalls {
    my $self = shift;
    my $e = $self->editor;

    my $pu_lib = $self->hold->pickup_lib;

    my $threshold =
        $self->parent->get_ou_setting(
            $pu_lib, 'circ.holds.recall_threshold', $self->editor)
        or return 1;

    my $interval =
        $self->parent->get_ou_setting(
            $pu_lib, 'circ.holds.recall_return_interval', $self->editor)
        or return 1;

    # Give me the ID of every checked out copy living at the hold
    # pickup library.
    my @copy_ids = map {$_->{id}}
        grep {$_->{circ_lib} eq $pu_lib} @{$self->recall_copies};

    return 1 unless @copy_ids;

    my $circ = $e->search_action_circulation([
        {   target_copy => \@copy_ids,
            checkin_time => undef,
            duration => {'>' => $threshold}
        }, {
            order_by => [{ class => 'circ', field => 'due_date'}],
            limit => 1
        }
    ])->[0];

    return unless $circ;

    $self->log_hold("recalling circ ".$circ->id);

    my $old_due_date = DateTime::Format::ISO8601->parse_datetime(clean_ISO8601($circ->due_date));

    # Give the user a new due date of either a full recall threshold,
    # or the return interval, whichever is further in the future.
    my $threshold_date = DateTime::Format::ISO8601
        ->parse_datetime(clean_ISO8601($circ->xact_start))
        ->add(seconds => interval_to_seconds($threshold));

    my $return_date = DateTime->now(time_zone => 'local')->add(
        seconds => interval_to_seconds($interval));

    if (DateTime->compare($threshold_date, $return_date) == 1) {
        # extend $return_date to threshold
        $return_date = $threshold_date;
    }
    # But don't go past the original due date
    # (the threshold should not be past the due date, but manual edits can
    # cause it to be)
    if (DateTime->compare($return_date, $old_due_date) == 1) {
        # truncate $return_date to due date
        $return_date = $old_due_date;
    }

    my %update_fields = (
        due_date => $return_date->iso8601(),
        renewal_remaining => 0,
    );

    my $fine_rules =
        $self->parent->get_ou_setting(
            $pu_lib, 'circ.holds.recall_fine_rules', $self->editor);

    # If the OU hasn't defined new fine rules for recalls, keep them
    # as they were
    if ($fine_rules) {
        $self->log_hold("applying recall fine rules: $fine_rules");
        my $rules = OpenSRF::Utils::JSON->JSON2perl($fine_rules);
        $update_fields{recurring_fine} = $rules->[0];
        $update_fields{fine_interval} = $rules->[1];
        $update_fields{max_fine} = $rules->[2];
    }

    # Copy updated fields into circ object.
    $circ->$_($update_fields{$_}) for keys %update_fields;

    $e->update_action_circulation($circ)
        or return $self->exit_targeter(
            "Error updating circulation object in process_recalls", 1);

    # Create trigger event for notifying current user
    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    $ses->request('open-ils.trigger.event.autocreate',
        'circ.recall.target', $circ, $circ->circ_lib);

    return 1;
}

# Target a single hold request
sub target {
    my ($self, $hold_id) = @_;

    my $e = $self->editor;
    $self->hold_id($hold_id);

    $self->log_hold("processing...");

    $e->xact_begin;

    my $hold = $e->retrieve_action_hold_request($hold_id)
        or return $self->exit_targeter("No hold found", 1);

    return $self->exit_targeter("Hold is not eligible for targeting")
        if $hold->capture_time     ||
           $hold->cancel_time      ||
           $hold->fulfillment_time ||
           $U->is_true($hold->frozen);

    $self->hold($hold);

    return unless $self->handle_expired_hold;
    return unless $self->get_hold_copies;
    return unless $self->update_copy_maps;

    # Hopeless Date logic based on copy map

    $self->handle_hopeless_date;

    # Confirm that we have something to work on.  If we have no
    # copies at this point, there's also nothing to recall.
    return unless $self->handle_no_copies;

    # Trim the set of working copies down to those that are
    # currently targetable.
    return unless $self->filter_copies_by_status;
    return unless $self->filter_copies_in_use;
    return unless $self->filter_closed_date_copies;

    # Set aside the previously targeted copy for later use as needed.
    # Code may exit here in skip_viable mode if the existing
    # current_copy value is still viable.
    return unless $self->inspect_previous_target;

    # Log that the hold was not captured.
    return unless $self->log_unfulfilled_hold;

    # Confirm again we have something to work on.  If we have no
    # targetable copies now, there may be a copy that can be recalled.
    return unless $self->handle_no_copies(process_recalls => 1);

    # At this point, the working list of copies has been trimmed to
    # those that are currently targetable at a superficial level.  
    # (They are holdable and available).  Now the code steps through 
    # these copies in order of priority and pickup lib proximity to 
    # find a copy that is confirmed targetable by policy.

    my $copy = $self->attempt_force_recall_target ||
               $self->attempt_to_find_copy        ||
               $self->attempt_prev_copy_retarget;

    # See if one of the above attempt* calls canceled the hold as a side
    # effect of looking for a copy to target.
    return if $hold->cancel_time;

    return $self->apply_copy_target($copy) if $copy;

    # No targetable copy was found.  Fire the no-copy handler.
    $self->handle_no_copies(force => 1, process_recalls => 1);
}



