# ---------------------------------------------------------------
# Copyright (C) 2005  Georgia Public Library Service 
# Bill Erickson <highfalutin@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------


package OpenILS::Application::Circ::Holds;
use base qw/OpenILS::Application/;
use strict; use warnings;
use OpenILS::Application::AppUtils;
use DateTime;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::Perm;
use OpenILS::Event;
use OpenSRF::Utils;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Utils::PermitHold;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Const qw/:const/;
use OpenILS::Application::Circ::Transit;
use OpenILS::Application::Actor::Friends;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/:datetime/;
use Digest::MD5 qw(md5_hex);
use OpenSRF::Utils::Cache;
my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;

__PACKAGE__->register_method(
    method    => "test_and_create_hold_batch",
    api_name  => "open-ils.circ.holds.test_and_create.batch",
    stream => 1,
    signature => {
        desc => q/This is for batch creating a set of holds where every field is identical except for the targets./,
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Hash of named parameters.  Same as for open-ils.circ.title_hold.is_possible, though the pertinent target field is automatically populated based on the hold_type and the specified list of targets.', type => 'object'},
            { desc => 'Array of target ids', type => 'array' }
        ],
        return => {
            desc => 'Array of hold ID on success, -1 on missing arg, event (or ref to array of events) on error(s)',
        },
    }
);

__PACKAGE__->register_method(
    method    => "test_and_create_hold_batch",
    api_name  => "open-ils.circ.holds.test_and_create.batch.override",
    stream => 1,
    signature => {
        desc  => '@see open-ils.circ.holds.test_and_create.batch',
    }
);


sub test_and_create_hold_batch {
	my( $self, $conn, $auth, $params, $target_list, $oargs ) = @_;

	my $override = 1 if $self->api_name =~ /override/;
    $oargs = { all => 1 } unless defined $oargs;

	my $e = new_editor(authtoken=>$auth);
	return $e->die_event unless $e->checkauth;
    $$params{'requestor'} = $e->requestor->id;

    my $target_field;
    if ($$params{'hold_type'} eq 'T') { $target_field = 'titleid'; }
    elsif ($$params{'hold_type'} eq 'C') { $target_field = 'copy_id'; }
    elsif ($$params{'hold_type'} eq 'R') { $target_field = 'copy_id'; }
    elsif ($$params{'hold_type'} eq 'F') { $target_field = 'copy_id'; }
    elsif ($$params{'hold_type'} eq 'I') { $target_field = 'issuanceid'; }
    elsif ($$params{'hold_type'} eq 'V') { $target_field = 'volume_id'; }
    elsif ($$params{'hold_type'} eq 'M') { $target_field = 'mrid'; }
    elsif ($$params{'hold_type'} eq 'P') { $target_field = 'partid'; }
    else { return undef; }

    foreach (@$target_list) {
        $$params{$target_field} = $_;
        my $res;
        ($res) = $self->method_lookup(
            'open-ils.circ.title_hold.is_possible')->run($auth, $params, $override ? $oargs : {});
        if ($res->{'success'} == 1) {

            $params->{'depth'} = $res->{'depth'} if $res->{'depth'};

            my $ahr = construct_hold_request_object($params);
            my ($res2) = $self->method_lookup(
                $override
                ? 'open-ils.circ.holds.create.override'
                : 'open-ils.circ.holds.create'
            )->run($auth, $ahr, $oargs);
            $res2 = {
                'target' => $$params{$target_field},
                'result' => $res2
            };
            $conn->respond($res2);
        } else {
            $res = {
                'target' => $$params{$target_field},
                'result' => $res
            };
            $conn->respond($res);
        }
    }
    return undef;
}

sub construct_hold_request_object {
    my ($params) = @_;

    my $ahr = Fieldmapper::action::hold_request->new;
    $ahr->isnew('1');

    foreach my $field (keys %{ $params }) {
        if ($field eq 'depth') { $ahr->selection_depth($$params{$field}); }
        elsif ($field eq 'patronid') {
            $ahr->usr($$params{$field}); }
        elsif ($field eq 'titleid') { $ahr->target($$params{$field}); }
        elsif ($field eq 'copy_id') { $ahr->target($$params{$field}); }
        elsif ($field eq 'issuanceid') { $ahr->target($$params{$field}); }
        elsif ($field eq 'volume_id') { $ahr->target($$params{$field}); }
        elsif ($field eq 'mrid') { $ahr->target($$params{$field}); }
        elsif ($field eq 'partid') { $ahr->target($$params{$field}); }
        else {
            $ahr->$field($$params{$field});
        }
    }
    return $ahr;
}

__PACKAGE__->register_method(
    method    => "create_hold_batch",
    api_name  => "open-ils.circ.holds.create.batch",
    stream => 1,
    signature => {
        desc => q/@see open-ils.circ.holds.create.batch/,
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Array of hold objects', type => 'array' }
        ],
        return => {
            desc => 'Array of hold ID on success, -1 on missing arg, event (or ref to array of events) on error(s)',
        },
    }
);

__PACKAGE__->register_method(
    method    => "create_hold_batch",
    api_name  => "open-ils.circ.holds.create.override.batch",
    stream => 1,
    signature => {
        desc  => '@see open-ils.circ.holds.create.batch',
    }
);


sub create_hold_batch {
	my( $self, $conn, $auth, $hold_list, $oargs ) = @_;
    (my $method = $self->api_name) =~ s/\.batch//og;
    foreach (@$hold_list) {
        my ($res) = $self->method_lookup($method)->run($auth, $_, $oargs);
        $conn->respond($res);
    }
    return undef;
}


__PACKAGE__->register_method(
    method    => "create_hold",
    api_name  => "open-ils.circ.holds.create",
    signature => {
        desc => "Create a new hold for an item.  From a permissions perspective, " .
                "the login session is used as the 'requestor' of the hold.  "      . 
                "The hold recipient is determined by the 'usr' setting within the hold object. " .
                'First we verify the requestor has holds request permissions.  '         .
                'Then we verify that the recipient is allowed to make the given hold.  ' .
                'If not, we see if the requestor has "override" capabilities.  If not, ' .
                'a permission exception is returned.  If permissions allow, we cycle '   .
                'through the set of holds objects and create.  '                         .
                'If the recipient does not have permission to place multiple holds '     .
                'on a single title and said operation is attempted, a permission '       .
                'exception is returned',
        params => [
            { desc => 'Authentication token',               type => 'string' },
            { desc => 'Hold object for hold to be created',
                type => 'object', class => 'ahr' }
        ],
        return => {
            desc => 'New ahr ID on success, -1 on missing arg, event (or ref to array of events) on error(s)',
        },
    }
);

__PACKAGE__->register_method(
    method    => "create_hold",
    api_name  => "open-ils.circ.holds.create.override",
    notes     => '@see open-ils.circ.holds.create',
    signature => {
        desc  => "If the recipient is not allowed to receive the requested hold, " .
                 "call this method to attempt the override",
        params => [
            { desc => 'Authentication token',               type => 'string' },
            {
                desc => 'Hold object for hold to be created',
                type => 'object', class => 'ahr'
            }
        ],
        return => {
            desc => 'New hold (ahr) ID on success, -1 on missing arg, event (or ref to array of events) on error(s)',
        },
    }
);

sub create_hold {
	my( $self, $conn, $auth, $hold, $oargs ) = @_;
    return -1 unless $hold;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;

	my $override = 1 if $self->api_name =~ /override/;
    $oargs = { all => 1 } unless defined $oargs;

    my @events;

    my $requestor = $e->requestor;
    my $recipient = $requestor;

    if( $requestor->id ne $hold->usr ) {
        # Make sure the requestor is allowed to place holds for 
        # the recipient if they are not the same people
        $recipient = $e->retrieve_actor_user($hold->usr)  or return $e->die_event;
        $e->allowed('REQUEST_HOLDS', $recipient->home_ou) or return $e->die_event;
    }

    # If the related org setting tells us to, block if patron privs have expired
    my $expire_setting = $U->ou_ancestor_setting_value($recipient->home_ou, OILS_SETTING_BLOCK_HOLD_FOR_EXPIRED_PATRON);
    if ($expire_setting) {
        my $expire = DateTime::Format::ISO8601->new->parse_datetime(
            cleanse_ISO8601($recipient->expire_date));

        push( @events, OpenILS::Event->new(
            'PATRON_ACCOUNT_EXPIRED',
            "payload" => {"fail_part" => "actor.usr.privs_expired"}
            )) if( CORE::time > $expire->epoch ) ;
    }

    # Now make sure the recipient is allowed to receive the specified hold
    my $porg = $recipient->home_ou;
    my $rid  = $e->requestor->id;
    my $t    = $hold->hold_type;

    # See if a duplicate hold already exists
    my $sargs = {
        usr			=> $recipient->id, 
        hold_type	=> $t, 
        fulfillment_time => undef, 
        target		=> $hold->target,
        cancel_time	=> undef,
    };

    $sargs->{holdable_formats} = $hold->holdable_formats if $t eq 'M';
        
    my $existing = $e->search_action_hold_request($sargs); 
    push( @events, OpenILS::Event->new('HOLD_EXISTS')) if @$existing;

    my $checked_out = hold_item_is_checked_out($e, $recipient->id, $hold->hold_type, $hold->target);
    push( @events, OpenILS::Event->new('HOLD_ITEM_CHECKED_OUT')) if $checked_out;

    if ( $t eq OILS_HOLD_TYPE_METARECORD ) {
        return $e->die_event unless $e->allowed('MR_HOLDS',     $porg);
    } elsif ( $t eq OILS_HOLD_TYPE_TITLE ) {
        return $e->die_event unless $e->allowed('TITLE_HOLDS',  $porg);
    } elsif ( $t eq OILS_HOLD_TYPE_VOLUME ) {
        return $e->die_event unless $e->allowed('VOLUME_HOLDS', $porg);
    } elsif ( $t eq OILS_HOLD_TYPE_MONOPART ) {
        return $e->die_event unless $e->allowed('TITLE_HOLDS', $porg);
    } elsif ( $t eq OILS_HOLD_TYPE_ISSUANCE ) {
        return $e->die_event unless $e->allowed('ISSUANCE_HOLDS', $porg);
    } elsif ( $t eq OILS_HOLD_TYPE_COPY ) {
        return $e->die_event unless $e->allowed('COPY_HOLDS',   $porg);
    } elsif ( $t eq OILS_HOLD_TYPE_FORCE || $t eq OILS_HOLD_TYPE_RECALL ) {
		my $copy = $e->retrieve_asset_copy($hold->target)
			or return $e->die_event;
        if ( $t eq OILS_HOLD_TYPE_FORCE ) {
            return $e->die_event unless $e->allowed('COPY_HOLDS_FORCE',   $copy->circ_lib);
        } elsif ( $t eq OILS_HOLD_TYPE_RECALL ) {
            return $e->die_event unless $e->allowed('COPY_HOLDS_RECALL',   $copy->circ_lib);
        }
    }

    if( @events ) {
        if (!$override) {
            $e->rollback;
            return \@events;
        }
        for my $evt (@events) {
            next unless $evt;
            my $name = $evt->{textcode};
            if($oargs->{all} || grep { $_ eq $name } @{$oargs->{events}}) {
                return $e->die_event unless $e->allowed("$name.override", $porg);
            } else {
                $e->rollback;
                return \@events;
            }
        }
    }

        # Check for hold expiration in the past, and set it to empty string.
        $hold->expire_time(undef) if ($hold->expire_time && $U->datecmp($hold->expire_time) == -1);

    # set the configured expire time
    unless($hold->expire_time) {
        $hold->expire_time(calculate_expire_time($recipient->home_ou));
    }

    $hold->requestor($e->requestor->id); 
    $hold->request_lib($e->requestor->ws_ou);
    $hold->selection_ou($hold->pickup_lib) unless $hold->selection_ou;
    $hold = $e->create_action_hold_request($hold) or return $e->die_event;

	$e->commit;

	$conn->respond_complete($hold->id);

    $U->storagereq(
        'open-ils.storage.action.hold_request.copy_targeter', 
        undef, $hold->id ) unless $U->is_true($hold->frozen);

	return undef;
}

# makes sure that a user has permission to place the type of requested hold
# returns the Perm exception if not allowed, returns undef if all is well
sub _check_holds_perm {
	my($type, $user_id, $org_id) = @_;

	my $evt;
	if ($type eq "M") {
		$evt = $apputils->check_perms($user_id, $org_id, "MR_HOLDS"    );
	} elsif ($type eq "T") {
		$evt = $apputils->check_perms($user_id, $org_id, "TITLE_HOLDS" );
	} elsif($type eq "V") {
		$evt = $apputils->check_perms($user_id, $org_id, "VOLUME_HOLDS");
	} elsif($type eq "C") {
		$evt = $apputils->check_perms($user_id, $org_id, "COPY_HOLDS"  );
	}

    return $evt if $evt;
	return undef;
}

# tests if the given user is allowed to place holds on another's behalf
sub _check_request_holds_perm {
	my $user_id = shift;
	my $org_id  = shift;
	if (my $evt = $apputils->check_perms(
		$user_id, $org_id, "REQUEST_HOLDS")) {
		return $evt;
	}
}

my $ses_is_req_note = 'The login session is the requestor.  If the requestor is different from the user, ' .
                      'then the requestor must have VIEW_HOLD permissions';

__PACKAGE__->register_method(
    method    => "retrieve_holds_by_id",
    api_name  => "open-ils.circ.holds.retrieve_by_id",
    signature => {
        desc   => "Retrieve the hold, with hold transits attached, for the specified ID.  $ses_is_req_note",
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Hold ID',              type => 'number' }
        ],
        return => {
            desc => 'Hold object with transits attached, event on error',
        }
    }
);


sub retrieve_holds_by_id {
	my($self, $client, $auth, $hold_id) = @_;
	my $e = new_editor(authtoken=>$auth);
	$e->checkauth or return $e->event;
	$e->allowed('VIEW_HOLD') or return $e->event;

	my $holds = $e->search_action_hold_request(
		[
			{ id =>  $hold_id , fulfillment_time => undef }, 
			{ 
                order_by => { ahr => "request_time" },
                flesh => 1,
                flesh_fields => {ahr => ['notes']}
            }
		]
	);

	flesh_hold_transits($holds);
	flesh_hold_notices($holds, $e);
	return $holds;
}


__PACKAGE__->register_method(
    method    => "retrieve_holds",
    api_name  => "open-ils.circ.holds.retrieve",
    signature => {
        desc   => "Retrieves all the holds, with hold transits attached, for the specified user.  $ses_is_req_note",
        params => [
            { desc => 'Authentication token', type => 'string'  },
            { desc => 'User ID',              type => 'integer' },
            { desc => 'Available Only',       type => 'boolean' }
        ],
        return => {
            desc => 'list of holds, event on error',
        }
   }
);

__PACKAGE__->register_method(
    method        => "retrieve_holds",
    api_name      => "open-ils.circ.holds.id_list.retrieve",
    authoritative => 1,
    signature     => {
        desc   => "Retrieves all the hold IDs, for the specified user.  $ses_is_req_note",
        params => [
            { desc => 'Authentication token', type => 'string'  },
            { desc => 'User ID',              type => 'integer' },
            { desc => 'Available Only',       type => 'boolean' }
        ],
        return => {
            desc => 'list of holds, event on error',
        }
   }
);

__PACKAGE__->register_method(
    method        => "retrieve_holds",
    api_name      => "open-ils.circ.holds.canceled.retrieve",
    authoritative => 1,
    signature     => {
        desc   => "Retrieves all the cancelled holds for the specified user.  $ses_is_req_note",
        params => [
            { desc => 'Authentication token', type => 'string'  },
            { desc => 'User ID',              type => 'integer' }
        ],
        return => {
            desc => 'list of holds, event on error',
        }
   }
);

__PACKAGE__->register_method(
    method        => "retrieve_holds",
    api_name      => "open-ils.circ.holds.canceled.id_list.retrieve",
    authoritative => 1,
    signature     => {
        desc   => "Retrieves list of cancelled hold IDs for the specified user.  $ses_is_req_note",
        params => [
            { desc => 'Authentication token', type => 'string'  },
            { desc => 'User ID',              type => 'integer' }
        ],
        return => {
            desc => 'list of hold IDs, event on error',
        }
   }
);


sub retrieve_holds {
    my ($self, $client, $auth, $user_id, $available) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $user_id = $e->requestor->id unless defined $user_id;

    my $notes_filter = {staff => 'f'};
    my $user = $e->retrieve_actor_user($user_id) or return $e->event;
    unless($user_id == $e->requestor->id) {
        if($e->allowed('VIEW_HOLD', $user->home_ou)) {
            $notes_filter = {staff => 't'}
        } else {
            my $allowed = OpenILS::Application::Actor::Friends->friend_perm_allowed(
                $e, $user_id, $e->requestor->id, 'hold.view');
            return $e->event unless $allowed;
        }
    } else {
        # staff member looking at his/her own holds can see staff and non-staff notes
        $notes_filter = {} if $e->allowed('VIEW_HOLD', $user->home_ou);
    }

    my $holds_query = {
        select => {ahr => ['id']},
        from => 'ahr', 
        where => {usr => $user_id, fulfillment_time => undef}
    };

    if($self->api_name =~ /canceled/) {

        # Fetch the canceled holds
        # order cancelled holds by cancel time, most recent first

        $holds_query->{order_by} = [{class => 'ahr', field => 'cancel_time', direction => 'desc'}];

        my $cancel_age;
        my $cancel_count = $U->ou_ancestor_setting_value(
                $e->requestor->ws_ou, 'circ.holds.canceled.display_count', $e);

        unless($cancel_count) {
            $cancel_age = $U->ou_ancestor_setting_value(
                $e->requestor->ws_ou, 'circ.holds.canceled.display_age', $e);

            # if no settings are defined, default to last 10 cancelled holds
            $cancel_count = 10 unless $cancel_age;
        }

        if($cancel_count) { # limit by count

            $holds_query->{where}->{cancel_time} = {'!=' => undef};
            $holds_query->{limit} = $cancel_count;

        } elsif($cancel_age) { # limit by age

            # find all of the canceled holds that were canceled within the configured time frame
            my $date = DateTime->now->subtract(seconds => OpenSRF::Utils::interval_to_seconds($cancel_age));
            $date = $U->epoch2ISO8601($date->epoch);
            $holds_query->{where}->{cancel_time} = {'>=' => $date};
        }

    } else {

        # order non-cancelled holds by ready-for-pickup, then active, followed by suspended
        # "compare" sorts false values to the front.  testing pickup_lib != current_shelf_lib
        # will sort by pl = csl > pl != csl > followed by csl is null;
        $holds_query->{order_by} = [
            {   class => 'ahr', 
                field => 'pickup_lib', 
                compare => {'!='  => {'+ahr' => 'current_shelf_lib'}}},
            {class => 'ahr', field => 'shelf_time'},
            {class => 'ahr', field => 'frozen'},
            {class => 'ahr', field => 'request_time'}

        ];
        $holds_query->{where}->{cancel_time} = undef;
        if($available) {
            $holds_query->{where}->{shelf_time} = {'!=' => undef};
            # Maybe?
            $holds_query->{where}->{pickup_lib} = {'=' => 'current_shelf_lib'};
        }
    }

    my $hold_ids = $e->json_query($holds_query);
    $hold_ids = [ map { $_->{id} } @$hold_ids ];

    return $hold_ids if $self->api_name =~ /id_list/;

    my @holds;
    for my $hold_id ( @$hold_ids ) {

        my $hold = $e->retrieve_action_hold_request($hold_id);
        $hold->notes($e->search_action_hold_request_note({hold => $hold_id, %$notes_filter}));

        $hold->transit(
            $e->search_action_hold_transit_copy([
                {hold => $hold->id},
                {order_by => {ahtc => 'source_send_time desc'}, limit => 1}])->[0]
        );

        push(@holds, $hold);
    }

    return \@holds;
}


__PACKAGE__->register_method(
    method   => 'user_hold_count',
    api_name => 'open-ils.circ.hold.user.count'
);

sub user_hold_count {
    my ( $self, $conn, $auth, $userid ) = @_;
    my $e = new_editor( authtoken => $auth );
    return $e->event unless $e->checkauth;
    my $patron = $e->retrieve_actor_user($userid)
        or return $e->event;
    return $e->event unless $e->allowed( 'VIEW_HOLD', $patron->home_ou );
    return __user_hold_count( $self, $e, $userid );
}

sub __user_hold_count {
    my ( $self, $e, $userid ) = @_;
    my $holds = $e->search_action_hold_request(
        {
            usr              => $userid,
            fulfillment_time => undef,
            cancel_time      => undef,
        },
        { idlist => 1 }
    );

    return scalar(@$holds);
}


__PACKAGE__->register_method(
    method   => "retrieve_holds_by_pickup_lib",
    api_name => "open-ils.circ.holds.retrieve_by_pickup_lib",
    notes    => 
      "Retrieves all the holds, with hold transits attached, for the specified pickup_ou id."
);

__PACKAGE__->register_method(
    method   => "retrieve_holds_by_pickup_lib",
    api_name => "open-ils.circ.holds.id_list.retrieve_by_pickup_lib",
    notes    => "Retrieves all the hold ids for the specified pickup_ou id. "
);

sub retrieve_holds_by_pickup_lib {
    my ($self, $client, $login_session, $ou_id) = @_;

    #FIXME -- put an appropriate permission check here
    #my( $user, $target, $evt ) = $apputils->checkses_requestor(
    #	$login_session, $user_id, 'VIEW_HOLD' );
    #return $evt if $evt;

	my $holds = $apputils->simplereq(
		'open-ils.cstore',
		"open-ils.cstore.direct.action.hold_request.search.atomic",
		{ 
			pickup_lib =>  $ou_id , 
			fulfillment_time => undef,
			cancel_time => undef
		}, 
		{ order_by => { ahr => "request_time" } }
    );

    if ( ! $self->api_name =~ /id_list/ ) {
        flesh_hold_transits($holds);
        return $holds;
    }
    # else id_list
    return [ map { $_->id } @$holds ];
}


__PACKAGE__->register_method(
    method   => "uncancel_hold",
    api_name => "open-ils.circ.hold.uncancel"
);

sub uncancel_hold {
	my($self, $client, $auth, $hold_id) = @_;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;

	my $hold = $e->retrieve_action_hold_request($hold_id)
		or return $e->die_event;
    return $e->die_event unless $e->allowed('CANCEL_HOLDS', $hold->request_lib);

    if ($hold->fulfillment_time) {
        $e->rollback;
        return 0;
    }
    unless ($hold->cancel_time) {
        $e->rollback;
        return 1;
    }

    # if configured to reset the request time, also reset the expire time
    if($U->ou_ancestor_setting_value(
        $hold->request_lib, 'circ.holds.uncancel.reset_request_time', $e)) {

        $hold->request_time('now');
        $hold->expire_time(calculate_expire_time($hold->request_lib));
    }

    $hold->clear_cancel_time;
    $hold->clear_cancel_cause;
    $hold->clear_cancel_note;
    $hold->clear_shelf_time;
    $hold->clear_current_copy;
    $hold->clear_capture_time;
    $hold->clear_prev_check_time;
    $hold->clear_shelf_expire_time;
	$hold->clear_current_shelf_lib;

    $e->update_action_hold_request($hold) or return $e->die_event;
    $e->commit;

    $U->storagereq('open-ils.storage.action.hold_request.copy_targeter', undef, $hold_id);

    return 1;
}


__PACKAGE__->register_method(
    method    => "cancel_hold",
    api_name  => "open-ils.circ.hold.cancel",
    signature => {
        desc   => 'Cancels the specified hold.  The login session is the requestor.  If the requestor is different from the usr field ' .
                  'on the hold, the requestor must have CANCEL_HOLDS permissions. The hold may be either the hold object or the hold id',
        param  => [
            {desc => 'Authentication token',  type => 'string'},
            {desc => 'Hold ID',               type => 'number'},
            {desc => 'Cause of Cancellation', type => 'string'},
            {desc => 'Note',                  type => 'string'}
        ],
        return => {
            desc => '1 on success, event on error'
        }
    }
);

sub cancel_hold {
	my($self, $client, $auth, $holdid, $cause, $note) = @_;

	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->die_event unless $e->checkauth;

	my $hold = $e->retrieve_action_hold_request($holdid)
		or return $e->die_event;

	if( $e->requestor->id ne $hold->usr ) {
		return $e->die_event unless $e->allowed('CANCEL_HOLDS');
	}

	if ($hold->cancel_time) {
        $e->rollback;
        return 1;
    }

	# If the hold is captured, reset the copy status
	if( $hold->capture_time and $hold->current_copy ) {

		my $copy = $e->retrieve_asset_copy($hold->current_copy)
			or return $e->die_event;

		if( $copy->status == OILS_COPY_STATUS_ON_HOLDS_SHELF ) {
         $logger->info("canceling hold $holdid whose item is on the holds shelf");
#			$logger->info("setting copy to status 'reshelving' on hold cancel");
#			$copy->status(OILS_COPY_STATUS_RESHELVING);
#			$copy->editor($e->requestor->id);
#			$copy->edit_date('now');
#			$e->update_asset_copy($copy) or return $e->event;

		} elsif( $copy->status == OILS_COPY_STATUS_IN_TRANSIT ) {

			my $hid = $hold->id;
			$logger->warn("! canceling hold [$hid] that is in transit");
			my $transid = $e->search_action_hold_transit_copy({hold=>$hold->id},{idlist=>1})->[0];

			if( $transid ) {
				my $trans = $e->retrieve_action_transit_copy($transid);
				# Leave the transit alive, but  set the copy status to 
				# reshelving so it will be properly reshelved when it gets back home
				if( $trans ) {
					$trans->copy_status( OILS_COPY_STATUS_RESHELVING );
					$e->update_action_transit_copy($trans) or return $e->die_event;
				}
			}
		}
	}

	$hold->cancel_time('now');
    $hold->cancel_cause($cause);
    $hold->cancel_note($note);
	$e->update_action_hold_request($hold)
		or return $e->die_event;

	delete_hold_copy_maps($self, $e, $hold->id);

	$e->commit;

    # re-fetch the hold to pick up the real cancel_time (not "now") for A/T
    $e->xact_begin;
    $hold = $e->retrieve_action_hold_request($hold->id) or return $e->die_event;
    $e->rollback;

    if ($e->requestor->id == $hold->usr) {
        $U->create_events_for_hook('hold_request.cancel.patron', $hold, $hold->pickup_lib);
    } else {
        $U->create_events_for_hook('hold_request.cancel.staff', $hold, $hold->pickup_lib);
    }

	return 1;
}

sub delete_hold_copy_maps {
	my $class  = shift;
	my $editor = shift;
	my $holdid = shift;

	my $maps = $editor->search_action_hold_copy_map({hold=>$holdid});
	for(@$maps) {
		$editor->delete_action_hold_copy_map($_) 
			or return $editor->event;
	}
	return undef;
}


my $update_hold_desc = 'The login session is the requestor. '       .
   'If the requestor is different from the usr field on the hold, ' .
   'the requestor must have UPDATE_HOLDS permissions. '             .
   'If supplying a hash of hold data, "id" must be included. '      .
   'The hash is ignored if a hold object is supplied, '             .
   'so you should supply only one kind of hold data argument.'      ;

__PACKAGE__->register_method(
    method    => "update_hold",
    api_name  => "open-ils.circ.hold.update",
    signature => {
        desc   => "Updates the specified hold.  $update_hold_desc",
        params => [
            {desc => 'Authentication token',         type => 'string'},
            {desc => 'Hold Object',                  type => 'object'},
            {desc => 'Hash of values to be applied', type => 'object'}
        ],
        return => {
            desc => 'Hold ID on success, event on error',
            # type => 'number'
        }
    }
);

__PACKAGE__->register_method(
    method    => "batch_update_hold",
    api_name  => "open-ils.circ.hold.update.batch",
    stream    => 1,
    signature => {
        desc   => "Updates the specified hold(s).  $update_hold_desc",
        params => [
            {desc => 'Authentication token',                    type => 'string'},
            {desc => 'Array of hold obejcts',                   type => 'array' },
            {desc => 'Array of hashes of values to be applied', type => 'array' }
        ],
        return => {
            desc => 'Hold ID per success, event per error',
        }
    }
);

sub update_hold {
	my($self, $client, $auth, $hold, $values) = @_;
    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    my $resp = update_hold_impl($self, $e, $hold, $values);
    if ($U->event_code($resp)) {
        $e->rollback;
        return $resp;
    }
    $e->commit;     # FIXME: update_hold_impl already does $e->commit  ??
    return $resp;
}

sub batch_update_hold {
	my($self, $client, $auth, $hold_list, $values_list) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $count = ($hold_list) ? scalar(@$hold_list) : scalar(@$values_list);     # FIXME: we don't know for sure that we got $values_list.  we could have neither list.
    $hold_list   ||= [];
    $values_list ||= [];      # FIXME: either move this above $count declaration, or send an event if both lists undef.  Probably the latter.

# FIXME: Failing over to [] guarantees warnings for "Use of unitialized value" in update_hold_impl call.
# FIXME: We should be sure we only call update_hold_impl with hold object OR hash, not both.

    for my $idx (0..$count-1) {
        $e->xact_begin;
        my $resp = update_hold_impl($self, $e, $hold_list->[$idx], $values_list->[$idx]);
        $e->xact_commit unless $U->event_code($resp);
        $client->respond($resp);
    }

    $e->disconnect;
    return undef;       # not in the register return type, assuming we should always have at least one list populated
}

sub update_hold_impl {
    my($self, $e, $hold, $values) = @_;
    my $hold_status;
    my $need_retarget = 0;

    unless($hold) {
        $hold = $e->retrieve_action_hold_request($values->{id})
            or return $e->die_event;
        for my $k (keys %$values) {
            # Outside of pickup_lib (covered by the first regex) I don't know when these would currently change.
            # But hey, why not cover things that may happen later?
            if ($k =~ '_(lib|ou)$' || $k eq 'target' || $k eq 'hold_type' || $k eq 'requestor' || $k eq 'selection_depth' || $k eq 'holdable_formats') {
                if (defined $values->{$k} && defined $hold->$k() && $values->{$k} ne $hold->$k()) {
                    # Value changed? RETARGET!
                    $need_retarget = 1;
                } elsif (defined $hold->$k() != defined $values->{$k}) {
                    # Value being set or cleared? RETARGET!
                    $need_retarget = 1;
                }
            }
            if (defined $values->{$k}) {
                $hold->$k($values->{$k});
            } else {
                my $f = "clear_$k"; $hold->$f();
            }
        }
    }

    my $orig_hold = $e->retrieve_action_hold_request($hold->id)
        or return $e->die_event;

    # don't allow the user to be changed
    return OpenILS::Event->new('BAD_PARAMS') if $hold->usr != $orig_hold->usr;

    if($hold->usr ne $e->requestor->id) {
        # if the hold is for a different user, make sure the 
        # requestor has the appropriate permissions
        my $usr = $e->retrieve_actor_user($hold->usr)
            or return $e->die_event;
        return $e->die_event unless $e->allowed('UPDATE_HOLD', $usr->home_ou);
    }


    # --------------------------------------------------------------
    # Changing the request time is like playing God
    # --------------------------------------------------------------
    if($hold->request_time ne $orig_hold->request_time) {
        return OpenILS::Event->new('BAD_PARAMS') if $hold->fulfillment_time;
        return $e->die_event unless $e->allowed('UPDATE_HOLD_REQUEST_TIME', $hold->pickup_lib);
    }
    
	
	# --------------------------------------------------------------
	# Code for making sure staff have appropriate permissons for cut_in_line
	# This, as is, doesn't prevent a user from cutting their own holds in line 
	# but needs to
	# --------------------------------------------------------------	
	if($U->is_true($hold->cut_in_line) ne $U->is_true($orig_hold->cut_in_line)) {
		return $e->die_event unless $e->allowed('UPDATE_HOLD_REQUEST_TIME', $hold->pickup_lib);
	}


    # --------------------------------------------------------------
    # Disallow hold suspencion if the hold is already captured.
    # --------------------------------------------------------------
    if ($U->is_true($hold->frozen) and not $U->is_true($orig_hold->frozen)) {
        $hold_status = _hold_status($e, $hold);
        if ($hold_status > 2 && $hold_status != 7) { # hold is captured
            $logger->info("bypassing hold freeze on captured hold");
            return OpenILS::Event->new('HOLD_SUSPEND_AFTER_CAPTURE');
        }
    }


    # --------------------------------------------------------------
    # if the hold is on the holds shelf or in transit and the pickup 
    # lib changes we need to create a new transit.
    # --------------------------------------------------------------
    if($orig_hold->pickup_lib ne $hold->pickup_lib) {

        $hold_status = _hold_status($e, $hold) unless $hold_status;

        if($hold_status == 3) { # in transit

            return $e->die_event unless $e->allowed('UPDATE_PICKUP_LIB_FROM_TRANSIT', $orig_hold->pickup_lib);
            return $e->die_event unless $e->allowed('UPDATE_PICKUP_LIB_FROM_TRANSIT', $hold->pickup_lib);

            $logger->info("updating pickup lib for hold ".$hold->id." while already in transit");

            # update the transit to reflect the new pickup location
			my $transit = $e->search_action_hold_transit_copy(
                {hold=>$hold->id, dest_recv_time => undef})->[0] 
                or return $e->die_event;

            $transit->prev_dest($transit->dest); # mark the previous destination on the transit
            $transit->dest($hold->pickup_lib);
            $e->update_action_hold_transit_copy($transit) or return $e->die_event;

        } elsif($hold_status == 4 or $hold_status == 5 or $hold_status == 8) { # on holds shelf

            return $e->die_event unless $e->allowed('UPDATE_PICKUP_LIB_FROM_HOLDS_SHELF', $orig_hold->pickup_lib);
            return $e->die_event unless $e->allowed('UPDATE_PICKUP_LIB_FROM_HOLDS_SHELF', $hold->pickup_lib);

            $logger->info("updating pickup lib for hold ".$hold->id." while on holds shelf");

            if ($hold->pickup_lib eq $orig_hold->current_shelf_lib) {
                # This can happen if the pickup lib is changed while the hold is 
                # on the shelf, then changed back to the original pickup lib.
                # Restore the original shelf_expire_time to prevent abuse.
                set_hold_shelf_expire_time(undef, $hold, $e, $hold->shelf_time);

            } else {
                # clear to prevent premature shelf expiration
                $hold->clear_shelf_expire_time;
            }
        }
    } 

    if($U->is_true($hold->frozen)) {
        $logger->info("clearing current_copy and check_time for frozen hold ".$hold->id);
        $hold->clear_current_copy;
        $hold->clear_prev_check_time;
        # Clear expire_time to prevent frozen holds from expiring.
        $logger->info("clearing expire_time for frozen hold ".$hold->id);
        $hold->clear_expire_time;
    }

    # If the hold_expire_time is in the past && is not equal to the
    # original expire_time, then reset the expire time to be in the
    # future.
    if ($hold->expire_time && $U->datecmp($hold->expire_time) == -1 && $U->datecmp($hold->expire_time, $orig_hold->expire_time) != 0) {
        $hold->expire_time(calculate_expire_time($hold->request_lib));
    }

    # If the hold is reactivated, reset the expire_time.
    if(!$U->is_true($hold->frozen) && $U->is_true($orig_hold->frozen)) {
        $logger->info("Reset expire_time on activated hold ".$hold->id);
        $hold->expire_time(calculate_expire_time($hold->request_lib));
    }

    $e->update_action_hold_request($hold) or return $e->die_event;
    $e->commit;

    if(!$U->is_true($hold->frozen) && $U->is_true($orig_hold->frozen)) {
        $logger->info("Running targeter on activated hold ".$hold->id);
        $U->storagereq( 'open-ils.storage.action.hold_request.copy_targeter', undef, $hold->id );
    }

    # a change to mint-condition changes the set of potential copies, so retarget the hold;
    if($U->is_true($hold->mint_condition) and !$U->is_true($orig_hold->mint_condition)) {
        _reset_hold($self, $e->requestor, $hold) 
    } elsif($need_retarget && !defined $hold->capture_time()) { # If needed, retarget the hold due to changes
        $U->storagereq(
    		'open-ils.storage.action.hold_request.copy_targeter', undef, $hold->id );
    }

    return $hold->id;
}

# this does not update the hold in the DB.  It only 
# sets the shelf_expire_time field on the hold object.
# start_time is optional and defaults to 'now'
sub set_hold_shelf_expire_time {
    my ($class, $hold, $editor, $start_time) = @_;

    my $shelf_expire = $U->ou_ancestor_setting_value( 
        $hold->pickup_lib,
        'circ.holds.default_shelf_expire_interval', 
        $editor
    );

    return undef unless $shelf_expire;

    $start_time = ($start_time) ? 
        DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($start_time)) :
        DateTime->now;

    my $seconds = OpenSRF::Utils->interval_to_seconds($shelf_expire);
    my $expire_time = $start_time->add(seconds => $seconds);

    # if the shelf expire time overlaps with a pickup lib's 
    # closed date, push it out to the first open date
    my $dateinfo = $U->storagereq(
        'open-ils.storage.actor.org_unit.closed_date.overlap', 
        $hold->pickup_lib, $expire_time->strftime('%FT%T%z'));

    if($dateinfo) {
        my $dt_parser = DateTime::Format::ISO8601->new;
        $expire_time = $dt_parser->parse_datetime(cleanse_ISO8601($dateinfo->{end}));

        # TODO: enable/disable time bump via setting?
        $expire_time->set(hour => '23', minute => '59', second => '59');

        $logger->info("circulator: shelf_expire_time overlaps".
            " with closed date, pushing expire time to $expire_time");
    }

    $hold->shelf_expire_time($expire_time->strftime('%FT%T%z'));
    return undef;
}


sub transit_hold {
    my($e, $orig_hold, $hold, $copy) = @_;
    my $src  = $orig_hold->pickup_lib;
    my $dest = $hold->pickup_lib;

    $logger->info("putting hold into transit on pickup_lib update");

    my $transit = Fieldmapper::action::hold_transit_copy->new;
    $transit->hold($hold->id);
    $transit->source($src);
    $transit->dest($dest);
    $transit->target_copy($copy->id);
    $transit->source_send_time('now');
    $transit->copy_status(OILS_COPY_STATUS_ON_HOLDS_SHELF);

    $copy->status(OILS_COPY_STATUS_IN_TRANSIT);
    $copy->editor($e->requestor->id);
    $copy->edit_date('now');

    $e->create_action_hold_transit_copy($transit) or return $e->die_event;
    $e->update_asset_copy($copy) or return $e->die_event;
    return undef;
}

# if the hold is frozen, this method ensures that the hold is not "targeted", 
# that is, it clears the current_copy and prev_check_time to essentiallly 
# reset the hold.  If it is being activated, it runs the targeter in the background
sub update_hold_if_frozen {
    my($self, $e, $hold, $orig_hold) = @_;
    return if $hold->capture_time;

    if($U->is_true($hold->frozen)) {
        $logger->info("clearing current_copy and check_time for frozen hold ".$hold->id);
        $hold->clear_current_copy;
        $hold->clear_prev_check_time;

    } else {
        if($U->is_true($orig_hold->frozen)) {
            $logger->info("Running targeter on activated hold ".$hold->id);
            $U->storagereq( 'open-ils.storage.action.hold_request.copy_targeter', undef, $hold->id );
        }
    }
}

__PACKAGE__->register_method(
    method    => "hold_note_CUD",
    api_name  => "open-ils.circ.hold_request.note.cud",
    signature => {
        desc   => 'Create, update or delete a hold request note.  If the operator (from Auth. token) '
                . 'is not the owner of the hold, the UPDATE_HOLD permission is required',
        params => [
            { desc => 'Authentication token', type => 'string' },
            { desc => 'Hold note object',     type => 'object' }
        ],
        return => {
            desc => 'Returns the note ID, event on error'
        },
    }
);

sub hold_note_CUD {
	my($self, $conn, $auth, $note) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $hold = $e->retrieve_action_hold_request($note->hold)
        or return $e->die_event;

    if($hold->usr ne $e->requestor->id) {
        my $usr = $e->retrieve_actor_user($hold->usr);
        return $e->die_event unless $e->allowed('UPDATE_HOLD', $usr->home_ou);
        $note->staff('t') if $note->isnew;
    }

    if($note->isnew) {
        $e->create_action_hold_request_note($note) or return $e->die_event;
    } elsif($note->ischanged) {
        $e->update_action_hold_request_note($note) or return $e->die_event;
    } elsif($note->isdeleted) {
        $e->delete_action_hold_request_note($note) or return $e->die_event;
    }

    $e->commit;
    return $note->id;
}


__PACKAGE__->register_method(
    method    => "retrieve_hold_status",
    api_name  => "open-ils.circ.hold.status.retrieve",
    signature => {
        desc   => 'Calculates the current status of the hold. The requestor must have '      .
                  'VIEW_HOLD permissions if the hold is for a user other than the requestor' ,
        param  => [
            { desc => 'Hold ID', type => 'number' }
        ],
        return => {
            # type => 'number',     # event sometimes
            desc => <<'END_OF_DESC'
Returns event on error or:
-1 on error (for now),
 1 for 'waiting for copy to become available',
 2 for 'waiting for copy capture',
 3 for 'in transit',
 4 for 'arrived',
 5 for 'hold-shelf-delay'
 6 for 'canceled'
 7 for 'suspended'
 8 for 'captured, on wrong hold shelf'
END_OF_DESC
        }
    }
);

sub retrieve_hold_status {
	my($self, $client, $auth, $hold_id) = @_;

	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;
	my $hold = $e->retrieve_action_hold_request($hold_id)
		or return $e->event;

	if( $e->requestor->id != $hold->usr ) {
		return $e->event unless $e->allowed('VIEW_HOLD');
	}

	return _hold_status($e, $hold);

}

sub _hold_status {
	my($e, $hold) = @_;
    if ($hold->cancel_time) {
        return 6;
    }
    if ($U->is_true($hold->frozen) && !$hold->capture_time) {
        return 7;
    }
    if ($hold->current_shelf_lib and $hold->current_shelf_lib ne $hold->pickup_lib) {
        return 8;
    }
	return 1 unless $hold->current_copy;
	return 2 unless $hold->capture_time;

	my $copy = $hold->current_copy;
	unless( ref $copy ) {
		$copy = $e->retrieve_asset_copy($hold->current_copy)
			or return $e->event;
	}

	return 3 if $copy->status == OILS_COPY_STATUS_IN_TRANSIT;

	if($copy->status == OILS_COPY_STATUS_ON_HOLDS_SHELF) {

        my $hs_wait_interval = $U->ou_ancestor_setting_value($hold->pickup_lib, 'circ.hold_shelf_status_delay');
        return 4 unless $hs_wait_interval;

        # if a hold_shelf_status_delay interval is defined and start_time plus 
        # the interval is greater than now, consider the hold to be in the virtual 
        # "on its way to the holds shelf" status. Return 5.

        my $transit    = $e->search_action_hold_transit_copy({hold => $hold->id})->[0];
        my $start_time = ($transit) ? $transit->dest_recv_time : $hold->capture_time;
        $start_time    = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($start_time));
        my $end_time   = $start_time->add(seconds => OpenSRF::Utils::interval_to_seconds($hs_wait_interval));

        return 5 if $end_time > DateTime->now;
        return 4;
    }

    return -1;  # error
}



__PACKAGE__->register_method(
    method    => "retrieve_hold_queue_stats",
    api_name  => "open-ils.circ.hold.queue_stats.retrieve",
    signature => {
        desc   => 'Returns summary data about the state of a hold',
        params => [
            { desc => 'Authentication token',  type => 'string'},
            { desc => 'Hold ID', type => 'number'},
        ],
        return => {
            desc => q/Summary object with keys: 
                total_holds : total holds in queue
                queue_position : current queue position
                potential_copies : number of potential copies for this hold
                estimated_wait : estimated wait time in days
                status : hold status  
                     -1 => error or unexpected state,
                     1 => 'waiting for copy to become available',
                     2 => 'waiting for copy capture',
                     3 => 'in transit',
                     4 => 'arrived',
                     5 => 'hold-shelf-delay'
            /,
            type => 'object'
        }
    }
);

sub retrieve_hold_queue_stats {
    my($self, $conn, $auth, $hold_id) = @_;
	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;
	my $hold = $e->retrieve_action_hold_request($hold_id) or return $e->event;
	if($e->requestor->id != $hold->usr) {
		return $e->event unless $e->allowed('VIEW_HOLD');
	}
    return retrieve_hold_queue_status_impl($e, $hold);
}

sub retrieve_hold_queue_status_impl {
    my $e = shift;
    my $hold = shift;

    # The holds queue is defined as the distinct set of holds that share at 
    # least one potential copy with the context hold, plus any holds that
    # share the same hold type and target.  The latter part exists to
    # accomodate holds that currently have no potential copies
    my $q_holds = $e->json_query({

        # fetch cut_in_line and request_time since they're in the order_by
        # and we're asking for distinct values
        select => {ahr => ['id', 'cut_in_line', 'request_time']},
        from   => {
            ahr => {
                'ahcm' => {
                    join => {
                        'ahcm2' => {
                            'class' => 'ahcm',
                            'field' => 'target_copy',
                            'fkey'  => 'target_copy'
                        }
                    }
                }
            }
        },
        order_by => [
            {
                "class" => "ahr",
                "field" => "cut_in_line",
                "transform" => "coalesce",
                "params" => [ 0 ],
                "direction" => "desc"
            },
            { "class" => "ahr", "field" => "request_time" }
        ],
        distinct => 1,
        where => {
            '+ahcm2' => { hold => $hold->id }
        }
    });

    if (!@$q_holds) { # none? maybe we don't have a map ... 
        $q_holds = $e->json_query({
            select => {ahr => ['id', 'cut_in_line', 'request_time']},
            from   => 'ahr',
            order_by => [
                {
                    "class" => "ahr",
                    "field" => "cut_in_line",
                    "transform" => "coalesce",
                    "params" => [ 0 ],
                    "direction" => "desc"
                },
                { "class" => "ahr", "field" => "request_time" }
            ],
            where    => {
                hold_type => $hold->hold_type, 
                target    => $hold->target 
           } 
        });
    }


    my $qpos = 1;
    for my $h (@$q_holds) {
        last if $h->{id} == $hold->id;
        $qpos++;
    }

    my $hold_data = $e->json_query({
        select => {
            acp => [ {column => 'id', transform => 'count', aggregate => 1, alias => 'count'} ],
            ccm => [ {column =>'avg_wait_time'} ]
        }, 
        from => {
            ahcm => {
                acp => {
                    join => {
                        ccm => {type => 'left'}
                    }
                }
            }
        }, 
        where => {'+ahcm' => {hold => $hold->id} }
    });

    my $user_org = $e->json_query({select => {au => ['home_ou']}, from => 'au', where => {id => $hold->usr}})->[0]->{home_ou};

    my $default_wait = $U->ou_ancestor_setting_value($user_org, OILS_SETTING_HOLD_ESIMATE_WAIT_INTERVAL);
    my $min_wait = $U->ou_ancestor_setting_value($user_org, 'circ.holds.min_estimated_wait_interval');
    $min_wait = OpenSRF::Utils::interval_to_seconds($min_wait || '0 seconds');
    $default_wait ||= '0 seconds';

    # Estimated wait time is the average wait time across the set 
    # of potential copies, divided by the number of potential copies
    # times the queue position.  

    my $combined_secs = 0;
    my $num_potentials = 0;

    for my $wait_data (@$hold_data) {
        my $count += $wait_data->{count};
        $combined_secs += $count * 
            OpenSRF::Utils::interval_to_seconds($wait_data->{avg_wait_time} || $default_wait);
        $num_potentials += $count;
    }

    my $estimated_wait = -1;

    if($num_potentials) {
        my $avg_wait = $combined_secs / $num_potentials;
        $estimated_wait = $qpos * ($avg_wait / $num_potentials);
        $estimated_wait = $min_wait if $estimated_wait < $min_wait and $estimated_wait != -1;
    }

    return {
        total_holds      => scalar(@$q_holds),
        queue_position   => $qpos,
        potential_copies => $num_potentials,
        status           => _hold_status( $e, $hold ),
        estimated_wait   => int($estimated_wait)
    };
}


sub fetch_open_hold_by_current_copy {
	my $class = shift;
	my $copyid = shift;
	my $hold = $apputils->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.action.hold_request.search.atomic',
		{ current_copy =>  $copyid , cancel_time => undef, fulfillment_time => undef });
	return $hold->[0] if ref($hold);
	return undef;
}

sub fetch_related_holds {
	my $class = shift;
	my $copyid = shift;
	return $apputils->simplereq(
		'open-ils.cstore', 
		'open-ils.cstore.direct.action.hold_request.search.atomic',
		{ current_copy =>  $copyid , cancel_time => undef, fulfillment_time => undef });
}


__PACKAGE__->register_method(
    method    => "hold_pull_list",
    api_name  => "open-ils.circ.hold_pull_list.retrieve",
    signature => {
        desc   => 'Returns (reference to) a list of holds that need to be "pulled" by a given location. ' .
                  'The location is determined by the login session.',
        params => [
            { desc => 'Limit (optional)',  type => 'number'},
            { desc => 'Offset (optional)', type => 'number'},
        ],
        return => {
            desc => 'reference to a list of holds, or event on failure',
        }
    }
);

__PACKAGE__->register_method(
    method    => "hold_pull_list",
    api_name  => "open-ils.circ.hold_pull_list.id_list.retrieve",
    signature => {
        desc   => 'Returns (reference to) a list of holds IDs that need to be "pulled" by a given location. ' .
                  'The location is determined by the login session.',
        params => [
            { desc => 'Limit (optional)',  type => 'number'},
            { desc => 'Offset (optional)', type => 'number'},
        ],
        return => {
            desc => 'reference to a list of holds, or event on failure',
        }
    }
);

__PACKAGE__->register_method(
    method    => "hold_pull_list",
    api_name  => "open-ils.circ.hold_pull_list.retrieve.count",
    signature => {
        desc   => 'Returns a count of holds that need to be "pulled" by a given location. ' .
                  'The location is determined by the login session.',
        params => [
            { desc => 'Limit (optional)',  type => 'number'},
            { desc => 'Offset (optional)', type => 'number'},
        ],
        return => {
            desc => 'Holds count (integer), or event on failure',
            # type => 'number'
        }
    }
);


sub hold_pull_list {
	my( $self, $conn, $authtoken, $limit, $offset ) = @_;
	my( $reqr, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;

	my $org = $reqr->ws_ou || $reqr->home_ou;
	# the perm locaiton shouldn't really matter here since holds
	# will exist all over and VIEW_HOLDS should be universal
	$evt = $U->check_perms($reqr->id, $org, 'VIEW_HOLD');
	return $evt if $evt;

    if($self->api_name =~ /count/) {

		my $count = $U->storagereq(
			'open-ils.storage.direct.action.hold_request.pull_list.current_copy_circ_lib.status_filtered.count',
			$org, $limit, $offset ); 

        $logger->info("Grabbing pull list for org unit $org with $count items");
        return $count;

    } elsif( $self->api_name =~ /id_list/ ) {
		return $U->storagereq(
			'open-ils.storage.direct.action.hold_request.pull_list.id_list.current_copy_circ_lib.status_filtered.atomic',
			$org, $limit, $offset ); 

	} else {
		return $U->storagereq(
			'open-ils.storage.direct.action.hold_request.pull_list.search.current_copy_circ_lib.status_filtered.atomic',
			$org, $limit, $offset ); 
	}
}

__PACKAGE__->register_method(
    method    => "print_hold_pull_list",
    api_name  => "open-ils.circ.hold_pull_list.print",
    signature => {
        desc   => 'Returns an HTML-formatted holds pull list',
        params => [
            { desc => 'Authtoken', type => 'string'},
            { desc => 'Org unit ID.  Optional, defaults to workstation org unit', type => 'number'},
        ],
        return => {
            desc => 'HTML string',
            type => 'string'
        }
    }
);

sub print_hold_pull_list {
    my($self, $client, $auth, $org_id) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

    $org_id = (defined $org_id) ? $org_id : $e->requestor->ws_ou;
    return $e->event unless $e->allowed('VIEW_HOLD', $org_id);

    my $hold_ids = $U->storagereq(
        'open-ils.storage.direct.action.hold_request.pull_list.id_list.current_copy_circ_lib.status_filtered.atomic',
        $org_id, 10000);

    return undef unless @$hold_ids;

    $client->status(new OpenSRF::DomainObject::oilsContinueStatus);

    # Holds will /NOT/ be in order after this ...
    my $holds = $e->search_action_hold_request({id => $hold_ids}, {substream => 1});
    $client->status(new OpenSRF::DomainObject::oilsContinueStatus);

    # ... so we must resort.
    my $hold_map = +{map { $_->id => $_ } @$holds};
    my $sorted_holds = [];
    push @$sorted_holds, $hold_map->{$_} foreach @$hold_ids;

    return $U->fire_object_event(
        undef, "ahr.format.pull_list", $sorted_holds,
        $org_id, undef, undef, $client
    );

}

__PACKAGE__->register_method(
    method    => "print_hold_pull_list_stream",
    stream   => 1,
    api_name  => "open-ils.circ.hold_pull_list.print.stream",
    signature => {
        desc   => 'Returns a stream of fleshed holds',
        params => [
            { desc => 'Authtoken', type => 'string'},
            { desc => 'Hash of optional param: Org unit ID (defaults to workstation org unit), limit, offset, sort (array of: acplo.position, prefix, call_number, suffix, request_time)',
              type => 'object'
            },
        ],
        return => {
            desc => 'A stream of fleshed holds',
            type => 'object'
        }
    }
);

sub print_hold_pull_list_stream {
    my($self, $client, $auth, $params) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    delete($$params{org_id}) unless (int($$params{org_id}));
    delete($$params{limit}) unless (int($$params{limit}));
    delete($$params{offset}) unless (int($$params{offset}));
    delete($$params{chunk_size}) unless (int($$params{chunk_size}));
    delete($$params{chunk_size}) if  ($$params{chunk_size} && $$params{chunk_size} > 50); # keep the size reasonable
    $$params{chunk_size} ||= 10;

    $$params{org_id} = (defined $$params{org_id}) ? $$params{org_id}: $e->requestor->ws_ou;
    return $e->die_event unless $e->allowed('VIEW_HOLD', $$params{org_id });

    my $sort = [];
    if ($$params{sort} && @{ $$params{sort} }) {
        for my $s (@{ $$params{sort} }) {
            if ($s eq 'acplo.position') {
                push @$sort, {
                    "class" => "acplo", "field" => "position",
                    "transform" => "coalesce", "params" => [999]
                };
            } elsif ($s eq 'prefix') {
                push @$sort, {"class" => "acnp", "field" => "label_sortkey"};
            } elsif ($s eq 'call_number') {
                push @$sort, {"class" => "acn", "field" => "label_sortkey"};
            } elsif ($s eq 'suffix') {
                push @$sort, {"class" => "acns", "field" => "label_sortkey"};
            } elsif ($s eq 'request_time') {
                push @$sort, {"class" => "ahr", "field" => "request_time"};
            }
        }
    } else {
        push @$sort, {"class" => "ahr", "field" => "request_time"};
    }

    my $holds_ids = $e->json_query(
        {
            "select" => {"ahr" => ["id"]},
            "from" => {
                "ahr" => {
                    "acp" => { 
                        "field" => "id",
                        "fkey" => "current_copy",
                        "filter" => {
                            "circ_lib" => $$params{org_id}, "status" => [0,7]
                        },
                        "join" => {
                            "acn" => {
                                "field" => "id",
                                "fkey" => "call_number",
                                "join" => {
                                    "acnp" => {
                                        "field" => "id",
                                        "fkey" => "prefix"
                                    },
                                    "acns" => {
                                        "field" => "id",
                                        "fkey" => "suffix"
                                    }
                                }
                            },
                            "acplo" => {
                                "field" => "org",
                                "fkey" => "circ_lib", 
                                "type" => "left",
                                "filter" => {
                                    "location" => {"=" => {"+acp" => "location"}}
                                }
                            }
                        }
                    }
                }
            },
            "where" => {
                "+ahr" => {
                    "capture_time" => undef,
                    "cancel_time" => undef,
                    "-or" => [
                        {"expire_time" => undef },
                        {"expire_time" => {">" => "now"}}
                    ]
                }
            },
            (@$sort ? (order_by => $sort) : ()),
            ($$params{limit} ? (limit => $$params{limit}) : ()),
            ($$params{offset} ? (offset => $$params{offset}) : ())
        }, {"substream" => 1}
    ) or return $e->die_event;

    $logger->info("about to stream back " . scalar(@$holds_ids) . " holds");

    my @chunk;
    for my $hid (@$holds_ids) {
        push @chunk, $e->retrieve_action_hold_request([
            $hid->{"id"}, {
                "flesh" => 3,
                "flesh_fields" => {
                    "ahr" => ["usr", "current_copy"],
                    "au"  => ["card"],
                    "acp" => ["location", "call_number", "parts"],
                    "acn" => ["record","prefix","suffix"]
                }
            }
        ]);

        if (@chunk >= $$params{chunk_size}) {
            $client->respond( \@chunk );
            @chunk = ();
        }
    }
    $client->respond_complete( \@chunk ) if (@chunk);
    $e->disconnect;
    return undef;
}



__PACKAGE__->register_method(
    method        => 'fetch_hold_notify',
    api_name      => 'open-ils.circ.hold_notification.retrieve_by_hold',
    authoritative => 1,
    signature     => q/ 
Returns a list of hold notification objects based on hold id.
@param authtoken The loggin session key
@param holdid The id of the hold whose notifications we want to retrieve
@return An array of hold notification objects, event on error.
/
);

sub fetch_hold_notify {
	my( $self, $conn, $authtoken, $holdid ) = @_;
	my( $requestor, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;
	my ($hold, $patron);
	($hold, $evt) = $U->fetch_hold($holdid);
	return $evt if $evt;
	($patron, $evt) = $U->fetch_user($hold->usr);
	return $evt if $evt;

	$evt = $U->check_perms($requestor->id, $patron->home_ou, 'VIEW_HOLD_NOTIFICATION');
	return $evt if $evt;

	$logger->info("User ".$requestor->id." fetching hold notifications for hold $holdid");
	return $U->cstorereq(
		'open-ils.cstore.direct.action.hold_notification.search.atomic', {hold => $holdid} );
}


__PACKAGE__->register_method(
    method    => 'create_hold_notify',
    api_name  => 'open-ils.circ.hold_notification.create',
    signature => q/
Creates a new hold notification object
@param authtoken The login session key
@param notification The hold notification object to create
@return ID of the new object on success, Event on error
/
);

sub create_hold_notify {
   my( $self, $conn, $auth, $note ) = @_;
   my $e = new_editor(authtoken=>$auth, xact=>1);
   return $e->die_event unless $e->checkauth;

   my $hold = $e->retrieve_action_hold_request($note->hold)
      or return $e->die_event;
   my $patron = $e->retrieve_actor_user($hold->usr) 
      or return $e->die_event;

   return $e->die_event unless 
      $e->allowed('CREATE_HOLD_NOTIFICATION', $patron->home_ou);

   $note->notify_staff($e->requestor->id);
   $e->create_action_hold_notification($note) or return $e->die_event;
   $e->commit;
   return $note->id;
}

__PACKAGE__->register_method(
    method    => 'create_hold_note',
    api_name  => 'open-ils.circ.hold_note.create',
    signature => q/
		Creates a new hold request note object
		@param authtoken The login session key
		@param note The hold note object to create
		@return ID of the new object on success, Event on error
		/
);

sub create_hold_note {
   my( $self, $conn, $auth, $note ) = @_;
   my $e = new_editor(authtoken=>$auth, xact=>1);
   return $e->die_event unless $e->checkauth;

   my $hold = $e->retrieve_action_hold_request($note->hold)
      or return $e->die_event;
   my $patron = $e->retrieve_actor_user($hold->usr) 
      or return $e->die_event;

   return $e->die_event unless 
      $e->allowed('UPDATE_HOLD', $patron->home_ou); # FIXME: Using permcrud perm listed in fm_IDL.xml for ahrn.  Probably want something more specific

   $e->create_action_hold_request_note($note) or return $e->die_event;
   $e->commit;
   return $note->id;
}

__PACKAGE__->register_method(
    method    => 'reset_hold',
    api_name  => 'open-ils.circ.hold.reset',
    signature => q/
		Un-captures and un-targets a hold, essentially returning
		it to the state it was in directly after it was placed,
		then attempts to re-target the hold
		@param authtoken The login session key
		@param holdid The id of the hold
	/
);


sub reset_hold {
	my( $self, $conn, $auth, $holdid ) = @_;
	my $reqr;
	my ($hold, $evt) = $U->fetch_hold($holdid);
	return $evt if $evt;
	($reqr, $evt) = $U->checksesperm($auth, 'UPDATE_HOLD');
	return $evt if $evt;
	$evt = _reset_hold($self, $reqr, $hold);
	return $evt if $evt;
	return 1;
}


__PACKAGE__->register_method(
    method   => 'reset_hold_batch',
    api_name => 'open-ils.circ.hold.reset.batch'
);

sub reset_hold_batch {
    my($self, $conn, $auth, $hold_ids) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    for my $hold_id ($hold_ids) {

        my $hold = $e->retrieve_action_hold_request(
            [$hold_id, {flesh => 1, flesh_fields => {ahr => ['usr']}}]) 
            or return $e->event;

	    next unless $e->allowed('UPDATE_HOLD', $hold->usr->home_ou);
        _reset_hold($self, $e->requestor, $hold);
    }

    return 1;
}


sub _reset_hold {
	my ($self, $reqr, $hold) = @_;

	my $e = new_editor(xact =>1, requestor => $reqr);

	$logger->info("reseting hold ".$hold->id);

	my $hid = $hold->id;

	if( $hold->capture_time and $hold->current_copy ) {

		my $copy = $e->retrieve_asset_copy($hold->current_copy)
			or return $e->die_event;

		if( $copy->status == OILS_COPY_STATUS_ON_HOLDS_SHELF ) {
			$logger->info("setting copy to status 'reshelving' on hold retarget");
			$copy->status(OILS_COPY_STATUS_RESHELVING);
			$copy->editor($e->requestor->id);
			$copy->edit_date('now');
			$e->update_asset_copy($copy) or return $e->die_event;

		} elsif( $copy->status == OILS_COPY_STATUS_IN_TRANSIT ) {

			# We don't want the copy to remain "in transit"
			$copy->status(OILS_COPY_STATUS_RESHELVING);
			$logger->warn("! reseting hold [$hid] that is in transit");
			my $transid = $e->search_action_hold_transit_copy({hold=>$hold->id},{idlist=>1})->[0];

			if( $transid ) {
				my $trans = $e->retrieve_action_transit_copy($transid);
				if( $trans ) {
					$logger->info("Aborting transit [$transid] on hold [$hid] reset...");
					my $evt = OpenILS::Application::Circ::Transit::__abort_transit($e, $trans, $copy, 1, 1);
					$logger->info("Transit abort completed with result $evt");
					unless ("$evt" eq 1) {
                        $e->rollback;
					    return $evt;
                    }
				}
			}
		}
	}

	$hold->clear_capture_time;
	$hold->clear_current_copy;
	$hold->clear_shelf_time;
	$hold->clear_shelf_expire_time;
	$hold->clear_current_shelf_lib;

	$e->update_action_hold_request($hold) or return $e->die_event;
	$e->commit;

	$U->storagereq(
		'open-ils.storage.action.hold_request.copy_targeter', undef, $hold->id );

	return undef;
}


__PACKAGE__->register_method(
    method    => 'fetch_open_title_holds',
    api_name  => 'open-ils.circ.open_holds.retrieve',
    signature => q/
		Returns a list ids of un-fulfilled holds for a given title id
		@param authtoken The login session key
		@param id the id of the item whose holds we want to retrieve
		@param type The hold type - M, T, I, V, C, F, R
	/
);

sub fetch_open_title_holds {
	my( $self, $conn, $auth, $id, $type, $org ) = @_;
	my $e = new_editor( authtoken => $auth );
	return $e->event unless $e->checkauth;

	$type ||= "T";
	$org  ||= $e->requestor->ws_ou;

#	return $e->search_action_hold_request(
#		{ target => $id, hold_type => $type, fulfillment_time => undef }, {idlist=>1});

	# XXX make me return IDs in the future ^--
	my $holds = $e->search_action_hold_request(
		{ 
			target				=> $id, 
			cancel_time			=> undef, 
			hold_type			=> $type, 
			fulfillment_time	=> undef 
		}
	);

	flesh_hold_transits($holds);
	return $holds;
}


sub flesh_hold_transits {
	my $holds = shift;
	for my $hold ( @$holds ) {
		$hold->transit(
			$apputils->simplereq(
				'open-ils.cstore',
				"open-ils.cstore.direct.action.hold_transit_copy.search.atomic",
				{ hold => $hold->id },
				{ order_by => { ahtc => 'id desc' }, limit => 1 }
			)->[0]
		);
	}
}

sub flesh_hold_notices {
	my( $holds, $e ) = @_;
	$e ||= new_editor();

	for my $hold (@$holds) {
		my $notices = $e->search_action_hold_notification(
			[
				{ hold => $hold->id },
				{ order_by => { anh => 'notify_time desc' } },
			],
			{idlist=>1}
		);

		$hold->notify_count(scalar(@$notices));
		if( @$notices ) {
			my $n = $e->retrieve_action_hold_notification($$notices[0])
				or return $e->event;
			$hold->notify_time($n->notify_time);
		}
	}
}


__PACKAGE__->register_method(
    method    => 'fetch_captured_holds',
    api_name  => 'open-ils.circ.captured_holds.on_shelf.retrieve',
    stream    => 1,
    authoritative => 1,
    signature => q/
		Returns a list of un-fulfilled holds (on the Holds Shelf) for a given title id
		@param authtoken The login session key
		@param org The org id of the location in question
		@param match_copy A specific copy to limit to
	/
);

__PACKAGE__->register_method(
    method    => 'fetch_captured_holds',
    api_name  => 'open-ils.circ.captured_holds.id_list.on_shelf.retrieve',
    stream    => 1,
    authoritative => 1,
    signature => q/
		Returns list ids of un-fulfilled holds (on the Holds Shelf) for a given title id
		@param authtoken The login session key
		@param org The org id of the location in question
		@param match_copy A specific copy to limit to
	/
);

__PACKAGE__->register_method(
    method    => 'fetch_captured_holds',
    api_name  => 'open-ils.circ.captured_holds.id_list.expired_on_shelf.retrieve',
    stream    => 1,
    authoritative => 1,
    signature => q/
		Returns list ids of shelf-expired un-fulfilled holds for a given title id
		@param authtoken The login session key
		@param org The org id of the location in question
		@param match_copy A specific copy to limit to
	/
);


sub fetch_captured_holds {
	my( $self, $conn, $auth, $org, $match_copy ) = @_;

	my $e = new_editor(authtoken => $auth);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('VIEW_HOLD'); # XXX rely on editor perm

	$org ||= $e->requestor->ws_ou;

	my $current_copy = { '!=' => undef };
	$current_copy = { '=' => $match_copy } if $match_copy;

    my $query = { 
        select => { alhr => ['id'] },
        from   => {
            alhr => {
                acp => {
                    field => 'id',
                    fkey  => 'current_copy'
                },
            }
        }, 
        where => {
            '+acp' => { status => OILS_COPY_STATUS_ON_HOLDS_SHELF },
            '+alhr' => {
                capture_time     => { "!=" => undef },
                current_copy     => $current_copy,
                fulfillment_time => undef,
                current_shelf_lib => $org
            }
        }
    };
    if($self->api_name =~ /expired/) {
        $query->{'where'}->{'+alhr'}->{'-or'} = {
                shelf_expire_time => { '<' => 'now'},
                cancel_time => { '!=' => undef },
        };
    }
    my $hold_ids = $e->json_query( $query );

    for my $hold_id (@$hold_ids) {
        if($self->api_name =~ /id_list/) {
            $conn->respond($hold_id->{id});
            next;
        } else {
            $conn->respond(
                $e->retrieve_action_hold_request([
                    $hold_id->{id},
                    {
                        flesh => 1,
                        flesh_fields => {ahr => ['notifications', 'transit', 'notes']},
                        order_by => {anh => 'notify_time desc'}
                    }
                ])
            );
        }
    }

    return undef;
}

__PACKAGE__->register_method(
    method    => "print_expired_holds_stream",
    api_name  => "open-ils.circ.captured_holds.expired.print.stream",
    stream    => 1
);

sub print_expired_holds_stream {
    my ($self, $client, $auth, $params) = @_;

    # No need to check specific permissions: we're going to call another method
    # that will do that.
    my $e = new_editor("authtoken" => $auth);
    return $e->die_event unless $e->checkauth;

    delete($$params{org_id}) unless (int($$params{org_id}));
    delete($$params{limit}) unless (int($$params{limit}));
    delete($$params{offset}) unless (int($$params{offset}));
    delete($$params{chunk_size}) unless (int($$params{chunk_size}));
    delete($$params{chunk_size}) if  ($$params{chunk_size} && $$params{chunk_size} > 50); # keep the size reasonable
    $$params{chunk_size} ||= 10;

    $$params{org_id} = (defined $$params{org_id}) ? $$params{org_id}: $e->requestor->ws_ou;

    my @hold_ids = $self->method_lookup(
        "open-ils.circ.captured_holds.id_list.expired_on_shelf.retrieve"
    )->run($auth, $params->{"org_id"});

    if (!@hold_ids) {
        $e->disconnect;
        return;
    } elsif (defined $U->event_code($hold_ids[0])) {
        $e->disconnect;
        return $hold_ids[0];
    }

    $logger->info("about to stream back up to " . scalar(@hold_ids) . " expired holds");

    while (@hold_ids) {
        my @hid_chunk = splice @hold_ids, 0, $params->{"chunk_size"};

        my $result_chunk = $e->json_query({
            "select" => {
                "acp" => ["barcode"],
                "au" => [qw/
                    first_given_name second_given_name family_name alias
                /],
                "acn" => ["label"],
                "bre" => ["marc"],
                "acpl" => ["name"]
            },
            "from" => {
                "ahr" => {
                    "acp" => {
                        "field" => "id", "fkey" => "current_copy",
                        "join" => {
                            "acn" => {
                                "field" => "id", "fkey" => "call_number",
                                "join" => {
                                    "bre" => {
                                        "field" => "id", "fkey" => "record"
                                    }
                                }
                            },
                            "acpl" => {"field" => "id", "fkey" => "location"}
                        }
                    },
                    "au" => {"field" => "id", "fkey" => "usr"}
                }
            },
            "where" => {"+ahr" => {"id" => \@hid_chunk}}
        }) or return $e->die_event;
        $client->respond($result_chunk);
    }

    $e->disconnect;
    undef;
}

__PACKAGE__->register_method(
    method    => "check_title_hold_batch",
    api_name  => "open-ils.circ.title_hold.is_possible.batch",
    stream    => 1,
    signature => {
        desc  => '@see open-ils.circ.title_hold.is_possible.batch',
        params => [
            { desc => 'Authentication token',     type => 'string'},
            { desc => 'Array of Hash of named parameters', type => 'array'},
        ],
        return => {
            desc => 'Array of response objects',
            type => 'array'
        }
    }
);

sub check_title_hold_batch {
    my($self, $client, $authtoken, $param_list, $oargs) = @_;
    foreach (@$param_list) {
        my ($res) = $self->method_lookup('open-ils.circ.title_hold.is_possible')->run($authtoken, $_, $oargs);
        $client->respond($res);
    }
    return undef;
}


__PACKAGE__->register_method(
    method    => "check_title_hold",
    api_name  => "open-ils.circ.title_hold.is_possible",
    signature => {
        desc  => 'Determines if a hold were to be placed by a given user, ' .
             'whether or not said hold would have any potential copies to fulfill it.' .
             'The named paramaters of the second argument include: ' .
             'patronid, titleid, volume_id, copy_id, mrid, depth, pickup_lib, hold_type, selection_ou. ' .
             'See perldoc ' . __PACKAGE__ . ' for more info on these fields.' , 
        params => [
            { desc => 'Authentication token',     type => 'string'},
            { desc => 'Hash of named parameters', type => 'object'},
        ],
        return => {
            desc => 'List of new message IDs (empty if none)',
            type => 'array'
        }
    }
);

=head3 check_title_hold (token, hash)

The named fields in the hash are: 

 patronid     - ID of the hold recipient  (required)
 depth        - hold range depth          (default 0)
 pickup_lib   - destination for hold, fallback value for selection_ou
 selection_ou - ID of org_unit establishing hard and soft hold boundary settings
 issuanceid   - ID of the issuance to be held, required for Issuance level hold
 partid       - ID of the monograph part to be held, required for monograph part level hold
 titleid      - ID (BRN) of the title to be held, required for Title level hold
 volume_id    - required for Volume level hold
 copy_id      - required for Copy level hold
 mrid         - required for Meta-record level hold
 hold_type    - T, C (or R or F), I, V or M for Title, Copy, Issuance, Volume or Meta-record  (default "T")

All key/value pairs are passed on to do_possibility_checks.

=cut

# FIXME: better params checking.  what other params are required, if any?
# FIXME: 3 copies of values confusing: $x, $params->{x} and $params{x}
# FIXME: for example, $depth gets a default value, but then $$params{depth} is still 
# used in conditionals, where it may be undefined, causing a warning.
# FIXME: specify proper usage/interaction of selection_ou and pickup_lib

sub check_title_hold {
    my( $self, $client, $authtoken, $params ) = @_;
    my $e = new_editor(authtoken=>$authtoken);
    return $e->event unless $e->checkauth;

    my %params       = %$params;
    my $depth        = $params{depth}        || 0;
    my $selection_ou = $params{selection_ou} || $params{pickup_lib};
    my $oargs        = $params{oargs}        || {};

    if($oargs->{events}) {
        @{$oargs->{events}} = grep { $e->allowed($_ . '.override', $e->requestor->ws_ou); } @{$oargs->{events}};
    }


	my $patron = $e->retrieve_actor_user($params{patronid})
		or return $e->event;

	if( $e->requestor->id ne $patron->id ) {
		return $e->event unless 
			$e->allowed('VIEW_HOLD_PERMIT', $patron->home_ou);
	}

	return OpenILS::Event->new('PATRON_BARRED') if $U->is_true($patron->barred);

	my $request_lib = $e->retrieve_actor_org_unit($e->requestor->ws_ou)
		or return $e->event;

    my $soft_boundary = $U->ou_ancestor_setting_value($selection_ou, OILS_SETTING_HOLD_SOFT_BOUNDARY);
    my $hard_boundary = $U->ou_ancestor_setting_value($selection_ou, OILS_SETTING_HOLD_HARD_BOUNDARY);

    my @status = ();
    my $return_depth = $hard_boundary; # default depth to return on success
    if(defined $soft_boundary and $depth < $soft_boundary) {
        # work up the tree and as soon as we find a potential copy, use that depth
        # also, make sure we don't go past the hard boundary if it exists

        # our min boundary is the greater of user-specified boundary or hard boundary
        my $min_depth = (defined $hard_boundary and $hard_boundary > $depth) ?  
            $hard_boundary : $depth;

        my $depth = $soft_boundary;
        while($depth >= $min_depth) {
            $logger->info("performing hold possibility check with soft boundary $depth");
            @status = do_possibility_checks($e, $patron, $request_lib, $depth, %params);
            if ($status[0]) {
                $return_depth = $depth;
                last;
            }
            $depth--;
        }
    } elsif(defined $hard_boundary and $depth < $hard_boundary) {
        # there is no soft boundary, enforce the hard boundary if it exists
        $logger->info("performing hold possibility check with hard boundary $hard_boundary");
        @status = do_possibility_checks($e, $patron, $request_lib, $hard_boundary, %params);
    } else {
        # no boundaries defined, fall back to user specifed boundary or no boundary
        $logger->info("performing hold possibility check with no boundary");
        @status = do_possibility_checks($e, $patron, $request_lib, $params{depth}, %params);
    }

    my $place_unfillable = 0;
    $place_unfillable = 1 if $e->allowed('PLACE_UNFILLABLE_HOLD', $e->requestor->ws_ou);

    if ($status[0]) {
        return {
            "success" => 1,
            "depth" => $return_depth,
            "local_avail" => $status[1]
        };
    } elsif ($status[2]) {
        my $n = scalar @{$status[2]};
        return {"success" => 0, "last_event" => $status[2]->[$n - 1], "age_protected_copy" => $status[3], "place_unfillable" => $place_unfillable};
    } else {
        return {"success" => 0, "age_protected_copy" => $status[3], "place_unfillable" => $place_unfillable};
    }
}



sub do_possibility_checks {
    my($e, $patron, $request_lib, $depth, %params) = @_;

    my $issuanceid   = $params{issuanceid}      || "";
    my $partid       = $params{partid}      || "";
    my $titleid      = $params{titleid}      || "";
    my $volid        = $params{volume_id};
    my $copyid       = $params{copy_id};
    my $mrid         = $params{mrid}         || "";
    my $pickup_lib   = $params{pickup_lib};
    my $hold_type    = $params{hold_type}    || 'T';
    my $selection_ou = $params{selection_ou} || $pickup_lib;
    my $holdable_formats = $params{holdable_formats};
    my $oargs        = $params{oargs}        || {};


	my $copy;
	my $volume;
	my $title;

	if( $hold_type eq OILS_HOLD_TYPE_FORCE || $hold_type eq OILS_HOLD_TYPE_RECALL || $hold_type eq OILS_HOLD_TYPE_COPY ) {

        return $e->event unless $copy   = $e->retrieve_asset_copy($copyid);
        return $e->event unless $volume = $e->retrieve_asset_call_number($copy->call_number);
        return $e->event unless $title  = $e->retrieve_biblio_record_entry($volume->record);

        return (1, 1, []) if( $hold_type eq OILS_HOLD_TYPE_RECALL || $hold_type eq OILS_HOLD_TYPE_FORCE);
        return verify_copy_for_hold( 
            $patron, $e->requestor, $title, $copy, $pickup_lib, $request_lib, $oargs
        );

	} elsif( $hold_type eq OILS_HOLD_TYPE_VOLUME ) {

		return $e->event unless $volume = $e->retrieve_asset_call_number($volid);
		return $e->event unless $title  = $e->retrieve_biblio_record_entry($volume->record);

		return _check_volume_hold_is_possible(
			$volume, $title, $depth, $request_lib, $patron, $e->requestor, $pickup_lib, $selection_ou, $oargs
        );

	} elsif( $hold_type eq OILS_HOLD_TYPE_TITLE ) {

		return _check_title_hold_is_possible(
			$titleid, $depth, $request_lib, $patron, $e->requestor, $pickup_lib, $selection_ou, undef, $oargs
        );

	} elsif( $hold_type eq OILS_HOLD_TYPE_ISSUANCE ) {

		return _check_issuance_hold_is_possible(
			$issuanceid, $depth, $request_lib, $patron, $e->requestor, $pickup_lib, $selection_ou, $oargs
        );

	} elsif( $hold_type eq OILS_HOLD_TYPE_MONOPART ) {

		return _check_monopart_hold_is_possible(
			$partid, $depth, $request_lib, $patron, $e->requestor, $pickup_lib, $selection_ou, $oargs
        );

	} elsif( $hold_type eq OILS_HOLD_TYPE_METARECORD ) {

		my $maps = $e->search_metabib_metarecord_source_map({metarecord=>$mrid});
		my @recs = map { $_->source } @$maps;
		my @status = ();
		for my $rec (@recs) {
			@status = _check_title_hold_is_possible(
				$rec, $depth, $request_lib, $patron, $e->requestor, $pickup_lib, $selection_ou, $holdable_formats, $oargs
			);
			last if $status[0];
		}
		return @status;
	}
#   else { Unrecognized hold_type ! }   # FIXME: return error? or 0?
}

my %prox_cache;
sub create_ranged_org_filter {
    my($e, $selection_ou, $depth) = @_;

    # find the orgs from which this hold may be fulfilled, 
    # based on the selection_ou and depth

    my $top_org = $e->search_actor_org_unit([
        {parent_ou => undef}, 
        {flesh=>1, flesh_fields=>{aou=>['ou_type']}}])->[0];
    my %org_filter;

    return () if $depth == $top_org->ou_type->depth;

    my $org_list = $U->storagereq('open-ils.storage.actor.org_unit.descendants.atomic', $selection_ou, $depth);
    %org_filter = (circ_lib => []);
    push(@{$org_filter{circ_lib}}, $_->id) for @$org_list;

    $logger->info("hold org filter at depth $depth and selection_ou ".
        "$selection_ou created list of @{$org_filter{circ_lib}}");

    return %org_filter;
}


sub _check_title_hold_is_possible {
    my( $titleid, $depth, $request_lib, $patron, $requestor, $pickup_lib, $selection_ou, $holdable_formats, $oargs ) = @_;
   
    my ($types, $formats, $lang);
    if (defined($holdable_formats)) {
        ($types, $formats, $lang) = split '-', $holdable_formats;
    }

    my $e = new_editor();
    my %org_filter = create_ranged_org_filter($e, $selection_ou, $depth);

    # this monster will grab the id and circ_lib of all of the "holdable" copies for the given record
    my $copies = $e->json_query(
        { 
            select => { acp => ['id', 'circ_lib'] },
              from => {
                acp => {
                    acn => {
                        field  => 'id',
                        fkey   => 'call_number',
                        'join' => {
                            bre => {
                                field  => 'id',
                                filter => { id => $titleid },
                                fkey   => 'record'
                            },
                            mrd => {
                                field  => 'record',
                                fkey   => 'record',
                                filter => {
                                    record => $titleid,
                                    ( $types   ? (item_type => [split '', $types])   : () ),
                                    ( $formats ? (item_form => [split '', $formats]) : () ),
                                    ( $lang    ? (item_lang => $lang)                : () )
                                }
                            }
                        }
                    },
                    acpl => { field => 'id', filter => { holdable => 't'}, fkey => 'location' },
                    ccs  => { field => 'id', filter => { holdable => 't'}, fkey => 'status'   },
                    acpm => { field => 'target_copy', type => 'left' } # ignore part-linked copies
                }
            }, 
            where => {
                '+acp' => { circulate => 't', deleted => 'f', holdable => 't', %org_filter },
                '+acpm' => { target_copy => undef } # ignore part-linked copies
            }
        }
    );

    $logger->info("title possible found ".scalar(@$copies)." potential copies");
    return (
        0, 0, [
            new OpenILS::Event(
                "HIGH_LEVEL_HOLD_HAS_NO_COPIES",
                "payload" => {"fail_part" => "no_ultimate_items"}
            )
        ]
    ) unless @$copies;

    # -----------------------------------------------------------------------
    # sort the copies into buckets based on their circ_lib proximity to 
    # the patron's home_ou.  
    # -----------------------------------------------------------------------

    my $home_org = $patron->home_ou;
    my $req_org = $request_lib->id;

    $logger->info("prox cache $home_org " . $prox_cache{$home_org});

    $prox_cache{$home_org} = 
        $e->search_actor_org_unit_proximity({from_org => $home_org})
        unless $prox_cache{$home_org};
    my $home_prox = $prox_cache{$home_org};

    my %buckets;
    my %hash = map { ($_->to_org => $_->prox) } @$home_prox;
    push( @{$buckets{ $hash{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

    my @keys = sort { $a <=> $b } keys %buckets;


    if( $home_org ne $req_org ) {
      # -----------------------------------------------------------------------
      # shove the copies close to the request_lib into the primary buckets 
      # directly before the farthest away copies.  That way, they are not 
      # given priority, but they are checked before the farthest copies.
      # -----------------------------------------------------------------------
        $prox_cache{$req_org} = 
            $e->search_actor_org_unit_proximity({from_org => $req_org})
            unless $prox_cache{$req_org};
        my $req_prox = $prox_cache{$req_org};

        my %buckets2;
        my %hash2 = map { ($_->to_org => $_->prox) } @$req_prox;
        push( @{$buckets2{ $hash2{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

        my $highest_key = $keys[@keys - 1];  # the farthest prox in the exising buckets
        my $new_key = $highest_key - 0.5; # right before the farthest prox
        my @keys2   = sort { $a <=> $b } keys %buckets2;
        for my $key (@keys2) {
            last if $key >= $highest_key;
            push( @{$buckets{$new_key}}, $_ ) for @{$buckets2{$key}};
        }
    }

    @keys = sort { $a <=> $b } keys %buckets;

    my $title;
    my %seen;
    my @status;
    my $age_protect_only = 0;
    OUTER: for my $key (@keys) {
      my @cps = @{$buckets{$key}};

      $logger->info("looking at " . scalar(@{$buckets{$key}}). " copies in proximity bucket $key");

      for my $copyid (@cps) {

         next if $seen{$copyid};
         $seen{$copyid} = 1; # there could be dupes given the merged buckets
         my $copy = $e->retrieve_asset_copy($copyid);
         $logger->debug("looking at bucket_key=$key, copy $copyid : circ_lib = " . $copy->circ_lib);

         unless($title) { # grab the title if we don't already have it
            my $vol = $e->retrieve_asset_call_number(
               [ $copy->call_number, { flesh => 1, flesh_fields => { bre => ['fixed_fields'], acn => ['record'] } } ] );
            $title = $vol->record;
         }
   
         @status = verify_copy_for_hold(
            $patron, $requestor, $title, $copy, $pickup_lib, $request_lib, $oargs);

         $age_protect_only ||= $status[3];
         last OUTER if $status[0];
      }
    }

    $status[3] = $age_protect_only;
    return @status;
}

sub _check_issuance_hold_is_possible {
    my( $issuanceid, $depth, $request_lib, $patron, $requestor, $pickup_lib, $selection_ou, $oargs ) = @_;
   
    my $e = new_editor();
    my %org_filter = create_ranged_org_filter($e, $selection_ou, $depth);

    # this monster will grab the id and circ_lib of all of the "holdable" copies for the given record
    my $copies = $e->json_query(
        { 
            select => { acp => ['id', 'circ_lib'] },
              from => {
                acp => {
                    sitem => {
                        field  => 'unit',
                        fkey   => 'id',
                        filter => { issuance => $issuanceid }
                    },
                    acpl => { field => 'id', filter => { holdable => 't'}, fkey => 'location' },
                    ccs  => { field => 'id', filter => { holdable => 't'}, fkey => 'status'   }
                }
            }, 
            where => {
                '+acp' => { circulate => 't', deleted => 'f', holdable => 't', %org_filter }
            },
            distinct => 1
        }
    );

    $logger->info("issuance possible found ".scalar(@$copies)." potential copies");

    my $empty_ok;
    if (!@$copies) {
        $empty_ok = $e->retrieve_config_global_flag('circ.holds.empty_issuance_ok');
        $empty_ok = ($empty_ok and $U->is_true($empty_ok->enabled));

        return (
            0, 0, [
                new OpenILS::Event(
                    "HIGH_LEVEL_HOLD_HAS_NO_COPIES",
                    "payload" => {"fail_part" => "no_ultimate_items"}
                )
            ]
        ) unless $empty_ok;

        return (1, 0);
    }

    # -----------------------------------------------------------------------
    # sort the copies into buckets based on their circ_lib proximity to 
    # the patron's home_ou.  
    # -----------------------------------------------------------------------

    my $home_org = $patron->home_ou;
    my $req_org = $request_lib->id;

    $logger->info("prox cache $home_org " . $prox_cache{$home_org});

    $prox_cache{$home_org} = 
        $e->search_actor_org_unit_proximity({from_org => $home_org})
        unless $prox_cache{$home_org};
    my $home_prox = $prox_cache{$home_org};

    my %buckets;
    my %hash = map { ($_->to_org => $_->prox) } @$home_prox;
    push( @{$buckets{ $hash{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

    my @keys = sort { $a <=> $b } keys %buckets;


    if( $home_org ne $req_org ) {
      # -----------------------------------------------------------------------
      # shove the copies close to the request_lib into the primary buckets 
      # directly before the farthest away copies.  That way, they are not 
      # given priority, but they are checked before the farthest copies.
      # -----------------------------------------------------------------------
        $prox_cache{$req_org} = 
            $e->search_actor_org_unit_proximity({from_org => $req_org})
            unless $prox_cache{$req_org};
        my $req_prox = $prox_cache{$req_org};

        my %buckets2;
        my %hash2 = map { ($_->to_org => $_->prox) } @$req_prox;
        push( @{$buckets2{ $hash2{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

        my $highest_key = $keys[@keys - 1];  # the farthest prox in the exising buckets
        my $new_key = $highest_key - 0.5; # right before the farthest prox
        my @keys2   = sort { $a <=> $b } keys %buckets2;
        for my $key (@keys2) {
            last if $key >= $highest_key;
            push( @{$buckets{$new_key}}, $_ ) for @{$buckets2{$key}};
        }
    }

    @keys = sort { $a <=> $b } keys %buckets;

    my $title;
    my %seen;
    my @status;
    my $age_protect_only = 0;
    OUTER: for my $key (@keys) {
      my @cps = @{$buckets{$key}};

      $logger->info("looking at " . scalar(@{$buckets{$key}}). " copies in proximity bucket $key");

      for my $copyid (@cps) {

         next if $seen{$copyid};
         $seen{$copyid} = 1; # there could be dupes given the merged buckets
         my $copy = $e->retrieve_asset_copy($copyid);
         $logger->debug("looking at bucket_key=$key, copy $copyid : circ_lib = " . $copy->circ_lib);

         unless($title) { # grab the title if we don't already have it
            my $vol = $e->retrieve_asset_call_number(
               [ $copy->call_number, { flesh => 1, flesh_fields => { bre => ['fixed_fields'], acn => ['record'] } } ] );
            $title = $vol->record;
         }
   
         @status = verify_copy_for_hold(
            $patron, $requestor, $title, $copy, $pickup_lib, $request_lib, $oargs);

         $age_protect_only ||= $status[3];
         last OUTER if $status[0];
      }
    }

    if (!$status[0]) {
        if (!defined($empty_ok)) {
            $empty_ok = $e->retrieve_config_global_flag('circ.holds.empty_issuance_ok');
            $empty_ok = ($empty_ok and $U->is_true($empty_ok->enabled));
        }

        return (1,0) if ($empty_ok);
    }
    $status[3] = $age_protect_only;
    return @status;
}

sub _check_monopart_hold_is_possible {
    my( $partid, $depth, $request_lib, $patron, $requestor, $pickup_lib, $selection_ou, $oargs ) = @_;
   
    my $e = new_editor();
    my %org_filter = create_ranged_org_filter($e, $selection_ou, $depth);

    # this monster will grab the id and circ_lib of all of the "holdable" copies for the given record
    my $copies = $e->json_query(
        { 
            select => { acp => ['id', 'circ_lib'] },
              from => {
                acp => {
                    acpm => {
                        field  => 'target_copy',
                        fkey   => 'id',
                        filter => { part => $partid }
                    },
                    acpl => { field => 'id', filter => { holdable => 't'}, fkey => 'location' },
                    ccs  => { field => 'id', filter => { holdable => 't'}, fkey => 'status'   }
                }
            }, 
            where => {
                '+acp' => { circulate => 't', deleted => 'f', holdable => 't', %org_filter }
            },
            distinct => 1
        }
    );

    $logger->info("monopart possible found ".scalar(@$copies)." potential copies");

    my $empty_ok;
    if (!@$copies) {
        $empty_ok = $e->retrieve_config_global_flag('circ.holds.empty_part_ok');
        $empty_ok = ($empty_ok and $U->is_true($empty_ok->enabled));

        return (
            0, 0, [
                new OpenILS::Event(
                    "HIGH_LEVEL_HOLD_HAS_NO_COPIES",
                    "payload" => {"fail_part" => "no_ultimate_items"}
                )
            ]
        ) unless $empty_ok;

        return (1, 0);
    }

    # -----------------------------------------------------------------------
    # sort the copies into buckets based on their circ_lib proximity to 
    # the patron's home_ou.  
    # -----------------------------------------------------------------------

    my $home_org = $patron->home_ou;
    my $req_org = $request_lib->id;

    $logger->info("prox cache $home_org " . $prox_cache{$home_org});

    $prox_cache{$home_org} = 
        $e->search_actor_org_unit_proximity({from_org => $home_org})
        unless $prox_cache{$home_org};
    my $home_prox = $prox_cache{$home_org};

    my %buckets;
    my %hash = map { ($_->to_org => $_->prox) } @$home_prox;
    push( @{$buckets{ $hash{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

    my @keys = sort { $a <=> $b } keys %buckets;


    if( $home_org ne $req_org ) {
      # -----------------------------------------------------------------------
      # shove the copies close to the request_lib into the primary buckets 
      # directly before the farthest away copies.  That way, they are not 
      # given priority, but they are checked before the farthest copies.
      # -----------------------------------------------------------------------
        $prox_cache{$req_org} = 
            $e->search_actor_org_unit_proximity({from_org => $req_org})
            unless $prox_cache{$req_org};
        my $req_prox = $prox_cache{$req_org};

        my %buckets2;
        my %hash2 = map { ($_->to_org => $_->prox) } @$req_prox;
        push( @{$buckets2{ $hash2{$_->{circ_lib}} } }, $_->{id} ) for @$copies;

        my $highest_key = $keys[@keys - 1];  # the farthest prox in the exising buckets
        my $new_key = $highest_key - 0.5; # right before the farthest prox
        my @keys2   = sort { $a <=> $b } keys %buckets2;
        for my $key (@keys2) {
            last if $key >= $highest_key;
            push( @{$buckets{$new_key}}, $_ ) for @{$buckets2{$key}};
        }
    }

    @keys = sort { $a <=> $b } keys %buckets;

    my $title;
    my %seen;
    my @status;
    my $age_protect_only = 0;
    OUTER: for my $key (@keys) {
      my @cps = @{$buckets{$key}};

      $logger->info("looking at " . scalar(@{$buckets{$key}}). " copies in proximity bucket $key");

      for my $copyid (@cps) {

         next if $seen{$copyid};
         $seen{$copyid} = 1; # there could be dupes given the merged buckets
         my $copy = $e->retrieve_asset_copy($copyid);
         $logger->debug("looking at bucket_key=$key, copy $copyid : circ_lib = " . $copy->circ_lib);

         unless($title) { # grab the title if we don't already have it
            my $vol = $e->retrieve_asset_call_number(
               [ $copy->call_number, { flesh => 1, flesh_fields => { bre => ['fixed_fields'], acn => ['record'] } } ] );
            $title = $vol->record;
         }
   
         @status = verify_copy_for_hold(
            $patron, $requestor, $title, $copy, $pickup_lib, $request_lib, $oargs);

         $age_protect_only ||= $status[3];
         last OUTER if $status[0];
      }
    }

    if (!$status[0]) {
        if (!defined($empty_ok)) {
            $empty_ok = $e->retrieve_config_global_flag('circ.holds.empty_part_ok');
            $empty_ok = ($empty_ok and $U->is_true($empty_ok->enabled));
        }

        return (1,0) if ($empty_ok);
    }
    $status[3] = $age_protect_only;
    return @status;
}


sub _check_volume_hold_is_possible {
	my( $vol, $title, $depth, $request_lib, $patron, $requestor, $pickup_lib, $selection_ou, $oargs ) = @_;
    my %org_filter = create_ranged_org_filter(new_editor(), $selection_ou, $depth);
	my $copies = new_editor->search_asset_copy({call_number => $vol->id, %org_filter});
	$logger->info("checking possibility of volume hold for volume ".$vol->id);

    my $filter_copies = [];
    for my $copy (@$copies) {
        # ignore part-mapped copies for regular volume level holds
        push(@$filter_copies, $copy) unless
            new_editor->search_asset_copy_part_map({target_copy => $copy->id})->[0];
    }
    $copies = $filter_copies;

    return (
        0, 0, [
            new OpenILS::Event(
                "HIGH_LEVEL_HOLD_HAS_NO_COPIES",
                "payload" => {"fail_part" => "no_ultimate_items"}
            )
        ]
    ) unless @$copies;

    my @status;
    my $age_protect_only = 0;
	for my $copy ( @$copies ) {
        @status = verify_copy_for_hold(
			$patron, $requestor, $title, $copy, $pickup_lib, $request_lib, $oargs );
        $age_protect_only ||= $status[3];
        last if $status[0];
	}
    $status[3] = $age_protect_only;
	return @status;
}



sub verify_copy_for_hold {
	my( $patron, $requestor, $title, $copy, $pickup_lib, $request_lib, $oargs ) = @_;
    $oargs = {} unless defined $oargs;
	$logger->info("checking possibility of copy in hold request for copy ".$copy->id);
    my $permitted = OpenILS::Utils::PermitHold::permit_copy_hold(
		{	patron				=> $patron, 
			requestor			=> $requestor, 
			copy				=> $copy,
			title				=> $title, 
			title_descriptor	=> $title->fixed_fields, # this is fleshed into the title object
			pickup_lib			=> $pickup_lib,
			request_lib			=> $request_lib,
            new_hold            => 1,
            show_event_list     => 1
		} 
	);

    # All overridden?
    my $permit_anyway = 0;
    foreach my $permit_event (@$permitted) {
        if (grep { $_ eq $permit_event->{textcode} } @{$oargs->{events}}) {
            $permit_anyway = 1;
            last;
        }
    }
    $permitted = [] if $permit_anyway;

    my $age_protect_only = 0;
    if (@$permitted == 1 && @$permitted[0]->{textcode} eq 'ITEM_AGE_PROTECTED') {
        $age_protect_only = 1;
    }

    return (
        (not scalar @$permitted), # true if permitted is an empty arrayref
        (   # XXX This test is of very dubious value; someone should figure
            # out what if anything is checking this value
	        ($copy->circ_lib == $pickup_lib) and 
            ($copy->status == OILS_COPY_STATUS_AVAILABLE)
        ),
        $permitted,
        $age_protect_only
    );
}



sub find_nearest_permitted_hold {

    my $class  = shift;
    my $editor = shift;     # CStoreEditor object
    my $copy   = shift;     # copy to target
    my $user   = shift;     # staff
    my $check_only = shift; # do no updates, just see if the copy could fulfill a hold
      
    my $evt = OpenILS::Event->new('ACTION_HOLD_REQUEST_NOT_FOUND');

    my $bc = $copy->barcode;

	# find any existing holds that already target this copy
	my $old_holds = $editor->search_action_hold_request(
		{	current_copy => $copy->id, 
			cancel_time  => undef, 
			capture_time => undef 
		} 
	);

    my $hold_stall_interval = $U->ou_ancestor_setting_value($user->ws_ou, OILS_SETTING_HOLD_SOFT_STALL);

	$logger->info("circulator: searching for best hold at org ".$user->ws_ou.
        " and copy $bc with a hold stalling interval of ". ($hold_stall_interval || "(none)"));

	my $fifo = $U->ou_ancestor_setting_value($user->ws_ou, 'circ.holds_fifo');

	# search for what should be the best holds for this copy to fulfill
	my $best_holds = $U->storagereq(
        "open-ils.storage.action.hold_request.nearest_hold.atomic", 
		$user->ws_ou, $copy->id, 100, $hold_stall_interval, $fifo );

	# Add any pre-targeted holds to the list too? Unless they are already there, anyway.
	if ($old_holds) {
		for my $holdid (@$old_holds) {
			next unless $holdid;
			push(@$best_holds, $holdid) unless ( grep { ''.$holdid eq ''.$_ } @$best_holds );
		}
	}

	unless(@$best_holds) {
		$logger->info("circulator: no suitable holds found for copy $bc");
		return (undef, $evt);
	}


	my $best_hold;

	# for each potential hold, we have to run the permit script
	# to make sure the hold is actually permitted.
    my %reqr_cache;
    my %org_cache;
	for my $holdid (@$best_holds) {
		next unless $holdid;
		$logger->info("circulator: checking if hold $holdid is permitted for copy $bc");

		my $hold = $editor->retrieve_action_hold_request($holdid) or next;
		my $reqr = $reqr_cache{$hold->requestor} || $editor->retrieve_actor_user($hold->requestor);
		my $rlib = $org_cache{$hold->request_lib} || $editor->retrieve_actor_org_unit($hold->request_lib);

		$reqr_cache{$hold->requestor} = $reqr;
		$org_cache{$hold->request_lib} = $rlib;

		# see if this hold is permitted
		my $permitted = OpenILS::Utils::PermitHold::permit_copy_hold(
			{	patron_id			=> $hold->usr,
				requestor			=> $reqr,
				copy				=> $copy,
				pickup_lib			=> $hold->pickup_lib,
				request_lib			=> $rlib,
				retarget			=> 1
			} 
		);

		if( $permitted ) {
			$best_hold = $hold;
			last;
		}
	}


	unless( $best_hold ) { # no "good" permitted holds were found
		# we got nuthin
		$logger->info("circulator: no suitable holds found for copy $bc");
		return (undef, $evt);
	}

	$logger->info("circulator: best hold ".$best_hold->id." found for copy $bc");

	# indicate a permitted hold was found
	return $best_hold if $check_only;

	# we've found a permitted hold.  we need to "grab" the copy 
	# to prevent re-targeted holds (next part) from re-grabbing the copy
	$best_hold->current_copy($copy->id);
	$editor->update_action_hold_request($best_hold) 
		or return (undef, $editor->event);


    my @retarget;

	# re-target any other holds that already target this copy
	for my $old_hold (@$old_holds) {
		next if $old_hold->id eq $best_hold->id; # don't re-target the hold we want
		$logger->info("circulator: clearing current_copy and prev_check_time on hold ".
            $old_hold->id." after a better hold [".$best_hold->id."] was found");
        $old_hold->clear_current_copy;
        $old_hold->clear_prev_check_time;
        $editor->update_action_hold_request($old_hold) 
            or return (undef, $editor->event);
        push(@retarget, $old_hold->id);
	}

	return ($best_hold, undef, (@retarget) ? \@retarget : undef);
}






__PACKAGE__->register_method(
    method   => 'all_rec_holds',
    api_name => 'open-ils.circ.holds.retrieve_all_from_title',
);

sub all_rec_holds {
	my( $self, $conn, $auth, $title_id, $args ) = @_;

	my $e = new_editor(authtoken=>$auth);
	$e->checkauth or return $e->event;
	$e->allowed('VIEW_HOLD') or return $e->event;

	$args ||= {};
    $args->{fulfillment_time} = undef; #  we don't want to see old fulfilled holds
	$args->{cancel_time} = undef;

	my $resp = { volume_holds => [], copy_holds => [], recall_holds => [], force_holds => [], metarecord_holds => [], part_holds => [], issuance_holds => [] };

    my $mr_map = $e->search_metabib_metarecord_source_map({source => $title_id})->[0];
    if($mr_map) {
        $resp->{metarecord_holds} = $e->search_action_hold_request(
            {   hold_type => OILS_HOLD_TYPE_METARECORD,
                target => $mr_map->metarecord,
                %$args 
            }, {idlist => 1}
        );
    }

	$resp->{title_holds} = $e->search_action_hold_request(
		{ 
			hold_type => OILS_HOLD_TYPE_TITLE, 
			target => $title_id, 
			%$args 
		}, {idlist=>1} );

    my $parts = $e->search_biblio_monograph_part(
        {
            record => $title_id
        }, {idlist=>1} );

    if (@$parts) {
        $resp->{part_holds} = $e->search_action_hold_request(
            {
                hold_type => OILS_HOLD_TYPE_MONOPART,
                target => $parts,
                %$args
            }, {idlist=>1} );
    }

    my $subs = $e->search_serial_subscription(
        { record_entry => $title_id }, {idlist=>1});

    if (@$subs) {
        my $issuances = $e->search_serial_issuance(
            {subscription => $subs}, {idlist=>1}
        );

        if ($issuances) {
            $resp->{issuance_holds} = $e->search_action_hold_request(
                {
                    hold_type => OILS_HOLD_TYPE_ISSUANCE,
                    target => $issuances,
                    %$args
                }, {idlist=>1}
            );
        }
    }

	my $vols = $e->search_asset_call_number(
		{ record => $title_id, deleted => 'f' }, {idlist=>1});

	return $resp unless @$vols;

	$resp->{volume_holds} = $e->search_action_hold_request(
		{ 
			hold_type => OILS_HOLD_TYPE_VOLUME, 
			target => $vols,
			%$args }, 
		{idlist=>1} );

	my $copies = $e->search_asset_copy(
		{ call_number => $vols, deleted => 'f' }, {idlist=>1});

	return $resp unless @$copies;

	$resp->{copy_holds} = $e->search_action_hold_request(
		{ 
			hold_type => OILS_HOLD_TYPE_COPY,
			target => $copies,
			%$args }, 
		{idlist=>1} );

	$resp->{recall_holds} = $e->search_action_hold_request(
		{ 
			hold_type => OILS_HOLD_TYPE_RECALL,
			target => $copies,
			%$args }, 
		{idlist=>1} );

	$resp->{force_holds} = $e->search_action_hold_request(
		{ 
			hold_type => OILS_HOLD_TYPE_FORCE,
			target => $copies,
			%$args }, 
		{idlist=>1} );

	return $resp;
}





__PACKAGE__->register_method(
    method        => 'uber_hold',
    authoritative => 1,
    api_name      => 'open-ils.circ.hold.details.retrieve'
);

sub uber_hold {
	my($self, $client, $auth, $hold_id, $args) = @_;
	my $e = new_editor(authtoken=>$auth);
	$e->checkauth or return $e->event;
    return uber_hold_impl($e, $hold_id, $args);
}

__PACKAGE__->register_method(
    method        => 'batch_uber_hold',
    authoritative => 1,
    stream        => 1,
    api_name      => 'open-ils.circ.hold.details.batch.retrieve'
);

sub batch_uber_hold {
	my($self, $client, $auth, $hold_ids, $args) = @_;
	my $e = new_editor(authtoken=>$auth);
	$e->checkauth or return $e->event;
    $client->respond(uber_hold_impl($e, $_, $args)) for @$hold_ids;
    return undef;
}

sub uber_hold_impl {
    my($e, $hold_id, $args) = @_;
    $args ||= {};

	my $hold = $e->retrieve_action_hold_request(
		[
			$hold_id,
			{
				flesh => 1,
				flesh_fields => { ahr => [ 'current_copy', 'usr', 'notes' ] }
			}
		]
	) or return $e->event;

    if($hold->usr->id ne $e->requestor->id) {
        # A user is allowed to see his/her own holds
	    $e->allowed('VIEW_HOLD') or return $e->event;
        $hold->notes( # filter out any non-staff ("private") notes
            [ grep { !$U->is_true($_->staff) } @{$hold->notes} ] );

    } else {
        # caller is asking for own hold, but may not have permission to view staff notes
	    unless($e->allowed('VIEW_HOLD')) {
            $hold->notes( # filter out any staff notes
                [ grep { $U->is_true($_->staff) } @{$hold->notes} ] );
        }
    }

	my $user = $hold->usr;
	$hold->usr($user->id);


	my( $mvr, $volume, $copy, $issuance, $part, $bre ) = find_hold_mvr($e, $hold, $args->{suppress_mvr});

	flesh_hold_notices([$hold], $e) unless $args->{suppress_notices};
	flesh_hold_transits([$hold]) unless $args->{suppress_transits};

    my $details = retrieve_hold_queue_status_impl($e, $hold);

    my $resp = {
        hold    => $hold,
        bre_id  => $bre->id,
        ($copy     ? (copy           => $copy)     : ()),
        ($volume   ? (volume         => $volume)   : ()),
        ($issuance ? (issuance       => $issuance) : ()),
        ($part     ? (part           => $part)     : ()),
        ($args->{include_bre}  ?  (bre => $bre)    : ()),
        ($args->{suppress_mvr} ?  () : (mvr => $mvr)),
        %$details
    };

    unless($args->{suppress_patron_details}) {
	    my $card = $e->retrieve_actor_card($user->card) or return $e->event;
        $resp->{patron_first}   = $user->first_given_name,
        $resp->{patron_last}    = $user->family_name,
        $resp->{patron_barcode} = $card->barcode,
        $resp->{patron_alias}   = $user->alias,
    };

    return $resp;
}



# -----------------------------------------------------
# Returns the MVR object that represents what the
# hold is all about
# -----------------------------------------------------
sub find_hold_mvr {
	my( $e, $hold, $no_mvr ) = @_;

	my $tid;
	my $copy;
	my $volume;
    my $issuance;
    my $part;

	if( $hold->hold_type eq OILS_HOLD_TYPE_METARECORD ) {
		my $mr = $e->retrieve_metabib_metarecord($hold->target)
			or return $e->event;
		$tid = $mr->master_record;

	} elsif( $hold->hold_type eq OILS_HOLD_TYPE_TITLE ) {
		$tid = $hold->target;

	} elsif( $hold->hold_type eq OILS_HOLD_TYPE_VOLUME ) {
		$volume = $e->retrieve_asset_call_number($hold->target)
			or return $e->event;
		$tid = $volume->record;

    } elsif( $hold->hold_type eq OILS_HOLD_TYPE_ISSUANCE ) {
        $issuance = $e->retrieve_serial_issuance([
            $hold->target,
            {flesh => 1, flesh_fields => {siss => [ qw/subscription/ ]}}
        ]) or return $e->event;

        $tid = $issuance->subscription->record_entry;

    } elsif( $hold->hold_type eq OILS_HOLD_TYPE_MONOPART ) {
        $part = $e->retrieve_biblio_monograph_part([
            $hold->target
        ]) or return $e->event;

        $tid = $part->record;

	} elsif( $hold->hold_type eq OILS_HOLD_TYPE_COPY || $hold->hold_type eq OILS_HOLD_TYPE_RECALL || $hold->hold_type eq OILS_HOLD_TYPE_FORCE ) {
		$copy = $e->retrieve_asset_copy([
            $hold->target, 
            {flesh => 1, flesh_fields => {acp => ['call_number']}}
        ]) or return $e->event;
        
		$volume = $copy->call_number;
		$tid = $volume->record;
	}

	if(!$copy and ref $hold->current_copy ) {
		$copy = $hold->current_copy;
		$hold->current_copy($copy->id);
	}

	if(!$volume and $copy) {
		$volume = $e->retrieve_asset_call_number($copy->call_number);
	}

    # TODO return metarcord mvr for M holds
	my $title = $e->retrieve_biblio_record_entry($tid);
	return ( ($no_mvr) ? undef : $U->record_to_mvr($title), $volume, $copy, $issuance, $part, $title );
}

__PACKAGE__->register_method(
    method    => 'clear_shelf_cache',
    api_name  => 'open-ils.circ.hold.clear_shelf.get_cache',
    stream    => 1,
    signature => {
        desc => q/
            Returns the holds processed with the given cache key
        /
    }
);

sub clear_shelf_cache {
    my($self, $client, $auth, $cache_key, $chunk_size) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth and $e->allowed('VIEW_HOLD');

    $chunk_size ||= 25;
    my $hold_data = OpenSRF::Utils::Cache->new('global')->get_cache($cache_key);

    if (!$hold_data) {
        $logger->info("no hold data found in cache"); # XXX TODO return event
        $e->rollback;
        return undef;
    }

    my $maximum = 0;
    foreach (keys %$hold_data) {
        $maximum += scalar(@{ $hold_data->{$_} });
    }
    $client->respond({"maximum" => $maximum, "progress" => 0});

    for my $action (sort keys %$hold_data) {
        while (@{$hold_data->{$action}}) {
            my @hid_chunk = splice @{$hold_data->{$action}}, 0, $chunk_size;

            my $result_chunk = $e->json_query({
                "select" => {
                    "acp" => ["barcode"],
                    "au" => [qw/
                        first_given_name second_given_name family_name alias
                    /],
                    "acn" => ["label"],
                    "acnp" => [{column => "label", alias => "prefix"}],
                    "acns" => [{column => "label", alias => "suffix"}],
                    "bre" => ["marc"],
                    "acpl" => ["name"],
                    "ahr" => ["id"]
                },
                "from" => {
                    "ahr" => {
                        "acp" => {
                            "field" => "id", "fkey" => "current_copy",
                            "join" => {
                                "acn" => {
                                    "field" => "id", "fkey" => "call_number",
                                    "join" => {
                                        "bre" => {
                                            "field" => "id", "fkey" => "record"
                                        },
                                        "acnp" => {
                                            "field" => "id", "fkey" => "prefix"
                                        },
                                        "acns" => {
                                            "field" => "id", "fkey" => "suffix"
                                        }
                                    }
                                },
                                "acpl" => {"field" => "id", "fkey" => "location"}
                            }
                        },
                        "au" => {"field" => "id", "fkey" => "usr"}
                    }
                },
                "where" => {"+ahr" => {"id" => \@hid_chunk}}
            }, {"substream" => 1}) or return $e->die_event;

            $client->respond([
                map {
                    +{"action" => $action, "hold_details" => $_}
                } @$result_chunk
            ]);
        }
    }

    $e->rollback;
    return undef;
}


__PACKAGE__->register_method(
    method    => 'clear_shelf_process',
    stream    => 1,
    api_name  => 'open-ils.circ.hold.clear_shelf.process',
    signature => {
        desc => q/
            1. Find all holds that have expired on the holds shelf
            2. Cancel the holds
            3. If a clear-shelf status is configured, put targeted copies into this status
            4. Divide copies into 3 groups: items to transit, items to reshelve, and items
                that are needed for holds.  No subsequent action is taken on the holds
                or items after grouping.
        /
    }
);

sub clear_shelf_process {
	my($self, $client, $auth, $org_id, $match_copy) = @_;

	my $e = new_editor(authtoken=>$auth, xact => 1);
	$e->checkauth or return $e->die_event;
	my $cache = OpenSRF::Utils::Cache->new('global');

    $org_id ||= $e->requestor->ws_ou;
	$e->allowed('UPDATE_HOLD', $org_id) or return $e->die_event;

    my $copy_status = $U->ou_ancestor_setting_value($org_id, 'circ.holds.clear_shelf.copy_status');

    my @hold_ids = $self->method_lookup(
        "open-ils.circ.captured_holds.id_list.expired_on_shelf.retrieve"
    )->run($auth, $org_id, $match_copy);

    my @holds;
    my @canceled_holds; # newly canceled holds
    my $chunk_size = 25; # chunked status updates
    my $counter = 0;
    for my $hold_id (@hold_ids) {

        $logger->info("Clear shelf processing hold $hold_id");
        
        my $hold = $e->retrieve_action_hold_request([
            $hold_id, {   
                flesh => 1,
                flesh_fields => {ahr => ['current_copy']}
            }
        ]);

        if (!$hold->cancel_time) { # may be canceled but still on the holds shelf
            $hold->cancel_time('now');
            $hold->cancel_cause(2); # Hold Shelf expiration
            $e->update_action_hold_request($hold) or return $e->die_event;
            delete_hold_copy_maps($self, $e, $hold->id) and return $e->die_event;
            push(@canceled_holds, $hold_id);
        }

        my $copy = $hold->current_copy;

        if($copy_status or $copy_status == 0) {
            # if a clear-shelf copy status is defined, update the copy
            $copy->status($copy_status);
            $copy->edit_date('now');
            $copy->editor($e->requestor->id);
            $e->update_asset_copy($copy) or return $e->die_event;
        }

        push(@holds, $hold);
        $client->respond({maximum => scalar(@holds), progress => $counter}) if ( (++$counter % $chunk_size) == 0);
    }

    if ($e->commit) {

        my %cache_data = (
            hold => [],
            transit => [],
            shelf => []
        );

        for my $hold (@holds) {

            my $copy = $hold->current_copy;
            my ($alt_hold) = __PACKAGE__->find_nearest_permitted_hold($e, $copy, $e->requestor, 1);

            if($alt_hold and !$match_copy) {

                push(@{$cache_data{hold}}, $hold->id); # copy is needed for a hold

            } elsif($copy->circ_lib != $e->requestor->ws_ou) {

                push(@{$cache_data{transit}}, $hold->id); # copy needs to transit

            } else {

                push(@{$cache_data{shelf}}, $hold->id); # copy needs to go back to the shelf
            }
        }

        my $cache_key = md5_hex(time . $$ . rand());
        $logger->info("clear_shelf_cache: storing under $cache_key");
        $cache->put_cache($cache_key, \%cache_data, 7200); # TODO: 2 hours.  configurable?

        # tell the client we're done
        $client->respond_complete({cache_key => $cache_key});

        # ------------
        # fire off the hold cancelation trigger and wait for response so don't flood the service

        # refetch the holds to pick up the caclulated cancel_time, 
        # which may be needed by Action/Trigger
        $e->xact_begin;
        my $updated_holds = [];
        $updated_holds = $e->search_action_hold_request({id => \@canceled_holds}, {substream => 1}) if (@canceled_holds > 0);
        $e->rollback;

        $U->create_events_for_hook(
            'hold_request.cancel.expire_holds_shelf', 
            $_, $org_id, undef, undef, 1) for @$updated_holds;

    } else {
        # tell the client we're done
        $client->respond_complete;
    }
}

__PACKAGE__->register_method(
    method    => 'usr_hold_summary',
    api_name  => 'open-ils.circ.holds.user_summary',
    signature => q/
        Returns a summary of holds statuses for a given user
    /
);

sub usr_hold_summary {
    my($self, $conn, $auth, $user_id) = @_;

	my $e = new_editor(authtoken=>$auth);
	$e->checkauth or return $e->event;
	$e->allowed('VIEW_HOLD') or return $e->event;

    my $holds = $e->search_action_hold_request(
        {  
            usr =>  $user_id , 
            fulfillment_time => undef,
            cancel_time      => undef,
        }
    );

    my %summary = (1 => 0, 2 => 0, 3 => 0, 4 => 0);
    $summary{_hold_status($e, $_)} += 1 for @$holds;
    return \%summary;
}



__PACKAGE__->register_method(
    method    => 'hold_has_copy_at',
    api_name  => 'open-ils.circ.hold.has_copy_at',
    signature => {
        desc   => 
                'Returns the ID of the found copy and name of the shelving location if there is ' .
                'an available copy at the specified org unit.  Returns empty hash otherwise.  '   .
                'The anticipated use for this method is to determine whether an item is '         .
                'available at the library where the user is placing the hold (or, alternatively, '.
                'at the pickup library) to encourage bypassing the hold placement and just '      .
                'checking out the item.' ,
        params => [
            { desc => 'Authentication Token', type => 'string' },
            { desc => 'Method Arguments.  Options include: hold_type, hold_target, org_unit.  ' 
                    . 'hold_type is the hold type code (T, V, C, M, ...).  '
                    . 'hold_target is the identifier of the hold target object.  ' 
                    . 'org_unit is org unit ID.', 
              type => 'object' 
            }
        ],
        return => { 
            desc => q/Result hash like { "copy" : copy_id, "location" : location_name }, empty hash on misses, event on error./,
            type => 'object' 
        }
    }
);

sub hold_has_copy_at {
    my($self, $conn, $auth, $args) = @_;

	my $e = new_editor(authtoken=>$auth);
	$e->checkauth or return $e->event;

    my $hold_type   = $$args{hold_type};
    my $hold_target = $$args{hold_target};
    my $org_unit    = $$args{org_unit};

    my $query = {
        select => {acp => ['id'], acpl => ['name']},
        from   => {
            acp => {
                acpl => {field => 'id', filter => { holdable => 't'}, fkey => 'location'},
                ccs  => {field => 'id', filter => { holdable => 't'}, fkey => 'status'  }
            }
        },
        where => {'+acp' => { circulate => 't', deleted => 'f', holdable => 't', circ_lib => $org_unit, status => [0,7]}},
        limit => 1
    };

    if($hold_type eq 'C' or $hold_type eq 'F' or $hold_type eq 'R') {

        $query->{where}->{'+acp'}->{id} = $hold_target;

    } elsif($hold_type eq 'V') {

        $query->{where}->{'+acp'}->{call_number} = $hold_target;

    } elsif($hold_type eq 'P') {

        $query->{from}->{acp}->{acpm} = {
            field  => 'target_copy',
            fkey   => 'id',
            filter => {part => $hold_target},
        };

    } elsif($hold_type eq 'I') {

        $query->{from}->{acp}->{sitem} = {
            field  => 'unit',
            fkey   => 'id',
            filter => {issuance => $hold_target},
        };

    } elsif($hold_type eq 'T') {

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

    } else {

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
    }

    my $res = $e->json_query($query)->[0] or return {};
    return {copy => $res->{id}, location => $res->{name}} if $res;
}


# returns true if the user already has an item checked out 
# that could be used to fulfill the requested hold.
sub hold_item_is_checked_out {
    my($e, $user_id, $hold_type, $hold_target) = @_;

    my $query = {
        select => {acp => ['id']},
        from   => {acp => {}},
        where  => {
            '+acp' => {
                id => {
                    in => { # copies for circs the user has checked out
                        select => {circ => ['target_copy']},
                        from   => 'circ',
                        where  => {
                            usr => $user_id,
                            checkin_time => undef,
                            '-or' => [
                                {stop_fines => ["MAXFINES","LONGOVERDUE"]},
                                {stop_fines => undef}
                            ],
                        }
                    }
                }
            }
        },
        limit => 1
    };

    if($hold_type eq 'C' || $hold_type eq 'R' || $hold_type eq 'F') {

        $query->{where}->{'+acp'}->{id}->{in}->{where}->{'target_copy'} = $hold_target;

    } elsif($hold_type eq 'V') {

        $query->{where}->{'+acp'}->{call_number} = $hold_target;

     } elsif($hold_type eq 'P') {

        $query->{from}->{acp}->{acpm} = {
            field  => 'target_copy',
            fkey   => 'id',
            filter => {part => $hold_target},
        };

     } elsif($hold_type eq 'I') {

        $query->{from}->{acp}->{sitem} = {
            field  => 'unit',
            fkey   => 'id',
            filter => {issuance => $hold_target},
        };

    } elsif($hold_type eq 'T') {

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

    } else {

        $query->{from}->{acp}->{acn} = {
            field => 'id',
            fkey => 'call_number',
            join => {
                bre => {
                    field => 'id',
                    fkey => 'record',
                    join => {
                        mmrsm => {
                            field => 'source',
                            fkey => 'id',
                            filter => {metarecord => $hold_target},
                        }
                    }
                }
            }
        };
    }

    return $e->json_query($query)->[0];
}

__PACKAGE__->register_method(
    method    => 'change_hold_title',
    api_name  => 'open-ils.circ.hold.change_title',
    signature => {
        desc => q/
            Updates all title level holds targeting the specified bibs to point a new bib./,
        params => [
            { desc => 'Authentication Token', type => 'string' },
            { desc => 'New Target Bib Id',    type => 'number' },
            { desc => 'Old Target Bib Ids',   type => 'array'  },
        ],
        return => { desc => '1 on success' }
    }
);

__PACKAGE__->register_method(
    method    => 'change_hold_title_for_specific_holds',
    api_name  => 'open-ils.circ.hold.change_title.specific_holds',
    signature => {
        desc => q/
            Updates specified holds to target new bib./,
        params => [
            { desc => 'Authentication Token', type => 'string' },
            { desc => 'New Target Bib Id',    type => 'number' },
            { desc => 'Holds Ids for holds to update',   type => 'array'  },
        ],
        return => { desc => '1 on success' }
    }
);


sub change_hold_title {
    my( $self, $client, $auth, $new_bib_id, $bib_ids ) = @_;

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    my $holds = $e->search_action_hold_request(
        [
            {
                cancel_time      => undef,
                fulfillment_time => undef,
                hold_type        => 'T',
                target           => $bib_ids
            },
            {
                flesh        => 1,
                flesh_fields => { ahr => ['usr'] }
            }
        ],
        { substream => 1 }
    );

    for my $hold (@$holds) {
        $e->allowed('UPDATE_HOLD', $hold->usr->home_ou) or return $e->die_event;
        $logger->info("Changing hold " . $hold->id . " target from " . $hold->target . " to $new_bib_id in title hold target change");
        $hold->target( $new_bib_id );
        $e->update_action_hold_request($hold) or return $e->die_event;
    }

    $e->commit;

    _reset_hold($self, $e->requestor, $_) for @$holds;

    return 1;
}

sub change_hold_title_for_specific_holds {
    my( $self, $client, $auth, $new_bib_id, $hold_ids ) = @_;

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    my $holds = $e->search_action_hold_request(
        [
            {
                cancel_time      => undef,
                fulfillment_time => undef,
                hold_type        => 'T',
                id               => $hold_ids
            },
            {
                flesh        => 1,
                flesh_fields => { ahr => ['usr'] }
            }
        ],
        { substream => 1 }
    );

    for my $hold (@$holds) {
        $e->allowed('UPDATE_HOLD', $hold->usr->home_ou) or return $e->die_event;
        $logger->info("Changing hold " . $hold->id . " target from " . $hold->target . " to $new_bib_id in title hold target change");
        $hold->target( $new_bib_id );
        $e->update_action_hold_request($hold) or return $e->die_event;
    }

    $e->commit;

    _reset_hold($self, $e->requestor, $_) for @$holds;

    return 1;
}

__PACKAGE__->register_method(
    method    => 'rec_hold_count',
    api_name  => 'open-ils.circ.bre.holds.count',
    signature => {
        desc => q/Returns the total number of holds that target the 
            selected bib record or its associated copies and call_numbers/,
        params => [
            { desc => 'Bib ID', type => 'number' },
        ],
        return => {desc => 'Hold count', type => 'number'}
    }
);

__PACKAGE__->register_method(
    method    => 'rec_hold_count',
    api_name  => 'open-ils.circ.mmr.holds.count',
    signature => {
        desc => q/Returns the total number of holds that target the 
            selected metarecord or its associated copies, call_numbers, and bib records/,
        params => [
            { desc => 'Metarecord ID', type => 'number' },
        ],
        return => {desc => 'Hold count', type => 'number'}
    }
);

# XXX Need to add type I (and, soon, type P) holds to these counts
sub rec_hold_count {
    my($self, $conn, $target_id) = @_;


    my $mmr_join = {
        mmrsm => {
            field => 'id',
            fkey => 'source',
            filter => {metarecord => $target_id}
        }
    };

    my $bre_join = {
        bre => {
            field => 'id',
            filter => { id => $target_id },
            fkey => 'record'
        }
    };

    if($self->api_name =~ /mmr/) {
        delete $bre_join->{bre}->{filter};
        $bre_join->{bre}->{join} = $mmr_join;
    }

    my $cn_join = {
        acn => {
            field => 'id',
            fkey => 'call_number',
            join => $bre_join
        }
    };

    my $query = {
        select => {ahr => [{column => 'id', transform => 'count', alias => 'count'}]},
        from => 'ahr',
        where => {
            '+ahr' => {
                cancel_time => undef, 
                fulfillment_time => undef,
                '-or' => [
                    {
                        '-and' => {
                            hold_type => [qw/C F R/],
                            target => {
                                in => {
                                    select => {acp => ['id']},
                                    from => { acp => $cn_join }
                                }
                            }
                        }
                    },
                    {
                        '-and' => {
                            hold_type => 'V',
                            target => {
                                in => {
                                    select => {acn => ['id']},
                                    from => {acn => $bre_join}
                                }
                            }
                        }
                    },
                    {
                        '-and' => {
                            hold_type => 'T',
                            target => $target_id
                        }
                    }
                ]
            }
        }
    };

    if($self->api_name =~ /mmr/) {
        $query->{where}->{'+ahr'}->{'-or'}->[2] = {
            '-and' => {
                hold_type => 'T',
                target => {
                    in => {
                        select => {bre => ['id']},
                        from => {bre => $mmr_join}
                    }
                }
            }
        };

        $query->{where}->{'+ahr'}->{'-or'}->[3] = {
            '-and' => {
                hold_type => 'M',
                target => $target_id
            }
        };
    }


    return new_editor()->json_query($query)->[0]->{count};
}

# A helper function to calculate a hold's expiration time at a given
# org_unit. Takes the org_unit as an argument and returns either the
# hold expire time as an ISO8601 string or undef if there is no hold
# expiration interval set for the subject ou.
sub calculate_expire_time
{
    my $ou = shift;
    my $interval = $U->ou_ancestor_setting_value($ou, OILS_SETTING_HOLD_EXPIRE);
    if($interval) {
        my $date = DateTime->now->add(seconds => OpenSRF::Utils::interval_to_seconds($interval));
        return $U->epoch2ISO8601($date->epoch);
    }
    return undef;
}

1;
