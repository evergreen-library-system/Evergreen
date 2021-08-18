package OpenILS::Application::Circ::Circulate;
use strict; use warnings;
use base 'OpenILS::Application';
use OpenSRF::EX qw(:try);
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils::Config;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Const qw/:const/;
use OpenILS::Application::AppUtils;
use DateTime;
my $U = "OpenILS::Application::AppUtils";

my %scripts;
my $booking_status;
my $opac_renewal_use_circ_lib;
my $desk_renewal_use_circ_lib;

sub determine_booking_status {
    unless (defined $booking_status) {
        my $ses = create OpenSRF::AppSession("router");
        $booking_status = grep {$_ eq "open-ils.booking"} @{
            $ses->request("opensrf.router.info.class.list")->gather(1)
        };
        $ses->disconnect;
        $logger->info("booking status: " . ($booking_status ? "on" : "off"));
    }

    return $booking_status;
}


my $MK_ENV_FLESH = { 
    flesh => 2, 
    flesh_fields => {acp => ['call_number','parts','floating'], acn => ['record']}
};

# table of cases where suppressing a system-generated copy alerts
# should generate an override of an old-style event
my %COPY_ALERT_OVERRIDES = (
    "CLAIMSRETURNED\tCHECKOUT" => ['CIRC_CLAIMS_RETURNED'],
    "CLAIMSRETURNED\tCHECKIN" => ['CIRC_CLAIMS_RETURNED'],
    "LOST\tCHECKOUT" => ['OPEN_CIRCULATION_EXISTS'],
    "LONGOVERDUE\tCHECKOUT" => ['OPEN_CIRCULATION_EXISTS'],
    "MISSING\tCHECKOUT" => ['COPY_NOT_AVAILABLE'],
    "DAMAGED\tCHECKOUT" => ['COPY_NOT_AVAILABLE'],
    "LOST_AND_PAID\tCHECKOUT" => ['COPY_NOT_AVAILABLE', 'OPEN_CIRCULATION_EXISTS']
);

sub initialize {}

__PACKAGE__->register_method(
    method  => "run_method",
    api_name    => "open-ils.circ.checkout.permit",
    notes       => q/
        Determines if the given checkout can occur
        @param authtoken The login session key
        @param params A trailing hash of named params including 
            barcode : The copy barcode, 
            patron : The patron the checkout is occurring for, 
            renew : true or false - whether or not this is a renewal
        @return The event that occurred during the permit check.  
    /);


__PACKAGE__->register_method (
    method      => 'run_method',
    api_name        => 'open-ils.circ.checkout.permit.override',
    signature   => q/@see open-ils.circ.checkout.permit/,
);


__PACKAGE__->register_method(
    method  => "run_method",
    api_name    => "open-ils.circ.checkout",
    notes => q/
        Checks out an item
        @param authtoken The login session key
        @param params A named hash of params including:
            copy            The copy object
            barcode     If no copy is provided, the copy is retrieved via barcode
            copyid      If no copy or barcode is provide, the copy id will be use
            patron      The patron's id
            noncat      True if this is a circulation for a non-cataloted item
            noncat_type The non-cataloged type id
            noncat_circ_lib The location for the noncat circ.  
            precat      The item has yet to be cataloged
            dummy_title The temporary title of the pre-cataloded item
            dummy_author The temporary authr of the pre-cataloded item
                Default is the home org of the staff member
        @return The SUCCESS event on success, any other event depending on the error
    /);

__PACKAGE__->register_method(
    method  => "run_method",
    api_name    => "open-ils.circ.checkin",
    argc        => 2,
    signature   => q/
        Generic super-method for handling all copies
        @param authtoken The login session key
        @param params Hash of named parameters including:
            barcode - The copy barcode
            force   - If true, copies in bad statuses will be checked in and give good statuses
            noop    - don't capture holds or put items into transit
            void_overdues - void all overdues for the circulation (aka amnesty)
            ...
    /
);

__PACKAGE__->register_method(
    method    => "run_method",
    api_name  => "open-ils.circ.checkin.override",
    signature => q/@see open-ils.circ.checkin/
);

__PACKAGE__->register_method(
    method    => "run_method",
    api_name  => "open-ils.circ.renew.override",
    signature => q/@see open-ils.circ.renew/,
);

__PACKAGE__->register_method(
    method  => "run_method",
    api_name    => "open-ils.circ.renew",
    notes       => <<"    NOTES");
    PARAMS( authtoken, circ => circ_id );
    open-ils.circ.renew(login_session, circ_object);
    Renews the provided circulation.  login_session is the requestor of the
    renewal and if the logged in user is not the same as circ->usr, then
    the logged in user must have RENEW_CIRC permissions.
    NOTES

__PACKAGE__->register_method(
    method   => "run_method",
    api_name => "open-ils.circ.checkout.full"
);
__PACKAGE__->register_method(
    method   => "run_method",
    api_name => "open-ils.circ.checkout.full.override"
);
__PACKAGE__->register_method(
    method   => "run_method",
    api_name => "open-ils.circ.reservation.pickup"
);
__PACKAGE__->register_method(
    method   => "run_method",
    api_name => "open-ils.circ.reservation.return"
);
__PACKAGE__->register_method(
    method   => "run_method",
    api_name => "open-ils.circ.reservation.return.override"
);
__PACKAGE__->register_method(
    method   => "run_method",
    api_name => "open-ils.circ.checkout.inspect",
    desc     => q/Returns the circ matrix test result and, on success, the rule set and matrix test object/
);


sub run_method {
    my( $self, $conn, $auth, $args ) = @_;
    translate_legacy_args($args);
    $args->{override_args} = { all => 1 } unless defined $args->{override_args};
    $args->{new_copy_alerts} ||= $self->api_level > 1 ? 1 : 0;
    my $api = $self->api_name;

    my $circulator = 
        OpenILS::Application::Circ::Circulator->new($auth, %$args);

    return circ_events($circulator) if $circulator->bail_out;

    $circulator->use_booking(determine_booking_status());

    # --------------------------------------------------------------------------
    # First, check for a booking transit, as the barcode may not be a copy
    # barcode, but a resource barcode, and nothing else in here will work
    # --------------------------------------------------------------------------

    if ($circulator->use_booking && (my $bc = $circulator->copy_barcode) && $api !~ /checkout|inspect/) { # do we have a barcode?
        my $resources = $circulator->editor->search_booking_resource( { barcode => $bc } ); # any resources by this barcode?
        if (@$resources) { # yes!

            my $res_id_list = [ map { $_->id } @$resources ];
            my $transit = $circulator->editor->search_action_reservation_transit_copy(
                [
                    { target_copy => $res_id_list, dest => $circulator->circ_lib, dest_recv_time => undef, cancel_time => undef },
                    { order_by => { artc => 'source_send_time' }, limit => 1 }
                ]
            )->[0]; # Any transit for this barcode?

            if ($transit) { # yes! unwrap it.

                my $reservation = $circulator->editor->retrieve_booking_reservation( $transit->reservation );
                my $res_type    = $circulator->editor->retrieve_booking_resource_type( $reservation->target_resource_type );

                my $success_event = new OpenILS::Event(
                    "SUCCESS", "payload" => {"reservation" => $reservation}
                );
                if ($U->is_true($res_type->catalog_item)) { # is there a copy to be had here?
                    if (my $copy = $circulator->editor->search_asset_copy([
                        { barcode => $bc, deleted => 'f' }, $MK_ENV_FLESH
                    ])->[0]) { # got a copy
                        $copy->status( $transit->copy_status );
                        $copy->editor($circulator->editor->requestor->id);
                        $copy->edit_date('now');
                        $circulator->editor->update_asset_copy($copy);
                        $success_event->{"payload"}->{"record"} =
                            $U->record_to_mvr($copy->call_number->record);
                        $success_event->{"payload"}->{"volume"} = $copy->call_number;
                        $copy->call_number($copy->call_number->id);
                        $success_event->{"payload"}->{"copy"} = $copy;
                    }
                }

                $transit->dest_recv_time('now');
                $circulator->editor->update_action_reservation_transit_copy( $transit );

                $circulator->editor->commit;
                # Formerly this branch just stopped here. Argh!
                $conn->respond_complete($success_event);
                return;
            }
        }
    }

    if ($circulator->use_booking) {
        $circulator->is_res_checkin($circulator->is_checkin(1))
            if $api =~ /reservation.return/ or (
                $api =~ /checkin/ and $circulator->seems_like_reservation()
            );

        $circulator->is_res_checkout(1) if $api =~ /reservation.pickup/;
    }

    $circulator->is_renewal(1) if $api =~ /renew/;
    $circulator->is_checkin(1) if $api =~ /checkin/;
    $circulator->is_checkout(1) if $api =~ /checkout/;
    $circulator->override(1) if $api =~ /override/o;

    $circulator->mk_env();
    $circulator->noop(1) if $circulator->claims_never_checked_out;

    return circ_events($circulator) if $circulator->bail_out;

    if( $api =~ /checkout\.permit/ ) {
        $circulator->do_permit();

    } elsif( $api =~ /checkout.full/ ) {

        # requesting a precat checkout implies that any required
        # overrides have been performed.  Go ahead and re-override.
        $circulator->skip_permit_key(1);
        $circulator->override(1) if ( $circulator->request_precat && $circulator->editor->allowed('CREATE_PRECAT') );
        $circulator->do_permit();
        $circulator->is_checkout(1);
        unless( $circulator->bail_out ) {
            $circulator->events([]);
            $circulator->do_checkout();
        }

    } elsif( $circulator->is_res_checkout ) {
        $circulator->do_reservation_pickup();

    } elsif( $api =~ /inspect/ ) {
        my $data = $circulator->do_inspect();
        $circulator->editor->rollback;
        return $data;

    } elsif( $api =~ /checkout/ ) {
        $circulator->do_checkout();

    } elsif( $circulator->is_res_checkin ) {
        $circulator->do_reservation_return();
        $circulator->do_checkin() if ($circulator->copy());
    } elsif( $api =~ /checkin/ ) {
        $circulator->do_checkin();

    } elsif( $api =~ /renew/ ) {
        $circulator->do_renew($api);
    }

    if( $circulator->bail_out ) {

        my @ee;
        # make sure no success event accidentally slip in
        $circulator->events(
            [ grep { $_->{textcode} ne 'SUCCESS' } @{$circulator->events} ]);

        # Log the events
        my @e = @{$circulator->events};
        push( @ee, $_->{textcode} ) for @e;
        $logger->info("circulator: bailing out with events: " . (join ", ", @ee));

        $circulator->editor->rollback;

    } else {

        # checkin and reservation return can result in modifications to
        # actor.usr.claims_never_checked_out_count without also modifying
        # actor.last_xact_id.  Perform a no-op update on the patron to
        # force an update to last_xact_id.
        if ($circulator->claims_never_checked_out && $circulator->patron) {
            $circulator->editor->update_actor_user(
                $circulator->editor->retrieve_actor_user($circulator->patron->id))
                or return $circulator->editor->die_event;
        }

        $circulator->editor->commit;
    }
    
    $conn->respond_complete(circ_events($circulator));

    return undef if $circulator->bail_out;

    $circulator->do_hold_notify($circulator->notify_hold)
        if $circulator->notify_hold;
    $circulator->retarget_holds if $circulator->retarget;
    $circulator->append_reading_list;
    $circulator->make_trigger_events;
    
    return undef;
}

sub circ_events {
    my $circ = shift;
    my @e = @{$circ->events};
    # if we have multiple events, SUCCESS should not be one of them;
    @e = grep { $_->{textcode} ne 'SUCCESS' } @e if @e > 1;
    return (@e == 1) ? $e[0] : \@e;
}


sub translate_legacy_args {
    my $args = shift;

    if( $$args{barcode} ) {
        $$args{copy_barcode} = $$args{barcode};
        delete $$args{barcode};
    }

    if( $$args{copyid} ) {
        $$args{copy_id} = $$args{copyid};
        delete $$args{copyid};
    }

    if( $$args{patronid} ) {
        $$args{patron_id} = $$args{patronid};
        delete $$args{patronid};
    }

    if( $$args{patron} and !ref($$args{patron}) ) {
        $$args{patron_id} = $$args{patron};
        delete $$args{patron};
    }


    if( $$args{noncat} ) {
        $$args{is_noncat} = $$args{noncat};
        delete $$args{noncat};
    }

    if( $$args{precat} ) {
        $$args{is_precat} = $$args{request_precat} = $$args{precat};
        delete $$args{precat};
    }
}



# --------------------------------------------------------------------------
# This package actually manages all of the circulation logic
# --------------------------------------------------------------------------
package OpenILS::Application::Circ::Circulator;
use strict; use warnings;
use vars q/$AUTOLOAD/;
use DateTime;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw(md5_hex);
use DateTime::Format::ISO8601;
use OpenILS::Utils::PermitHold;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::Circ::Holds;
use OpenILS::Application::Circ::Transit;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Const qw/:const/;
use OpenILS::Utils::Penalty;
use OpenILS::Application::Circ::CircCommon;
use Time::Local;

my $CC = "OpenILS::Application::Circ::CircCommon";
my $holdcode    = "OpenILS::Application::Circ::Holds";
my $transcode   = "OpenILS::Application::Circ::Transit";
my %user_groups;

sub DESTROY { }


# --------------------------------------------------------------------------
# Add a pile of automagic getter/setter methods
# --------------------------------------------------------------------------
my @AUTOLOAD_FIELDS = qw/
    notify_hold
    remote_hold
    backdate
    reservation
    do_inventory_update
    copy
    copy_id
    copy_barcode
    new_copy_alerts
    user_copy_alerts
    system_copy_alerts
    overrides_per_copy_alerts
    next_copy_status
    copy_state
    patron
    patron_id
    patron_barcode
    volume
    title
    is_renewal
    is_checkout
    is_res_checkout
    is_precat
    is_noncat
    request_precat
    is_checkin
    is_res_checkin
    noncat_type
    editor
    events
    cache_handle
    override
    circ_permit_patron
    circ_permit_copy
    circ_duration
    circ_recurring_fines
    circ_max_fines
    circ_permit_renew
    circ
    transit
    hold
    permit_key
    noncat_circ_lib
    noncat_count
    checkout_time
    dummy_title
    dummy_author
    dummy_isbn
    circ_modifier
    circ_lib
    barcode
    duration_level
    recurring_fines_level
    duration_rule
    recurring_fines_rule
    max_fine_rule
    renewal_remaining
    auto_renewal_remaining
    hard_due_date
    due_date
    fulfilled_holds
    transit
    checkin_changed
    force
    permit_override
    pending_checkouts
    cancelled_hold_transit
    opac_renewal
    phone_renewal
    desk_renewal
    sip_renewal
    auto_renewal
    retarget
    matrix_test_result
    circ_matrix_matchpoint
    circ_test_success
    is_deposit
    is_rental
    deposit_billing
    rental_billing
    capture
    noop
    void_overdues
    parent_circ
    return_patron
    claims_never_checked_out
    skip_permit_key
    skip_deposit_fee
    skip_rental_fee
    use_booking
    clear_expired
    retarget_mode
    hold_as_transit
    fake_hold_dest
    limit_groups
    override_args
    checkout_is_for_hold
    manual_float
    dont_change_lost_zero
    lost_bill_options
    needs_lost_bill_handling
/;


sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) or die "$self is not an object";
    my $data = shift;
    my $name = $AUTOLOAD;
    $name =~ s/.*://o;   

    unless (grep { $_ eq $name } @AUTOLOAD_FIELDS) {
        $logger->error("circulator: $type: invalid autoload field: $name");
        die "$type: invalid autoload field: $name\n" 
    }

    {
        no strict 'refs';
        *{"${type}::${name}"} = sub {
            my $s = shift;
            my $v = shift;
            $s->{$name} = $v if defined $v;
            return $s->{$name};
        }
    }
    return $self->$name($data);
}


sub new {
    my( $class, $auth, %args ) = @_;
    $class = ref($class) || $class;
    my $self = bless( {}, $class );

    $self->events([]);
    $self->editor(new_editor(xact => 1, authtoken => $auth));

    unless( $self->editor->checkauth ) {
        $self->bail_on_events($self->editor->event);
        return $self;
    }

    $self->cache_handle(OpenSRF::Utils::Cache->new('global'));

    $self->$_($args{$_}) for keys %args;

    $self->circ_lib(
        ($self->circ_lib) ? $self->circ_lib : $self->editor->requestor->ws_ou);

    # if this is a renewal, default to desk_renewal
    $self->desk_renewal(1) unless
        $self->opac_renewal or $self->phone_renewal or $self->sip_renewal
        or $self->auto_renewal;

    $self->capture('') unless $self->capture;

    unless(%user_groups) {
        my $gps = $self->editor->retrieve_all_permission_grp_tree;
        %user_groups = map { $_->id => $_ } @$gps;
    }

    return $self;
}


# --------------------------------------------------------------------------
# True if we should discontinue processing
# --------------------------------------------------------------------------
sub bail_out {
    my( $self, $bool ) = @_;
    if( defined $bool ) {
        $logger->info("circulator: BAILING OUT") if $bool;
        $self->{bail_out} = $bool;
    }
    return $self->{bail_out};
}


sub push_events {
    my( $self, @evts ) = @_;
    for my $e (@evts) {
        next unless $e;
        $e->{payload} = $self->copy if 
              ($e->{textcode} eq 'COPY_NOT_AVAILABLE');

        $logger->info("circulator: pushing event ".$e->{textcode});
        push( @{$self->events}, $e ) unless
            grep { $_->{textcode} eq $e->{textcode} } @{$self->events};
    }
}

sub mk_permit_key {
    my $self = shift;
    return '' if $self->skip_permit_key;
    my $key = md5_hex( time() . rand() . "$$" );
    $self->cache_handle->put_cache( "oils_permit_key_$key", 1, 300 );
    return $self->permit_key($key);
}

sub check_permit_key {
    my $self = shift;
    return 1 if $self->skip_permit_key;
    my $key = $self->permit_key;
    return 0 unless $key;
    my $k = "oils_permit_key_$key";
    my $one = $self->cache_handle->get_cache($k);
    $self->cache_handle->delete_cache($k);
    return ($one) ? 1 : 0;
}

sub seems_like_reservation {
    my $self = shift;

    # Some words about the following method:
    # 1) It requires the VIEW_USER permission, but that's not an
    # issue, right, since all staff should have that?
    # 2) It returns only one reservation at a time, even if an item can be
    # and is currently overbooked.  Hmmm....
    my $booking_ses = create OpenSRF::AppSession("open-ils.booking");
    my $result = $booking_ses->request(
        "open-ils.booking.reservations.by_returnable_resource_barcode",
        $self->editor->authtoken,
        $self->copy_barcode
    )->gather(1);
    $booking_ses->disconnect;

    return $self->bail_on_events($result) if defined $U->event_code($result);

    if (@$result > 0) {
        $self->reservation(shift @$result);
        return 1;
    } else {
        return 0;
    }

}

# save_trimmed_copy() used just to be a block in mk_env(), but was separated for re-use
sub save_trimmed_copy {
    my ($self, $copy) = @_;

    $self->copy($copy);
    $self->volume($copy->call_number);
    $self->title($self->volume->record);
    $self->copy->call_number($self->volume->id);
    $self->volume->record($self->title->id);
    $self->is_precat(1) if $self->volume->id == OILS_PRECAT_CALL_NUMBER;
    if($self->copy->deposit_amount and $self->copy->deposit_amount > 0) {
        $self->is_deposit(1) if $U->is_true($self->copy->deposit);
        $self->is_rental(1) unless $U->is_true($self->copy->deposit);
    }
}

sub collect_user_copy_alerts {
    my $self = shift;
    my $e = $self->editor;

    if($self->copy) {
        my $alerts = $e->search_asset_copy_alert([
            {copy => $self->copy->id, ack_time => undef},
            {flesh => 1, flesh_fields => { aca => [ qw/ alert_type / ] }}
        ]);
        if (ref $alerts eq "ARRAY") {
            $logger->info("circulator: found " . scalar(@$alerts) . " alerts for copy " .
                $self->copy->id);
            $self->user_copy_alerts($alerts);
        }
    }
}

sub filter_user_copy_alerts {
    my $self = shift;

    my $e = $self->editor;

    if(my $alerts = $self->user_copy_alerts) {

        my $suppress_orgs = $U->get_org_full_path($self->circ_lib);
        my $suppressions = $e->search_actor_copy_alert_suppress(
            {org => $suppress_orgs}
        );

        my @final_alerts;
        foreach my $a (@$alerts) {
            # filter on event type
            if (defined $a->alert_type) {
                next if ($a->alert_type->event eq 'CHECKIN' && !$self->is_checkin && !$self->is_renewal);
                next if ($a->alert_type->event eq 'CHECKOUT' && !$self->is_checkout && !$self->is_renewal);
                next if (defined $a->alert_type->in_renew && $U->is_true($a->alert_type->in_renew) && !$self->is_renewal);
                next if (defined $a->alert_type->in_renew && !$U->is_true($a->alert_type->in_renew) && $self->is_renewal);
            }

            # filter on suppression
            next if (grep { $a->alert_type->id == $_->alert_type} @$suppressions);

            # filter on "only at circ lib"
            if (defined $a->alert_type->at_circ) {
                my $copy_circ_lib = (ref $self->copy->circ_lib) ?
                    $self->copy->circ_lib->id : $self->copy->circ_lib;
                my $orgs = $U->get_org_descendants($copy_circ_lib);

                if ($U->is_true($a->alert_type->invert_location)) {
                    next if (grep {$_ == $self->circ_lib} @$orgs);
                } else {
                    next unless (grep {$_ == $self->circ_lib} @$orgs);
                }
            }

            # filter on "only at owning lib"
            if (defined $a->alert_type->at_owning) {
                my $copy_owning_lib = (ref $self->volume->owning_lib) ?
                    $self->volume->owning_lib->id : $self->volume->owning_lib;
                my $orgs = $U->get_org_descendants($copy_owning_lib);

                if ($U->is_true($a->alert_type->invert_location)) {
                    next if (grep {$_ == $self->circ_lib} @$orgs);
                } else {
                    next unless (grep {$_ == $self->circ_lib} @$orgs);
                }
            }

            $a->alert_type->next_status([$U->unique_unnested_numbers($a->alert_type->next_status)]);

            push @final_alerts, $a;
        }

        $self->user_copy_alerts(\@final_alerts);
    }
}

sub generate_system_copy_alerts {
    my $self = shift;
    return unless($self->copy);

    # don't create system copy alerts if the copy
    # is in a normal state; we're assuming that there's
    # never a need to generate a popup for each and every
    # checkin or checkout of normal items. If this assumption
    # proves false, then we'll need to add a way to explicitly specify
    # that a copy alert type should never generate a system copy alert
    return if $self->copy_state eq 'NORMAL';

    my $e = $self->editor;

    my $suppress_orgs = $U->get_org_full_path($self->circ_lib);
    my $suppressions = $e->search_actor_copy_alert_suppress(
        {org => $suppress_orgs}
    );

    # events we care about ...
    my $event = [];
    push(@$event, 'CHECKIN') if $self->is_checkin;
    push(@$event, 'CHECKOUT') if $self->is_checkout;
    return unless scalar(@$event);

    my $alert_orgs = $U->get_org_ancestors($self->circ_lib);
    my $alert_types = $e->search_config_copy_alert_type({
        active    => 't',
        scope_org => $alert_orgs,
        event     => $event,
        state => $self->copy_state,
        '-or' => [ { in_renew => $self->is_renewal }, { in_renew => undef } ],
    });

    my @final_types;
    foreach my $a (@$alert_types) {
        # filter on "only at circ lib"
        if (defined $a->at_circ) {
            my $copy_circ_lib = (ref $self->copy->circ_lib) ?
                $self->copy->circ_lib->id : $self->copy->circ_lib;
            my $orgs = $U->get_org_descendants($copy_circ_lib);

            if ($U->is_true($a->invert_location)) {
                next if (grep {$_ == $self->circ_lib} @$orgs);
            } else {
                next unless (grep {$_ == $self->circ_lib} @$orgs);
            }
        }

        # filter on "only at owning lib"
        if (defined $a->at_owning) {
            my $copy_owning_lib = (ref $self->volume->owning_lib) ?
                $self->volume->owning_lib->id : $self->volume->owning_lib;
            my $orgs = $U->get_org_descendants($copy_owning_lib);

            if ($U->is_true($a->invert_location)) {
                next if (grep {$_ == $self->circ_lib} @$orgs);
            } else {
                next unless (grep {$_ == $self->circ_lib} @$orgs);
            }
        }

        push @final_types, $a;
    }

    if (@final_types) {
        $logger->info("circulator: found " . scalar(@final_types) . " system alert types for copy" .
            $self->copy->id);
    }

    my @alerts;
    
    # keep track of conditions corresponding to suppressed
    # system alerts, as these may be used to overridee
    # certain old-style-events
    my %auto_override_conditions = ();
    foreach my $t (@final_types) {
        if ($t->next_status) {
            if (grep { $t->id == $_->alert_type } @$suppressions) {
                $t->next_status([]);
            } else {
                $t->next_status([$U->unique_unnested_numbers($t->next_status)]);
            }
        }

        my $alert = new Fieldmapper::asset::copy_alert ();
        $alert->alert_type($t->id);
        $alert->copy($self->copy->id);
        $alert->temp(1);
        $alert->create_staff($e->requestor->id);
        $alert->create_time('now');
        $alert->ack_staff($e->requestor->id);
        $alert->ack_time('now');

        $alert = $e->create_asset_copy_alert($alert);

        next unless $alert;

        $alert->alert_type($t->clone);

        push(@{$self->next_copy_status}, @{$t->next_status}) if ($t->next_status);
        if (grep {$_->alert_type == $t->id} @$suppressions) {
            $auto_override_conditions{join("\t", $t->state, $t->event)} = 1;
        }
        push(@alerts, $alert) unless (grep {$_->alert_type == $t->id} @$suppressions);
    }

    $self->system_copy_alerts(\@alerts);
    $self->overrides_per_copy_alerts(\%auto_override_conditions);
}

sub add_overrides_from_system_copy_alerts {
    my $self = shift;
    my $e = $self->editor;

    foreach my $condition (keys %{$self->overrides_per_copy_alerts()}) {
        if (exists $COPY_ALERT_OVERRIDES{$condition}) {
            $self->override(1);
            push @{$self->override_args->{events}}, @{ $COPY_ALERT_OVERRIDES{$condition} };
            # special handling for long-overdue and lost checkouts
            if (grep { $_ eq 'OPEN_CIRCULATION_EXISTS' } @{ $COPY_ALERT_OVERRIDES{$condition} }) {
                my $state = (split /\t/, $condition, -1)[0];
                my $setting;
                if ($state eq 'LOST' or $state eq 'LOST_AND_PAID') {
                    $setting = 'circ.copy_alerts.forgive_fines_on_lost_checkin';
                } elsif ($state eq 'LONGOVERDUE') {
                    $setting = 'circ.copy_alerts.forgive_fines_on_long_overdue_checkin';
                } else {
                    next;
                }
                my $forgive = $U->ou_ancestor_setting_value(
                    $self->circ_lib, $setting, $e
                );
                if ($U->is_true($forgive)) {
                    $self->void_overdues(1);
                }
                $self->noop(1); # do not attempt transits, just check it in
                $self->do_checkin();
            }
        }
    }
}

sub mk_env {
    my $self = shift;
    my $e = $self->editor;

    $self->next_copy_status([]) unless (defined $self->next_copy_status);
    $self->overrides_per_copy_alerts({}) unless (defined $self->overrides_per_copy_alerts);

    # --------------------------------------------------------------------------
    # Grab the fleshed copy
    # --------------------------------------------------------------------------
    unless($self->is_noncat) {
        my $copy;
        if($self->copy_id) {
            $copy = $e->retrieve_asset_copy(
                [$self->copy_id, $MK_ENV_FLESH ]) or return $e->event;
    
        } elsif( $self->copy_barcode ) {
    
            $copy = $e->search_asset_copy(
                [{barcode => $self->copy_barcode, deleted => 'f'}, $MK_ENV_FLESH ])->[0];
        } elsif( $self->reservation ) {
            my $res = $e->json_query(
                {
                    "select" => {"acp" => ["id"]},
                    "from" => {
                        "acp" => {
                            "brsrc" => {
                                "fkey" => "barcode",
                                "field" => "barcode",
                                "join" => {
                                    "bresv" => {
                                        "fkey" => "id",
                                        "field" => "current_resource"
                                    }
                                }
                            }
                        }
                    },
                    "where" => {
                        deleted => 'f',
                        "+bresv" => {
                            "id" => (ref $self->reservation) ?
                                $self->reservation->id : $self->reservation
                        }
                    }
                }
            );
            if (ref $res eq "ARRAY" and scalar @$res) {
                $logger->info("circulator: mapped reservation " .
                    $self->reservation . " to copy " . $res->[0]->{"id"});
                $copy = $e->retrieve_asset_copy([$res->[0]->{"id"}, $MK_ENV_FLESH]);
            }
        }
    
        if($copy) {
            $self->save_trimmed_copy($copy);

            # alerts!
            $self->copy_state(
                $e->json_query(
                    {from => ['asset.copy_state', $copy->id]}
                )->[0]{'asset.copy_state'}
            );

            $self->generate_system_copy_alerts;
            $self->add_overrides_from_system_copy_alerts;
            $self->collect_user_copy_alerts;
            $self->filter_user_copy_alerts;

        } else {
            # We can't renew if there is no copy
            return $self->bail_on_events(OpenILS::Event->new('ASSET_COPY_NOT_FOUND'))
                if $self->is_renewal;
            $self->is_precat(1);
        }
    }

    # --------------------------------------------------------------------------
    # Grab the patron
    # --------------------------------------------------------------------------
    my $patron;
    my $flesh = {
        flesh => 1,
        flesh_fields => {au => [ qw/ card / ]}
    };

    if( $self->patron_id ) {
        $patron = $e->retrieve_actor_user([$self->patron_id, $flesh])
            or return $self->bail_on_events(OpenILS::Event->new('ACTOR_USER_NOT_FOUND'));

    } elsif( $self->patron_barcode ) {

        # note: throwing ACTOR_USER_NOT_FOUND instead of ACTOR_CARD_NOT_FOUND is intentional
        my $card = $e->search_actor_card({barcode => $self->patron_barcode})->[0] 
            or return $self->bail_on_events(OpenILS::Event->new('ACTOR_USER_NOT_FOUND'));

        $patron = $e->retrieve_actor_user($card->usr)
            or return $self->bail_on_events(OpenILS::Event->new('ACTOR_USER_NOT_FOUND'));

        # Use the card we looked up, not the patron's primary, for card active checks
        $patron->card($card);

    } else {
        if( my $copy = $self->copy ) {

            $flesh->{flesh} = 2;
            $flesh->{flesh_fields}->{circ} = ['usr'];

            my $circ = $e->search_action_circulation([
                {target_copy => $copy->id, checkin_time => undef}, $flesh
            ])->[0];

            if($circ) {
                $patron = $circ->usr;
                $circ->usr($patron->id); # de-flesh for consistency
                $self->circ($circ); 
            }
        }
    }

    return $self->bail_on_events(OpenILS::Event->new('ACTOR_USER_NOT_FOUND'))
        unless $self->patron($patron) or $self->is_checkin;

    unless($self->is_checkin) {

        # Check for inactivity and patron reg. expiration

        $self->bail_on_events(OpenILS::Event->new('PATRON_INACTIVE'))
            unless $U->is_true($patron->active);
    
        $self->bail_on_events(OpenILS::Event->new('PATRON_CARD_INACTIVE'))
            unless $U->is_true($patron->card->active);

        # Expired patrons cannot check out.  Renewals for expired
        # patrons depend on a setting and will be checked in the
        # do_renew subroutine.
        if ($self->is_checkout) {
            my $expire = DateTime::Format::ISO8601->new->parse_datetime(
                clean_ISO8601($patron->expire_date));

            if (CORE::time > $expire->epoch) {
                $self->bail_on_events(OpenILS::Event->new('PATRON_ACCOUNT_EXPIRED'))
            }
        }
    }
}


# --------------------------------------------------------------------------
# Does the circ permit work
# --------------------------------------------------------------------------
sub do_permit {
    my $self = shift;

    $self->log_me("do_permit()");

    unless( $self->editor->requestor->id == $self->patron->id ) {
        return $self->bail_on_events($self->editor->event)
            unless( $self->editor->allowed('VIEW_PERMIT_CHECKOUT') );
    }

    $self->check_captured_holds();
    $self->do_copy_checks();
    return if $self->bail_out;
    $self->run_patron_permit_scripts();
    $self->run_copy_permit_scripts() 
        unless $self->is_precat or $self->is_noncat;
    $self->check_item_deposit_events();
    $self->override_events();
    return if $self->bail_out;

    if($self->is_precat and not $self->request_precat) {
        $self->push_events(
            OpenILS::Event->new(
                'ITEM_NOT_CATALOGED', payload => $self->mk_permit_key));
        return $self->bail_out(1) unless $self->is_renewal;
    }

    $self->push_events(
        OpenILS::Event->new('SUCCESS', payload => $self->mk_permit_key));
}

sub check_item_deposit_events {
    my $self = shift;
    $self->push_events(OpenILS::Event->new('ITEM_DEPOSIT_REQUIRED', payload => $self->copy)) 
        if $self->is_deposit and not $self->is_deposit_exempt;
    $self->push_events(OpenILS::Event->new('ITEM_RENTAL_FEE_REQUIRED', payload => $self->copy)) 
        if $self->is_rental and not $self->is_rental_exempt;
}

# returns true if the user is not required to pay deposits
sub is_deposit_exempt {
    my $self = shift;
    my $pid = (ref $self->patron->profile) ?
        $self->patron->profile->id : $self->patron->profile;
    my $groups = $U->ou_ancestor_setting_value(
        $self->circ_lib, 'circ.deposit.exempt_groups', $self->editor);
    for my $grp (@$groups) {
        return 1 if $self->is_group_descendant($grp, $pid);
    }
    return 0;
}

# returns true if the user is not required to pay rental fees
sub is_rental_exempt {
    my $self = shift;
    my $pid = (ref $self->patron->profile) ?
        $self->patron->profile->id : $self->patron->profile;
    my $groups = $U->ou_ancestor_setting_value(
        $self->circ_lib, 'circ.rental.exempt_groups', $self->editor);
    for my $grp (@$groups) {
        return 1 if $self->is_group_descendant($grp, $pid);
    }
    return 0;
}

sub is_group_descendant {
    my($self, $p_id, $c_id) = @_;
    return 0 unless defined $p_id and defined $c_id;
    return 1 if $c_id == $p_id;
    while(my $grp = $user_groups{$c_id}) {
        $c_id = $grp->parent;
        return 0 unless defined $c_id;
        return 1 if $c_id == $p_id;
    }
    return 0;
}

sub check_captured_holds {
    my $self    = shift;
    my $copy    = $self->copy;
    my $patron  = $self->patron;

    return undef unless $copy;

    my $s = $U->copy_status($copy->status)->id;
    return unless $s == OILS_COPY_STATUS_ON_HOLDS_SHELF;
    $logger->info("circulator: copy is on holds shelf, searching for the correct hold");

    # Item is on the holds shelf, make sure it's going to the right person
    my $hold = $self->editor->search_action_hold_request(
        [
            { 
                current_copy        => $copy->id , 
                capture_time        => { '!=' => undef },
                cancel_time         => undef, 
                fulfillment_time    => undef 
            },
            { limit => 1,
              flesh => 1,
              flesh_fields => { ahr => ['usr'] }
            }
        ]
    )->[0];

    if ($hold and $hold->usr->id == $patron->id) {
        $self->checkout_is_for_hold(1);
        return undef;
    } elsif ($hold) {
        my $payload;
        my $holdau = $hold->usr;

        if ($holdau) {
            $payload->{patron_name} = $holdau->first_given_name . ' ' . $holdau->family_name;
            $payload->{patron_id} = $holdau->id;
        } else {
            $payload->{patron_name} = "???";
        }
        $payload->{hold_id}     = $hold->id;
        $self->push_events(OpenILS::Event->new('ITEM_ON_HOLDS_SHELF',
                                               payload => $payload));
    }

    $logger->info("circulator: this copy is needed by a different patron to fulfill a hold");

}


sub do_copy_checks {
    my $self = shift;
    my $copy = $self->copy;
    return unless $copy;

    my $stat = $U->copy_status($copy->status)->id;

    # We cannot check out a copy if it is in-transit
    if( $stat == OILS_COPY_STATUS_IN_TRANSIT ) {
        return $self->bail_on_events(OpenILS::Event->new('COPY_IN_TRANSIT'));
    }

    $self->handle_claims_returned();
    return if $self->bail_out;

    # no claims returned circ was found, check if there is any open circ
    unless( $self->is_renewal ) {

        my $circs = $self->editor->search_action_circulation(
            { target_copy => $copy->id, checkin_time => undef }
        );

        if(my $old_circ = $circs->[0]) { # an open circ was found

            my $payload = {copy => $copy};

            if($old_circ->usr == $self->patron->id) {
                
                $payload->{old_circ} = $old_circ;

                # If there is an open circulation on the checkout item and an auto-renew 
                # interval is defined, inform the caller that they should go 
                # ahead and renew the item instead of warning about open circulations.
    
                my $auto_renew_intvl = $U->ou_ancestor_setting_value(        
                    $self->circ_lib,
                    'circ.checkout_auto_renew_age', 
                    $self->editor
                );

                if($auto_renew_intvl) {
                    my $intvl_seconds = OpenILS::Utils::DateTime->interval_to_seconds($auto_renew_intvl);
                    my $checkout_time = DateTime::Format::ISO8601->new->parse_datetime( clean_ISO8601($old_circ->xact_start) );

                    if(DateTime->now > $checkout_time->add(seconds => $intvl_seconds)) {
                        $payload->{auto_renew} = 1;
                    }
                }
            }

            return $self->bail_on_events(
                OpenILS::Event->new('OPEN_CIRCULATION_EXISTS', payload => $payload)
            );
        }
    }
}

my $LEGACY_CIRC_EVENT_MAP = {
    'no_item' => 'ITEM_NOT_CATALOGED',
    'actor.usr.barred' => 'PATRON_BARRED',
    'asset.copy.circulate' =>  'COPY_CIRC_NOT_ALLOWED',
    'asset.copy.status' => 'COPY_NOT_AVAILABLE',
    'asset.copy_location.circulate' => 'COPY_CIRC_NOT_ALLOWED',
    'config.circ_matrix_test.circulate' => 'COPY_CIRC_NOT_ALLOWED',
    'config.circ_matrix_test.max_items_out' =>  'PATRON_EXCEEDS_CHECKOUT_COUNT',
    'config.circ_matrix_test.max_overdue' =>  'PATRON_EXCEEDS_OVERDUE_COUNT',
    'config.circ_matrix_test.max_fines' => 'PATRON_EXCEEDS_FINES',
    'config.circ_matrix_circ_mod_test' => 'PATRON_EXCEEDS_CHECKOUT_COUNT',
    'config.circ_matrix_test.total_copy_hold_ratio' => 
        'TOTAL_HOLD_COPY_RATIO_EXCEEDED',
    'config.circ_matrix_test.available_copy_hold_ratio' => 
        'AVAIL_HOLD_COPY_RATIO_EXCEEDED'
};


# ---------------------------------------------------------------------
# This pushes any patron-related events into the list but does not
# set bail_out for any events
# ---------------------------------------------------------------------
sub run_patron_permit_scripts {
    my $self        = shift;
    my $patronid    = $self->patron->id;

    my @allevents; 


    my $results = $self->run_indb_circ_test;
    unless($self->circ_test_success) {
        my @trimmed_results;

        if ($self->is_noncat) {
            # no_item result is OK during noncat checkout
            @trimmed_results = grep { ($_->{fail_part} || '') ne 'no_item' } @$results;

        } else {

            if ($self->checkout_is_for_hold) {
                # if this checkout will fulfill a hold, ignore CIRC blocks
                # and rely instead on the (later-checked) FULFILL block

                my @pen_names = grep {$_} map {$_->{fail_part}} @$results;
                my $fblock_pens = $self->editor->search_config_standing_penalty(
                    {name => [@pen_names], block_list => {like => '%CIRC%'}});

                for my $res (@$results) {
                    my $name = $res->{fail_part} || '';
                    next if grep {$_->name eq $name} @$fblock_pens;
                    push(@trimmed_results, $res);
                }

            } else { 
                # not for hold or noncat
                @trimmed_results = @$results;
            }
        }

        # update the final set of test results
        $self->matrix_test_result(\@trimmed_results); 

        push @allevents, $self->matrix_test_result_events;
    }

    for (@allevents) {
       $_->{payload} = $self->copy if 
             ($_->{textcode} eq 'COPY_NOT_AVAILABLE');
    }

    $logger->info("circulator: permit_patron script returned events: @allevents") if @allevents;

    $self->push_events(@allevents);
}

sub matrix_test_result_codes {
    my $self = shift;
    map { $_->{"fail_part"} } @{$self->matrix_test_result};
}

sub matrix_test_result_events {
    my $self = shift;
    map {
        my $event = new OpenILS::Event(
            $LEGACY_CIRC_EVENT_MAP->{$_->{"fail_part"}} || $_->{"fail_part"}
        );
        $event->{"payload"} = {"fail_part" => $_->{"fail_part"}};
        $event;
    } (@{$self->matrix_test_result});
}

sub run_indb_circ_test {
    my $self = shift;
    return $self->matrix_test_result if $self->matrix_test_result;

    # Before we run the database function, let's make sure that the patron's
    # threshold-based penalties are up-to-date, so that the database function
    # can take them into consideration.
    #
    # This takes place in a separate cstore editor and db transaction, so that
    # even if the circulation fails and its transaction is rolled back, any
    # newly calculated penalties remain on the patron's account.
    #
    # Note that this depends on the PostgreSQL transaction isolation level
    # being "read committed" (which it is by default); if it were "repeatable
    # read" or "serializable", the in-DB circ/renew test that follows would not
    # see the updated penalties.
    my $penalty_editor = new_editor(xact => 1, authtoken => $self->editor->authtoken);
    return $penalty_editor->event unless( $penalty_editor->checkauth );
    OpenILS::Utils::Penalty->calculate_penalties($penalty_editor, $self->patron->id, $self->circ_lib);
    $penalty_editor->commit;

    my $dbfunc = ($self->is_renewal) ? 
        'action.item_user_renew_test' : 'action.item_user_circ_test';

    if( $self->is_precat && $self->request_precat) {
        $self->make_precat_copy;
        return if $self->bail_out;
    }

    my $results = $self->editor->json_query(
        {   from => [
                $dbfunc,
                $self->circ_lib,
                ($self->is_noncat or ($self->is_precat and !$self->override and !$self->is_renewal)) ? undef : $self->copy->id, 
                $self->patron->id,
            ]
        }
    );

    $self->circ_test_success($U->is_true($results->[0]->{success}));

    if(my $mp = $results->[0]->{matchpoint}) {
        $logger->info("circulator: circ policy test found matchpoint built via rows " . $results->[0]->{buildrows});
        $self->circ_matrix_matchpoint($self->editor->retrieve_config_circ_matrix_matchpoint($mp));
        $self->circ_matrix_matchpoint->duration_rule($self->editor->retrieve_config_rules_circ_duration($results->[0]->{duration_rule}));
        if(defined($results->[0]->{renewals})) {
            $self->circ_matrix_matchpoint->duration_rule->max_renewals($results->[0]->{renewals});
        }
        $self->circ_matrix_matchpoint->recurring_fine_rule($self->editor->retrieve_config_rules_recurring_fine($results->[0]->{recurring_fine_rule}));
        if(defined($results->[0]->{grace_period})) {
            $self->circ_matrix_matchpoint->recurring_fine_rule->grace_period($results->[0]->{grace_period});
        }
        $self->circ_matrix_matchpoint->max_fine_rule($self->editor->retrieve_config_rules_max_fine($results->[0]->{max_fine_rule}));
        if(defined($results->[0]->{hard_due_date})) {
            $self->circ_matrix_matchpoint->hard_due_date($self->editor->retrieve_config_hard_due_date($results->[0]->{hard_due_date}));
        }
        # Grab the *last* response for limit_groups, where it is more likely to be filled
        $self->limit_groups($results->[-1]->{limit_groups});
    }

    return $self->matrix_test_result($results);
}

# ---------------------------------------------------------------------
# given a use and copy, this will calculate the circulation policy
# parameters.  Only works with in-db circ.
# ---------------------------------------------------------------------
sub do_inspect {
    my $self = shift;

    return OpenILS::Event->new('ASSET_COPY_NOT_FOUND') unless $self->copy;

    $self->run_indb_circ_test;

    my $results = {
        circ_test_success => $self->circ_test_success,
        failure_events => [],
        failure_codes => [],
        matchpoint => $self->circ_matrix_matchpoint
    };

    unless($self->circ_test_success) {
        $results->{"failure_codes"} = [ $self->matrix_test_result_codes ];
        $results->{"failure_events"} = [ $self->matrix_test_result_events ];
    }

    if($self->circ_matrix_matchpoint) {
        my $duration_rule = $self->circ_matrix_matchpoint->duration_rule;
        my $recurring_fine_rule = $self->circ_matrix_matchpoint->recurring_fine_rule;
        my $max_fine_rule = $self->circ_matrix_matchpoint->max_fine_rule;
        my $hard_due_date = $self->circ_matrix_matchpoint->hard_due_date;
    
        my $policy = $self->get_circ_policy(
            $duration_rule, $recurring_fine_rule, $max_fine_rule, $hard_due_date);
    
        $$results{$_} = $$policy{$_} for keys %$policy;
    }

    return $results;
}

# ---------------------------------------------------------------------
# Loads the circ policy info for duration, recurring fine, and max
# fine based on the current copy
# ---------------------------------------------------------------------
sub get_circ_policy {
    my($self, $duration_rule, $recurring_fine_rule, $max_fine_rule, $hard_due_date) = @_;

    my $policy = {
        duration_rule => $duration_rule->name,
        recurring_fine_rule => $recurring_fine_rule->name,
        max_fine_rule => $max_fine_rule->name,
        max_fine => $self->get_max_fine_amount($max_fine_rule),
        fine_interval => $recurring_fine_rule->recurrence_interval,
        renewal_remaining => $duration_rule->max_renewals,
        auto_renewal_remaining => $duration_rule->max_auto_renewals,
        grace_period => $recurring_fine_rule->grace_period
    };

    if($hard_due_date) {
        $policy->{duration_date_ceiling} = $hard_due_date->ceiling_date;
        $policy->{duration_date_ceiling_force} = $hard_due_date->forceto;
    }
    else {
        $policy->{duration_date_ceiling} = undef;
        $policy->{duration_date_ceiling_force} = undef;
    }

    $policy->{duration} = $duration_rule->shrt
        if $self->copy->loan_duration == OILS_CIRC_DURATION_SHORT;
    $policy->{duration} = $duration_rule->normal
        if $self->copy->loan_duration == OILS_CIRC_DURATION_NORMAL;
    $policy->{duration} = $duration_rule->extended
        if $self->copy->loan_duration == OILS_CIRC_DURATION_EXTENDED;

    $policy->{recurring_fine} = $recurring_fine_rule->low
        if $self->copy->fine_level == OILS_REC_FINE_LEVEL_LOW;
    $policy->{recurring_fine} = $recurring_fine_rule->normal
        if $self->copy->fine_level == OILS_REC_FINE_LEVEL_NORMAL;
    $policy->{recurring_fine} = $recurring_fine_rule->high
        if $self->copy->fine_level == OILS_REC_FINE_LEVEL_HIGH;

    return $policy;
}

sub get_max_fine_amount {
    my $self = shift;
    my $max_fine_rule = shift;
    my $max_amount = $max_fine_rule->amount;

    # if is_percent is true then the max->amount is
    # use as a percentage of the copy price
    if ($U->is_true($max_fine_rule->is_percent)) {
        my $price = $U->get_copy_price($self->editor, $self->copy, $self->volume);
        $max_amount = $price * $max_fine_rule->amount / 100;
    } elsif (
        $U->ou_ancestor_setting_value(
            $self->circ_lib,
            'circ.max_fine.cap_at_price',
            $self->editor
        )
    ) {
        my $price = $U->get_copy_price($self->editor, $self->copy, $self->volume);
        $max_amount = ( $price && $max_amount > $price ) ? $price : $max_amount;
    }

    return $max_amount;
}



sub run_copy_permit_scripts {
    my $self = shift;
    my $copy = $self->copy || return;

    my @allevents;

    my $results = $self->run_indb_circ_test;
    push @allevents, $self->matrix_test_result_events
        unless $self->circ_test_success;

    # See if this copy has an alert message
    my $ae = $self->check_copy_alert();
    push( @allevents, $ae ) if $ae;

    # uniquify the events
    my %hash = map { ($_->{ilsevent} => $_) } @allevents;
    @allevents = values %hash;

    $logger->info("circulator: permit_copy script returned events: @allevents") if @allevents;

    $self->push_events(@allevents);
}


sub check_copy_alert {
    my $self = shift;

    if ($self->new_copy_alerts) {
        my @alerts;
        push @alerts, @{$self->user_copy_alerts} # we have preexisting alerts 
            if ($self->user_copy_alerts && @{$self->user_copy_alerts});

        push @alerts, @{$self->system_copy_alerts} # we have new dynamic alerts 
            if ($self->system_copy_alerts && @{$self->system_copy_alerts});

        if (@alerts) {
            $self->bail_out(1) if (!$self->override);
            return OpenILS::Event->new( 'COPY_ALERT_MESSAGE', payload => \@alerts);
        }
    }

    return undef if $self->is_renewal;
    return OpenILS::Event->new(
        'COPY_ALERT_MESSAGE', payload => $self->copy->alert_message)
        if $self->copy and $self->copy->alert_message;
    return undef;
}



# --------------------------------------------------------------------------
# If the call is overriding and has permissions to override every collected
# event, the are cleared.  Any event that the caller does not have
# permission to override, will be left in the event list and bail_out will
# be set
# XXX We need code in here to cancel any holds/transits on copies 
# that are being force-checked out
# --------------------------------------------------------------------------
sub override_events {
    my $self = shift;
    my @events = @{$self->events};
    return unless @events;
    my $oargs = $self->override_args;

    if(!$self->override) {
        return $self->bail_out(1) 
            if( @events > 1 or $events[0]->{textcode} ne 'SUCCESS' );
    }   

    $self->events([]);
    
    for my $e (@events) {
        my $tc = $e->{textcode};
        next if $tc eq 'SUCCESS';
        if($oargs->{all} || grep { $_ eq $tc } @{$oargs->{events}}) {
            my $ov = "$tc.override";
            $logger->info("circulator: attempting to override event: $ov");

            return $self->bail_on_events($self->editor->event)
                unless( $self->editor->allowed($ov) );
        } else {
            return $self->bail_out(1);
        }
   }
}
    

# --------------------------------------------------------------------------
# If there is an open claimsreturn circ on the requested copy, close the 
# circ if overriding, otherwise bail out
# --------------------------------------------------------------------------
sub handle_claims_returned {
    my $self = shift;
    my $copy = $self->copy;

    my $CR = $self->editor->search_action_circulation(
        {   
            target_copy     => $copy->id,
            stop_fines      => OILS_STOP_FINES_CLAIMSRETURNED,
            checkin_time    => undef,
        }
    );

    return unless ($CR = $CR->[0]); 

    my $evt;

    # - If the caller has set the override flag, we will check the item in
    if($self->override && ($self->override_args->{all} || grep { $_ eq 'CIRC_CLAIMS_RETURNED' } @{$self->override_args->{events}}) ) {

        $CR->checkin_time('now');   
        $CR->checkin_scan_time('now');   
        $CR->checkin_lib($self->circ_lib);
        $CR->checkin_workstation($self->editor->requestor->wsid);
        $CR->checkin_staff($self->editor->requestor->id);

        $evt = $self->editor->event 
            unless $self->editor->update_action_circulation($CR);

    } else {
        $evt = OpenILS::Event->new('CIRC_CLAIMS_RETURNED');
    }

    $self->bail_on_events($evt) if $evt;
    return;
}


# --------------------------------------------------------------------------
# This performs the checkout
# --------------------------------------------------------------------------
sub do_checkout {
    my $self = shift;

    $self->log_me("do_checkout()");

    # make sure perms are good if this isn't a renewal
    unless( $self->is_renewal ) {
        return $self->bail_on_events($self->editor->event)
            unless( $self->editor->allowed('COPY_CHECKOUT') );
    }

    # verify the permit key
    unless( $self->check_permit_key ) {
        if( $self->permit_override ) {
            return $self->bail_on_events($self->editor->event)
                unless $self->editor->allowed('CIRC_PERMIT_OVERRIDE');
        } else {
            return $self->bail_on_events(OpenILS::Event->new('CIRC_PERMIT_BAD_KEY'))
        }   
    }

    # if this is a non-cataloged circ, build the circ and finish
    if( $self->is_noncat ) {
        $self->checkout_noncat;
        $self->push_events(
            OpenILS::Event->new('SUCCESS', 
            payload => { noncat_circ => $self->circ }));
        return;
    }

    if( $self->is_precat ) {
        $self->make_precat_copy;
        return if $self->bail_out;

    } elsif( $self->copy->call_number == OILS_PRECAT_CALL_NUMBER ) {
        return $self->bail_on_events(OpenILS::Event->new('ITEM_NOT_CATALOGED'));
    }

    $self->do_copy_checks;
    return if $self->bail_out;

    $self->run_checkout_scripts();
    return if $self->bail_out;

    $self->build_checkout_circ_object();
    return if $self->bail_out;

    my $modify_to_start = $self->booking_adjusted_due_date();
    return if $self->bail_out;

    $self->apply_modified_due_date($modify_to_start);
    return if $self->bail_out;

    return $self->bail_on_events($self->editor->event)
        unless $self->editor->create_action_circulation($self->circ);

    # refresh the circ to force local time zone for now
    $self->circ($self->editor->retrieve_action_circulation($self->circ->id));

    if($self->limit_groups) {
        $self->editor->json_query({ from => ['action.link_circ_limit_groups', $self->circ->id, $self->limit_groups] });
    }

    $self->copy->status(OILS_COPY_STATUS_CHECKED_OUT);
    $self->update_copy;
    return if $self->bail_out;

    $self->apply_deposit_fee();
    return if $self->bail_out;

    $self->handle_checkout_holds();
    return if $self->bail_out;

    # ------------------------------------------------------------------------------
    # Update the patron penalty info in the DB, now that the item is checked out and
    # may cause the patron to reach certain thresholds.
    # ------------------------------------------------------------------------------
    OpenILS::Utils::Penalty->calculate_penalties($self->editor, $self->patron->id, $self->circ_lib);

    my $record = $U->record_to_mvr($self->title) unless $self->is_precat;
    
    my $pcirc;
    if($self->is_renewal) {
        # flesh the billing summary for the checked-in circ
        $pcirc = $self->editor->retrieve_action_circulation([
            $self->parent_circ,
            {flesh => 2, flesh_fields => {circ => ['billable_transaction'], mbt => ['summary']}}
        ]);
    }

    $self->push_events(
        OpenILS::Event->new('SUCCESS',
            payload  => {
                copy             => $U->unflesh_copy($self->copy),
                volume           => $self->volume,
                circ             => $self->circ,
                record           => $record,
                holds_fulfilled  => $self->fulfilled_holds,
                deposit_billing  => $self->deposit_billing,
                rental_billing   => $self->rental_billing,
                parent_circ      => $pcirc,
                patron           => ($self->return_patron) ? $self->patron : undef,
                patron_money     => $self->editor->retrieve_money_user_summary($self->patron->id)
            }
        )
    );
}

sub apply_deposit_fee {
    my $self = shift;
    my $copy = $self->copy;
    return unless 
        ($self->is_deposit and not $self->is_deposit_exempt) or 
        ($self->is_rental and not $self->is_rental_exempt);

    return if $self->is_deposit and $self->skip_deposit_fee;
    return if $self->is_rental and $self->skip_rental_fee;

    my $bill = Fieldmapper::money::billing->new;
    my $amount = $copy->deposit_amount;
    my $billing_type;
    my $btype;

    if($self->is_deposit) {
        $billing_type = OILS_BILLING_TYPE_DEPOSIT;
        $btype = 5;
        $self->deposit_billing($bill);
    } else {
        $billing_type = OILS_BILLING_TYPE_RENTAL;
        $btype = 6;
        $self->rental_billing($bill);
    }

    $bill->xact($self->circ->id);
    $bill->amount($amount);
    $bill->note(OILS_BILLING_NOTE_SYSTEM);
    $bill->billing_type($billing_type);
    $bill->btype($btype);
    $self->editor->create_money_billing($bill) or $self->bail_on_events($self->editor->event);

    $logger->info("circulator: charged $amount on checkout with billing type $billing_type");
}

sub update_copy {
    my $self = shift;
    my $copy = $self->copy;

    my $stat = $copy->status if ref $copy->status;
    my $loc = $copy->location if ref $copy->location;
    my $circ_lib = $copy->circ_lib if ref $copy->circ_lib;

    $copy->status($stat->id) if $stat;
    $copy->location($loc->id) if $loc;
    $copy->circ_lib($circ_lib->id) if $circ_lib;
    $copy->editor($self->editor->requestor->id);
    $copy->edit_date('now');
    $copy->age_protect($copy->age_protect->id) if ref $copy->age_protect;

    return $self->bail_on_events($self->editor->event)
        unless $self->editor->update_asset_copy($self->copy);

    $copy->status($U->copy_status($copy->status));
    $copy->location($loc) if $loc;
    $copy->circ_lib($circ_lib) if $circ_lib;
}

sub update_reservation {
    my $self = shift;
    my $reservation = $self->reservation;

    my $usr = $reservation->usr;
    my $target_rt = $reservation->target_resource_type;
    my $target_r = $reservation->target_resource;
    my $current_r = $reservation->current_resource;

    $reservation->usr($usr->id) if ref $usr;
    $reservation->target_resource_type($target_rt->id) if ref $target_rt;
    $reservation->target_resource($target_r->id) if ref $target_r;
    $reservation->current_resource($current_r->id) if ref $current_r;

    return $self->bail_on_events($self->editor->event)
        unless $self->editor->update_booking_reservation($self->reservation);

    my $evt;
    ($reservation, $evt) = $U->fetch_booking_reservation($reservation->id);
    $self->reservation($reservation);
}


sub bail_on_events {
    my( $self, @evts ) = @_;
    $self->push_events(@evts);
    $self->bail_out(1);
}

# ------------------------------------------------------------------------------
# A hold FULFILL block is just like a CIRC block, except that FULFILL only
# affects copies that will fulfill holds and CIRC affects all other copies.
# If blocks exists, bail, push Events onto the event pile, and return true.
# ------------------------------------------------------------------------------
sub check_hold_fulfill_blocks {
    my $self = shift;

    # With the addition of ignore_proximity in csp, we need to fetch
    # the proximity of both the circ_lib and the copy's circ_lib to
    # the patron's home_ou.
    my ($ou_prox, $copy_prox);
    my $home_ou = (ref($self->patron->home_ou)) ? $self->patron->home_ou->id : $self->patron->home_ou;
    $ou_prox = $U->get_org_unit_proximity($self->editor, $home_ou, $self->circ_lib);
    $ou_prox = -1 unless (defined($ou_prox));
    my $copy_ou = (ref($self->copy->circ_lib)) ? $self->copy->circ_lib->id : $self->copy->circ_lib;
    if ($copy_ou == $self->circ_lib) {
        # Save us the time of an extra query.
        $copy_prox = $ou_prox;
    } else {
        $copy_prox = $U->get_org_unit_proximity($self->editor, $home_ou, $copy_ou);
        $copy_prox = -1 unless (defined($copy_prox));
    }

    # See if the user has any penalties applied that prevent hold fulfillment
    my $pens = $self->editor->json_query({
        select => {csp => ['name', 'label']},
        from => {ausp => {csp => {}}},
        where => {
            '+ausp' => {
                usr => $self->patron->id,
                org_unit => $U->get_org_full_path($self->circ_lib),
                '-or' => [
                    {stop_date => undef},
                    {stop_date => {'>' => 'now'}}
                ]
            },
            '+csp' => {
                block_list => {'like' => '%FULFILL%'},
                '-or' => [
                    {ignore_proximity => undef},
                    {ignore_proximity => {'<' => $ou_prox}},
                    {ignore_proximity => {'<' => $copy_prox}}
                ]
            }
        }
    });

    return 0 unless @$pens;

    for my $pen (@$pens) {
        $logger->info("circulator: patron has hold FULFILL block " . $pen->{name});
        my $event = OpenILS::Event->new($pen->{name});
        $event->{desc} = $pen->{label};
        $self->push_events($event);
    }

    $self->override_events;
    return $self->bail_out;
}


# ------------------------------------------------------------------------------
# When an item is checked out, see if we can fulfill a hold for this patron
# ------------------------------------------------------------------------------
sub handle_checkout_holds {
   my $self    = shift;
   my $copy    = $self->copy;
   my $patron  = $self->patron;

   my $e = $self->editor;
   $self->fulfilled_holds([]);

   # non-cats can't fulfill a hold
   return if $self->is_noncat;

    my $hold = $e->search_action_hold_request({   
        current_copy        => $copy->id , 
        cancel_time         => undef, 
        fulfillment_time    => undef
    })->[0];

    if($hold and $hold->usr != $patron->id) {
        # reset the hold since the copy is now checked out
    
        $logger->info("circulator: un-targeting hold ".$hold->id.
            " because copy ".$copy->id." is getting checked out");

        $U->simplereq('open-ils.circ',
            'open-ils.circ.hold_reset_reason_entry.create',
            $e->authtoken,
            $hold->id,
            OILS_HOLD_CHECK_OUT,
            "Checked out to patron #".$patron->id
        );
        $hold->clear_prev_check_time; 
        $hold->clear_current_copy;
        $hold->clear_capture_time;
        $hold->clear_shelf_time;
        $hold->clear_shelf_expire_time;
        $hold->clear_current_shelf_lib;

        return $self->bail_on_event($e->event)
            unless $e->update_action_hold_request($hold);

        $hold = undef;
    }

    unless($hold) {
        $hold = $self->find_related_user_hold($copy, $patron) or return;
        $logger->info("circulator: found related hold to fulfill in checkout");
    }

    return if $self->check_hold_fulfill_blocks;

    $logger->debug("circulator: checkout fulfilling hold " . $hold->id);

    # if the hold was never officially captured, capture it.
    $hold->clear_hopeless_date;
    $hold->current_copy($copy->id);
    $hold->capture_time('now') unless $hold->capture_time;
    $hold->fulfillment_time('now');
    $hold->fulfillment_staff($e->requestor->id);
    $hold->fulfillment_lib($self->circ_lib);

    return $self->bail_on_events($e->event)
        unless $e->update_action_hold_request($hold);

    return $self->fulfilled_holds([$hold->id]);
}


# ------------------------------------------------------------------------------
# If the circ.checkout_fill_related_hold setting is turned on and no hold for
# the patron directly targets the checked out item, see if there is another hold 
# for the patron that could be fulfilled by the checked out item.  Fulfill the
# oldest hold and only fulfill 1 of them.
# 
# For "another hold":
#
# First, check for one that the copy matches via hold_copy_map, ensuring that
# *any* hold type that this copy could fill may end up filled.
#
# Then, if circ.checkout_fill_related_hold_exact_match_only is not enabled, look
# for a Title (T) or Volume (V) hold that matches the item. This allows items
# that are non-requestable to count as capturing those hold types.
# ------------------------------------------------------------------------------
sub find_related_user_hold {
    my($self, $copy, $patron) = @_;
    my $e = $self->editor;

    # holds on precat copies are always copy-level, so this call will
    # always return undef.  Exit early.
    return undef if $self->is_precat;

    return undef unless $U->ou_ancestor_setting_value(        
        $self->circ_lib, 'circ.checkout_fills_related_hold', $e);

    # find the oldest unfulfilled hold that has not yet hit the holds shelf.
    my $args = {
        select => {ahr => ['id']}, 
        from => {
            ahr => {
                ahcm => {
                    field => 'hold',
                    fkey => 'id'
                },
                acp => {
                    field => 'id', 
                    fkey => 'current_copy',
                    type => 'left' # there may be no current_copy
                }
            }
        }, 
        where => {
            '+ahr' => {
                usr => $patron->id,
                fulfillment_time => undef,
                cancel_time => undef,
               '-or' => [
                    {expire_time => undef},
                    {expire_time => {'>' => 'now'}}
                ]
            },
            '+ahcm' => {
                target_copy => $self->copy->id
            },
            '+acp' => {
                '-or' => [
                    {id => undef}, # left-join copy may be nonexistent
                    {status => {'!=' => OILS_COPY_STATUS_ON_HOLDS_SHELF}},
                ]
            }
        },
        order_by => {ahr => {request_time => {direction => 'asc'}}},
        limit => 1
    };

    my $hold_info = $e->json_query($args)->[0];
    return $e->retrieve_action_hold_request($hold_info->{id}) if $hold_info;
    return undef if $U->ou_ancestor_setting_value(        
        $self->circ_lib, 'circ.checkout_fills_related_hold_exact_match_only', $e);

    # find the oldest unfulfilled hold that has not yet hit the holds shelf.
    $args = {
        select => {ahr => ['id']}, 
        from => {
            ahr => {
                acp => {
                    field => 'id', 
                    fkey => 'current_copy',
                    type => 'left' # there may be no current_copy
                }
            }
        }, 
        where => {
            '+ahr' => {
                usr => $patron->id,
                fulfillment_time => undef,
                cancel_time => undef,
               '-or' => [
                    {expire_time => undef},
                    {expire_time => {'>' => 'now'}}
                ]
            },
            '-or' => [
                {
                    '+ahr' => { 
                        hold_type => 'V',
                        target => $self->volume->id
                    }
                },
                { 
                    '+ahr' => { 
                        hold_type => 'T',
                        target => $self->title->id
                    }
                },
            ],
            '+acp' => {
                '-or' => [
                    {id => undef}, # left-join copy may be nonexistent
                    {status => {'!=' => OILS_COPY_STATUS_ON_HOLDS_SHELF}},
                ]
            }
        },
        order_by => {ahr => {request_time => {direction => 'asc'}}},
        limit => 1
    };

    $hold_info = $e->json_query($args)->[0];
    return $e->retrieve_action_hold_request($hold_info->{id}) if $hold_info;
    return undef;
}


sub run_checkout_scripts {
    my $self = shift;
    my $nobail = shift;

    my $evt;

    my $duration;
    my $recurring;
    my $max_fine;
    my $hard_due_date;
    my $duration_name;
    my $recurring_name;
    my $max_fine_name;
    my $hard_due_date_name;

    $self->run_indb_circ_test();
    $duration = $self->circ_matrix_matchpoint->duration_rule;
    $recurring = $self->circ_matrix_matchpoint->recurring_fine_rule;
    $max_fine = $self->circ_matrix_matchpoint->max_fine_rule;
    $hard_due_date = $self->circ_matrix_matchpoint->hard_due_date;

    $duration_name = $duration->name if $duration;
    if( $duration_name ne OILS_UNLIMITED_CIRC_DURATION ) {

        unless($duration) {
            ($duration, $evt) = $U->fetch_circ_duration_by_name($duration_name);
            return $self->bail_on_events($evt) if ($evt && !$nobail);
        
            ($recurring, $evt) = $U->fetch_recurring_fine_by_name($recurring_name);
            return $self->bail_on_events($evt) if ($evt && !$nobail);
        
            ($max_fine, $evt) = $U->fetch_max_fine_by_name($max_fine_name);
            return $self->bail_on_events($evt) if ($evt && !$nobail);

            if($hard_due_date_name) {
                ($hard_due_date, $evt) = $U->fetch_hard_due_date_by_name($hard_due_date_name);
                return $self->bail_on_events($evt) if ($evt && !$nobail);
            }
        }

    } else {

        # The item circulates with an unlimited duration
        $duration   = undef;
        $recurring  = undef;
        $max_fine   = undef;
        $hard_due_date = undef;
    }

   $self->duration_rule($duration);
   $self->recurring_fines_rule($recurring);
   $self->max_fine_rule($max_fine);
   $self->hard_due_date($hard_due_date);
}


sub build_checkout_circ_object {
    my $self = shift;

   my $circ       = Fieldmapper::action::circulation->new;
   my $duration   = $self->duration_rule;
   my $max        = $self->max_fine_rule;
   my $recurring  = $self->recurring_fines_rule;
   my $hard_due_date    = $self->hard_due_date;
   my $copy       = $self->copy;
   my $patron     = $self->patron;
   my $duration_date_ceiling;
   my $duration_date_ceiling_force;

    if( $duration ) {

        my $policy = $self->get_circ_policy($duration, $recurring, $max, $hard_due_date);
        $duration_date_ceiling = $policy->{duration_date_ceiling};
        $duration_date_ceiling_force = $policy->{duration_date_ceiling_force};

        my $dname = $duration->name;
        my $mname = $max->name;
        my $rname = $recurring->name;
        my $hdname = ''; 
        if($hard_due_date) {
            $hdname = $hard_due_date->name;
        }

        $logger->debug("circulator: building circulation ".
            "with duration=$dname, maxfine=$mname, recurring=$rname, hard due date=$hdname");
    
        $circ->duration($policy->{duration});
        $circ->recurring_fine($policy->{recurring_fine});
        $circ->duration_rule($duration->name);
        $circ->recurring_fine_rule($recurring->name);
        $circ->max_fine_rule($max->name);
        $circ->max_fine($policy->{max_fine});
        $circ->fine_interval($recurring->recurrence_interval);
        $circ->renewal_remaining($duration->max_renewals);
        $circ->auto_renewal_remaining($duration->max_auto_renewals);
        $circ->grace_period($policy->{grace_period});

    } else {

        $logger->info("circulator: copy found with an unlimited circ duration");
        $circ->duration_rule(OILS_UNLIMITED_CIRC_DURATION);
        $circ->recurring_fine_rule(OILS_UNLIMITED_CIRC_DURATION);
        $circ->max_fine_rule(OILS_UNLIMITED_CIRC_DURATION);
        $circ->renewal_remaining(0);
        $circ->grace_period(0);
    }

   $circ->target_copy( $copy->id );
   $circ->usr( $patron->id );
   $circ->circ_lib( $self->circ_lib );
   $circ->workstation($self->editor->requestor->wsid) 
    if defined $self->editor->requestor->wsid;

    # renewals maintain a link to the parent circulation
    $circ->parent_circ($self->parent_circ);

   if( $self->is_renewal ) {
      $circ->opac_renewal('t') if $self->opac_renewal;
      $circ->phone_renewal('t') if $self->phone_renewal;
      $circ->desk_renewal('t') if $self->desk_renewal;
      $circ->auto_renewal('t') if $self->auto_renewal;
      $circ->renewal_remaining($self->renewal_remaining);
      $circ->auto_renewal_remaining($self->auto_renewal_remaining);
      $circ->circ_staff($self->editor->requestor->id);
   }

    # if the user provided an overiding checkout time,
    # (e.g. the checkout really happened several hours ago), then
    # we apply that here.  Does this need a perm??
    $circ->xact_start(clean_ISO8601($self->checkout_time))
        if $self->checkout_time;

    # if a patron is renewing, 'requestor' will be the patron
    $circ->circ_staff($self->editor->requestor->id);
    $circ->due_date( $self->create_due_date($circ->duration, $duration_date_ceiling, $duration_date_ceiling_force, $circ->xact_start) ) if $circ->duration;

    $self->circ($circ);
}

sub do_reservation_pickup {
    my $self = shift;

    $self->log_me("do_reservation_pickup()");

    $self->reservation->pickup_time('now');

    if (
        $self->reservation->current_resource &&
        $U->is_true($self->reservation->target_resource_type->catalog_item)
    ) {
        # We used to try to set $self->copy and $self->patron here,
        # but that should already be done.

        $self->run_checkout_scripts(1);

        my $duration   = $self->duration_rule;
        my $max        = $self->max_fine_rule;
        my $recurring  = $self->recurring_fines_rule;

        if ($duration && $max && $recurring) {
            my $policy = $self->get_circ_policy($duration, $recurring, $max);

            my $dname = $duration->name;
            my $mname = $max->name;
            my $rname = $recurring->name;

            $logger->debug("circulator: updating reservation ".
                "with duration=$dname, maxfine=$mname, recurring=$rname");

            $self->reservation->fine_amount($policy->{recurring_fine});
            $self->reservation->max_fine($policy->{max_fine});
            $self->reservation->fine_interval($recurring->recurrence_interval);
        }

        $self->copy->status(OILS_COPY_STATUS_CHECKED_OUT);
        $self->update_copy();

    } else {
        $self->reservation->fine_amount(
            $self->reservation->target_resource_type->fine_amount
        );
        $self->reservation->max_fine(
            $self->reservation->target_resource_type->max_fine
        );
        $self->reservation->fine_interval(
            $self->reservation->target_resource_type->fine_interval
        );
    }

    $self->update_reservation();
}

sub do_reservation_return {
    my $self = shift;
    my $request = shift;

    $self->log_me("do_reservation_return()");

    if (not ref $self->reservation) {
        my ($reservation, $evt) =
            $U->fetch_booking_reservation($self->reservation);
        return $self->bail_on_events($evt) if $evt;
        $self->reservation($reservation);
    }

    $self->handle_fines(1);
    $self->reservation->return_time('now');
    $self->update_reservation();
    $self->reshelve_copy if $self->copy;

    if ( $self->reservation->current_resource && $self->reservation->current_resource->catalog_item ) {
        $self->copy( $self->reservation->current_resource->catalog_item );
    }
}

sub booking_adjusted_due_date {
    my $self = shift;
    my $circ = $self->circ;
    my $copy = $self->copy;

    return undef unless $self->use_booking;

    my $changed;

    if( $self->due_date ) {

        return $self->bail_on_events($self->editor->event)
            unless $self->editor->allowed('CIRC_OVERRIDE_DUE_DATE', $self->circ_lib);

       $circ->due_date(clean_ISO8601($self->due_date));

    } else {

        return unless $copy and $circ->due_date;
    }

    my $booking_items = $self->editor->search_booking_resource( { barcode => $copy->barcode } );
    if (@$booking_items) {
        my $booking_item = $booking_items->[0];
        my $resource_type = $self->editor->retrieve_booking_resource_type( $booking_item->type );

        my $stop_circ_setting = $U->ou_ancestor_setting_value( $self->circ_lib, 'circ.booking_reservation.stop_circ', $self->editor );
        my $shorten_circ_setting = $resource_type->elbow_room ||
            $U->ou_ancestor_setting_value( $self->circ_lib, 'circ.booking_reservation.default_elbow_room', $self->editor ) ||
            '0 seconds';

        my $booking_ses = OpenSRF::AppSession->create( 'open-ils.booking' );
        my $bookings = $booking_ses->request('open-ils.booking.reservations.filtered_id_list', $self->editor->authtoken, {
              resource     => $booking_item->id
            , search_start => 'now'
            , search_end   => $circ->due_date
            , fields       => { cancel_time => undef, return_time => undef }
        })->gather(1);
        $booking_ses->disconnect;

        throw OpenSRF::EX::ERROR ("Improper input arguments") unless defined $bookings;
        return $self->bail_on_events($bookings) if ref($bookings) eq 'HASH';
        
        my $dt_parser = DateTime::Format::ISO8601->new;
        my $due_date = $dt_parser->parse_datetime( clean_ISO8601($circ->due_date) );

        for my $bid (@$bookings) {

            my $booking = $self->editor->retrieve_booking_reservation( $bid );

            my $booking_start = $dt_parser->parse_datetime( clean_ISO8601($booking->start_time) );
            my $booking_end = $dt_parser->parse_datetime( clean_ISO8601($booking->end_time) );

            return $self->bail_on_events( OpenILS::Event->new('COPY_RESERVED') )
                if ($booking_start < DateTime->now);


            if ($U->is_true($stop_circ_setting)) {
                $self->bail_on_events( OpenILS::Event->new('COPY_RESERVED') ); 
            } else {
                $due_date = $booking_start->subtract( seconds => interval_to_seconds($shorten_circ_setting) );
                $self->bail_on_events( OpenILS::Event->new('COPY_RESERVED') ) if ($due_date < DateTime->now); 
            }
            
            # We set the circ duration here only to affect the logic that will
            # later (in a DB trigger) mangle the time part of the due date to
            # 11:59pm. Having any circ duration that is not a whole number of
            # days is enough to prevent the "correction."
            my $new_circ_duration = $due_date->epoch - time;
            $new_circ_duration++ if $new_circ_duration % 86400 == 0;
            $circ->duration("$new_circ_duration seconds");

            $circ->due_date(clean_ISO8601($due_date->strftime('%FT%T%z')));
            $changed = 1;
        }

        return $self->bail_on_events($self->editor->event)
            unless $self->editor->allowed('CIRC_OVERRIDE_DUE_DATE', $self->circ_lib);
    }

    return $changed;
}

sub apply_modified_due_date {
    my $self = shift;
    my $shift_earlier = shift;
    my $circ = $self->circ;
    my $copy = $self->copy;

   if( $self->due_date ) {

        return $self->bail_on_events($self->editor->event)
            unless $self->editor->allowed('CIRC_OVERRIDE_DUE_DATE', $self->circ_lib);

      $circ->due_date(clean_ISO8601($self->due_date));

   } else {

      # if the due_date lands on a day when the location is closed
      return unless $copy and $circ->due_date;

        $self->extend_renewal_due_date if $self->is_renewal;

        #my $org = (ref $copy->circ_lib) ? $copy->circ_lib->id : $copy->circ_lib;

        # due-date overlap should be determined by the location the item
        # is checked out from, not the owning or circ lib of the item
        my $org = $self->circ_lib;

      $logger->info("circulator: circ searching for closed date overlap on lib $org".
            " with an item due date of ".$circ->due_date );

      my $dateinfo = $U->storagereq(
         'open-ils.storage.actor.org_unit.closed_date.overlap', 
            $org, $circ->due_date );

      if($dateinfo) {
         $logger->info("circulator: $dateinfo : circ due data / close date overlap found : due_date=".
            $circ->due_date." start=". $dateinfo->{start}.", end=".$dateinfo->{end});

            # XXX make the behavior more dynamic
            # for now, we just push the due date to after the close date
            if ($shift_earlier) {
                $circ->due_date($dateinfo->{start});
            } else {
                $circ->due_date($dateinfo->{end});
            }
      }
   }
}

sub extend_renewal_due_date {
    my $self = shift;
    my $circ = $self->circ;
    my $matchpoint = $self->circ_matrix_matchpoint;

    return unless $U->is_true($matchpoint->renew_extends_due_date);

    my $prev_circ = $self->editor->retrieve_action_circulation($self->parent_circ);

    my $start_time = DateTime::Format::ISO8601->new
        ->parse_datetime(clean_ISO8601($prev_circ->xact_start))->epoch;

    my $prev_due_date = DateTime::Format::ISO8601->new
        ->parse_datetime(clean_ISO8601($prev_circ->due_date));

    my $due_date = DateTime::Format::ISO8601->new
        ->parse_datetime(clean_ISO8601($circ->due_date));

    my $prev_due_time = $prev_due_date->epoch;

    my $now_time = DateTime->now->epoch;

    return if $prev_due_time < $now_time; # Renewed circ was overdue.

    if (my $interval = $matchpoint->renew_extend_min_interval) {

        my $min_duration = OpenILS::Utils::DateTime->interval_to_seconds($interval);
        my $checkout_duration = $now_time - $start_time;

        if ($checkout_duration < $min_duration) {
            # Renewal occurred too early in the cycle to result in an
            # extension of the due date on the renewal.

            # If the new due date falls before the due date of
            # the previous circulation, use the due date of the prev.
            # circ so the patron does not lose time.
            my $due = $due_date < $prev_due_date ? $prev_due_date : $due_date;
            $circ->due_date($due->strftime('%FT%T%z'));

            return;
        }
    }

    # Item was checked out long enough during the previous circulation
    # to consider extending the due date of the renewal to cover the gap.

    # Amount of the previous duration that was left unused.
    my $remaining_duration = $prev_due_time - $now_time;

    $due_date->add(seconds => $remaining_duration);

    # If the calculated due date falls before the due date of the previous 
    # circulation, use the due date of the prev. circ so the patron does
    # not lose time.
    my $due = $due_date < $prev_due_date ? $prev_due_date : $due_date;

    $logger->info("circulator: renewal due date extension landed on due date: $due");

    $circ->due_date($due->strftime('%FT%T%z'));
}


sub create_due_date {
    my( $self, $duration, $date_ceiling, $force_date, $start_time ) = @_;

    # Look up circulating library's TZ, or else use client TZ, falling
    # back to server TZ
    my $tz = $U->ou_ancestor_setting_value(
        $self->circ_lib,
        'lib.timezone',
        $self->editor
    ) || 'local';

    my $due_date = $start_time ?
        DateTime::Format::ISO8601
            ->new
            ->parse_datetime(clean_ISO8601($start_time))
            ->set_time_zone($tz) :
        DateTime->now(time_zone => $tz);

    # add the circ duration
    $due_date->add(seconds => OpenILS::Utils::DateTime->interval_to_seconds($duration, $due_date));

    if($date_ceiling) {
        my $cdate = DateTime::Format::ISO8601
            ->new
            ->parse_datetime(clean_ISO8601($date_ceiling))
            ->set_time_zone($tz);

        if ($cdate > DateTime->now and ($cdate < $due_date or $U->is_true( $force_date ))) {
            $logger->info("circulator: overriding due date with date ceiling: $date_ceiling");
            $due_date = $cdate;
        }
    }

    # return ISO8601 time with timezone
    return $due_date->strftime('%FT%T%z');
}



sub make_precat_copy {
    my $self = shift;
    my $copy = $self->copy;
    return $self->bail_on_events(OpenILS::Event->new('PERM_FAILURE'))
       unless $self->editor->allowed('CREATE_PRECAT') || $self->is_renewal;

   if($copy) {
        $logger->debug("circulator: Pre-cat copy already exists in checkout: ID=" . $copy->id);

        $copy->editor($self->editor->requestor->id);
        $copy->edit_date('now');
        $copy->dummy_title($self->dummy_title || $copy->dummy_title || '');
        $copy->dummy_isbn($self->dummy_isbn || $copy->dummy_isbn || '');
        $copy->dummy_author($self->dummy_author || $copy->dummy_author || '');
        $copy->circ_modifier($self->circ_modifier || $copy->circ_modifier);
        $self->update_copy();
        return;
   }

    $logger->info("circulator: Creating a new precataloged ".
        "copy in checkout with barcode " . $self->copy_barcode);

    $copy = Fieldmapper::asset::copy->new;
    $copy->circ_lib($self->circ_lib);
    $copy->creator($self->editor->requestor->id);
    $copy->editor($self->editor->requestor->id);
    $copy->barcode($self->copy_barcode);
    $copy->call_number(OILS_PRECAT_CALL_NUMBER); 
    $copy->loan_duration(OILS_PRECAT_COPY_LOAN_DURATION);
    $copy->fine_level(OILS_PRECAT_COPY_FINE_LEVEL);

    $copy->dummy_title($self->dummy_title || "");
    $copy->dummy_author($self->dummy_author || "");
    $copy->dummy_isbn($self->dummy_isbn || "");
    $copy->circ_modifier($self->circ_modifier);


    # See if we need to override the circ_lib for the copy with a configured circ_lib
    # Setting is shortname of the org unit
    my $precat_circ_lib = $U->ou_ancestor_setting_value(
        $self->circ_lib, 'circ.pre_cat_copy_circ_lib', $self->editor);

    if($precat_circ_lib) {
        my $org = $self->editor->search_actor_org_unit({shortname => $precat_circ_lib})->[0];

        if(!$org) {
            $self->bail_on_events($self->editor->event);
            return;
        }

        $copy->circ_lib($org->id);
    }


    unless( $self->copy($self->editor->create_asset_copy($copy)) ) {
        $self->bail_out(1);
        $self->push_events($self->editor->event);
        return;
    }   
}


sub checkout_noncat {
    my $self = shift;

    my $circ;
    my $evt;

   my $lib      = $self->noncat_circ_lib || $self->circ_lib;
   my $count    = $self->noncat_count || 1;
   my $cotime   = clean_ISO8601($self->checkout_time) || "";

   $logger->info("circulator: circ creating $count noncat circs with checkout time $cotime");

   for(1..$count) {

      ( $circ, $evt ) = OpenILS::Application::Circ::NonCat::create_non_cat_circ(
         $self->editor->requestor->id, 
            $self->patron->id, 
            $lib, 
            $self->noncat_type, 
            $cotime,
            $self->editor );

        if( $evt ) {
            $self->push_events($evt);
            $self->bail_out(1);
            return; 
        }
        $self->circ($circ);
   }
}

# if an item is in transit but the status doesn't agree, then we need to fix things.
# The next two subs will hopefully do that
sub fix_broken_transit_status {
    my $self = shift;

    # Capture the transit so we don't have to fetch it again later during checkin
    # This used to live in sub check_transit_checkin_interval and later again in
    # do_checkin
    $self->transit(
        $self->editor->search_action_transit_copy(
            {target_copy => $self->copy->id, dest_recv_time => undef, cancel_time => undef}
        )->[0]
    );

    if ($self->transit && $U->copy_status($self->copy->status)->id != OILS_COPY_STATUS_IN_TRANSIT) {
        $logger->warn("circulator: we have a copy ".$self->copy->barcode.
            " that is in-transit but without the In Transit status... fixing");
        $self->copy->status(OILS_COPY_STATUS_IN_TRANSIT);
        # FIXME - do we want to make this permanent if the checkin bails?
        $self->update_copy;
    }

}
sub cancel_transit_if_circ_exists {
    my $self = shift;
    if ($self->circ && $self->transit) {
        $logger->warn("circulator: we have a copy ".$self->copy->barcode.
            " that is in-transit AND circulating... aborting the transit");
        my $circ_ses = create OpenSRF::AppSession("open-ils.circ");
        my $result = $circ_ses->request(
            "open-ils.circ.transit.abort",
            $self->editor->authtoken,
            { 'transitid' => $self->transit->id }
        )->gather(1);
        $logger->warn("circulator: transit abort result: ".$result);
        $circ_ses->disconnect;
        $self->transit(undef);
    }
}

# If a copy goes into transit and is then checked in before the transit checkin 
# interval has expired, push an event onto the overridable events list.
sub check_transit_checkin_interval {
    my $self = shift;

    # only concerned with in-transit items
    return unless $U->copy_status($self->copy->status)->id == OILS_COPY_STATUS_IN_TRANSIT;

    # no interval, no problem
    my $interval = $U->ou_ancestor_setting_value($self->circ_lib, 'circ.transit.min_checkin_interval');
    return unless $interval;

    # transit from X to X for whatever reason has no min interval
    return if $self->transit->source == $self->transit->dest;

    my $seconds = OpenILS::Utils::DateTime->interval_to_seconds($interval);
    my $t_start = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($self->transit->source_send_time));
    my $horizon = $t_start->add(seconds => $seconds);

    # See if we are still within the transit checkin forbidden range
    $self->push_events(OpenILS::Event->new('TRANSIT_CHECKIN_INTERVAL_BLOCK')) 
        if $horizon > DateTime->now;
}

# Retarget local holds at checkin
sub checkin_retarget {
    my $self = shift;
    return unless $self->retarget_mode and $self->retarget_mode =~ m/retarget/; # Retargeting?
    return unless $self->is_checkin; # Renewals need not be checked
    return if $self->capture eq 'nocapture'; # Not capturing holds anyway? Move on.
    return if $self->is_precat; # No holds for precats
    return unless $self->circ_lib == $self->copy->circ_lib; # Item isn't "home"? Don't check.
    return unless $U->is_true($self->copy->holdable); # Not holdable, shouldn't capture holds.
    my $status = $U->copy_status($self->copy->status);
    return unless $U->is_true($status->holdable); # Current status not holdable means no hold will ever target the item
    # Specifically target items that are likely new (by status ID)
    return unless $status->id == OILS_COPY_STATUS_IN_PROCESS || $self->retarget_mode =~ m/\.all/;
    my $location = $self->copy->location;
    if(!ref($location)) {
        $location = $self->editor->retrieve_asset_copy_location($self->copy->location);
        $self->copy->location($location);
    }
    return unless $U->is_true($location->holdable); # Don't bother on non-holdable locations

    # Fetch holds for the bib
    my ($result) = $holdcode->method_lookup('open-ils.circ.holds.retrieve_all_from_title')->run(
                    $self->editor->authtoken,
                    $self->title->id,
                    {
                        capture_time => undef, # No touching captured holds
                        frozen => 'f', # Don't bother with frozen holds
                        pickup_lib => $self->circ_lib # Only holds actually here
                    }); 

    # Error? Skip the step.
    return if exists $result->{"ilsevent"};

    # Assemble holds
    my $holds = [];
    foreach my $holdlist (keys %{$result}) {
        push @$holds, @{$result->{$holdlist}};
    }

    return if scalar(@$holds) == 0; # No holds, no retargeting

    # Check for parts on this copy
    my $parts = $self->editor->search_asset_copy_part_map({ target_copy => $self->copy->id });
    my %parts_hash = ();
    %parts_hash = map {$_->part, 1} @$parts if @$parts;

    # Loop over holds in request-ish order
    # Stage 1: Get them into request-ish order
    # Also grab type and target for skipping low hanging ones
    $result = $self->editor->json_query({
        "select" => { "ahr" => ["id", "hold_type", "target"] },
        "from" => { "ahr" => { "au" => { "fkey" => "usr",  "join" => "pgt"} } },
        "where" => { "id" => $holds },
        "order_by" => [
            { "class" => "pgt", "field" => "hold_priority"},
            { "class" => "ahr", "field" => "cut_in_line", "direction" => "desc", "transform" => "coalesce", "params" => ['f']},
            { "class" => "ahr", "field" => "selection_depth", "direction" => "desc"},
            { "class" => "ahr", "field" => "request_time"}
        ]
    });

    # Stage 2: Loop!
    if (ref $result eq "ARRAY" and scalar @$result) {
        foreach (@{$result}) {
            # Copy level, but not this copy?
            next if ($_->{hold_type} eq 'C' or $_->{hold_type} eq 'R' or $_->{hold_type} eq 'F'
                and $_->{target} != $self->copy->id);
            # Volume level, but not this volume?
            next if ($_->{hold_type} eq 'V' and $_->{target} != $self->volume->id);
            if(@$parts) { # We have parts?
                # Skip title holds
                next if ($_->{hold_type} eq 'T');
                # Skip part holds for parts not on this copy
                next if ($_->{hold_type} eq 'P' and not $parts_hash{$_->{target}});
            } else {
                # No parts, no part holds
                next if ($_->{hold_type} eq 'P');
            }
            # So much for easy stuff, attempt a retarget!
            $U->simplereq('open-ils.circ',
            'open-ils.circ.hold_reset_reason_entry.create', $self->editor->authtoken, $_->{id},OILS_HOLD_BETTER_HOLD);
            my $tresult = $U->simplereq(
                'open-ils.hold-targeter',
                'open-ils.hold-targeter.target', 
                {hold => $_->{id}, find_copy => $self->copy->id}
            );
            if(ref $tresult eq "ARRAY" and scalar @$tresult) {
                last if(exists $tresult->[0]->{found_copy} and $tresult->[0]->{found_copy});
            }
        }
    }
}

sub do_checkin {
    my $self = shift;
    $self->log_me("do_checkin()");

    return $self->bail_on_events(
        OpenILS::Event->new('ASSET_COPY_NOT_FOUND')) 
        unless $self->copy;

    # Never capture a deleted copy for a hold.
    $self->capture('nocapture') if $U->is_true($self->copy->deleted);

    $self->fix_broken_transit_status; # if applicable
    $self->check_transit_checkin_interval;
    $self->checkin_retarget;

    # the renew code and mk_env should have already found our circulation object
    unless( $self->circ ) {

        my $circs = $self->editor->search_action_circulation(
            { target_copy => $self->copy->id, checkin_time => undef });

        $self->circ($$circs[0]);

        # for now, just warn if there are multiple open circs on a copy
        $logger->warn("circulator: we have ".scalar(@$circs).
            " open circs for copy " .$self->copy->id."!!") if @$circs > 1;
    }
    $self->cancel_transit_if_circ_exists; # if applicable

    my $stat = $U->copy_status($self->copy->status)->id;

    # LOST (and to some extent, LONGOVERDUE) may optionally be handled
    # differently if they are already paid for.  We need to check for this
    # early since overdue generation is potentially affected.
    my $dont_change_lost_zero = 0;
    if ($stat == OILS_COPY_STATUS_LOST
        || $stat == OILS_COPY_STATUS_LOST_AND_PAID
        || $stat == OILS_COPY_STATUS_LONG_OVERDUE) {

        # LOST fine settings are controlled by the copy's circ lib, not the the
        # circulation's
        my $copy_circ_lib = (ref $self->copy->circ_lib) ?
                $self->copy->circ_lib->id : $self->copy->circ_lib;
        $dont_change_lost_zero = $U->ou_ancestor_setting_value(
            $copy_circ_lib, 'circ.checkin.lost_zero_balance.do_not_change',
            $self->editor) || 0;

        # Don't assume there's always a circ based on copy status
        if ($dont_change_lost_zero && $self->circ) {
            my ($obt) = $U->fetch_mbts($self->circ->id, $self->editor);
            $dont_change_lost_zero = 0 if( $obt and $obt->balance_owed != 0 );
        }

        $self->dont_change_lost_zero($dont_change_lost_zero);
    }

    # Check if the copy can float to here. We need this for inventory
    # and to see if the copy needs to transit or stay here later.
    my $can_float = 0;
    if ($self->copy->floating) {
        my $res = $self->editor->json_query(
            {   from =>
                [
                    'evergreen.can_float',
                    $self->copy->floating->id,
                    $self->copy->circ_lib,
                    $self->circ_lib
                ]
            }
        );
        $can_float = $U->is_true($res->[0]->{'evergreen.can_float'}) if $res;
    }

    # Do copy inventory if necessary.
    if ($self->do_inventory_update && ($self->circ_lib == $self->copy->circ_lib || $can_float)) {
        my $aci = Fieldmapper::asset::copy_inventory->new();
        $aci->inventory_date('now');
        $aci->inventory_workstation($self->editor->requestor->wsid);
        $aci->copy($self->copy->id());
        $self->editor->create_asset_copy_inventory($aci);
        $self->checkin_changed(1);
    }

    if( $self->checkin_check_holds_shelf() ) {
        $self->bail_on_events(OpenILS::Event->new('NO_CHANGE'));
        $self->hold($U->fetch_open_hold_by_copy($self->copy->id));
        if($self->fake_hold_dest) {
            $self->hold->pickup_lib($self->circ_lib);
        }
        $self->checkin_flesh_events;
        return;
    }

    unless( $self->is_renewal ) {
        return $self->bail_on_events($self->editor->event)
            unless $self->editor->allowed('COPY_CHECKIN');
    }

    $self->push_events($self->check_copy_alert());
    $self->push_events($self->check_checkin_copy_status());

    # if the circ is marked as 'claims returned', add the event to the list
    $self->push_events(OpenILS::Event->new('CIRC_CLAIMS_RETURNED'))
        if ($self->circ and $self->circ->stop_fines 
                and $self->circ->stop_fines eq OILS_STOP_FINES_CLAIMSRETURNED);

    $self->check_circ_deposit();

    # handle the overridable events 
    $self->override_events unless $self->is_renewal;
    return if $self->bail_out;
    
    if( $self->circ ) {
        $self->checkin_handle_circ_start;
        return if $self->bail_out;

        if (!$dont_change_lost_zero) {
            # if this circ is LOST and we are configured to generate overdue
            # fines for lost items on checkin (to fill the gap between mark
            # lost time and when the fines would have naturally stopped), then
            # stop_fines is no longer valid and should be cleared.
            #
            # stop_fines will be set again during the handle_fines() stage.
            # XXX should this setting come from the copy circ lib (like other
            # LOST settings), instead of the circulation circ lib?
            if ($stat == OILS_COPY_STATUS_LOST) {
                $self->circ->clear_stop_fines if
                    $U->ou_ancestor_setting_value(
                        $self->circ_lib,
                        OILS_SETTING_GENERATE_OVERDUE_ON_LOST_RETURN,
                        $self->editor
                    );
            }

            # Set stop_fines when claimed never checked out
            $self->circ->stop_fines( OILS_STOP_FINES_CLAIMS_NEVERCHECKEDOUT ) if( $self->claims_never_checked_out );

            # handle fines for this circ, including overdue gen if needed
            $self->handle_fines;
        }

        # Void any item deposits if the library wants to
        $self->check_circ_deposit(1);

        $self->checkin_handle_circ_finish;
        return if $self->bail_out;
        $self->checkin_changed(1);

    } elsif( $self->transit ) {
        my $hold_transit = $self->process_received_transit;
        $self->checkin_changed(1);

        if( $self->bail_out ) { 
            $self->checkin_flesh_events;
            return;
        }
        
        if( my $e = $self->check_checkin_copy_status() ) {
            # If the original copy status is special, alert the caller
            my $ev = $self->events;
            $self->events([$e]);
            $self->override_events;
            return if $self->bail_out;
            $self->events($ev);
        }

        if( $hold_transit or 
                $U->copy_status($self->copy->status)->id 
                    == OILS_COPY_STATUS_ON_HOLDS_SHELF ) {

            my $hold;
            if( $hold_transit ) {
               $hold = $self->editor->retrieve_action_hold_request($hold_transit->hold);
            } else {
                   ($hold) = $U->fetch_open_hold_by_copy($self->copy->id);
            }

            $self->hold($hold);

            if( $hold and ( $hold->cancel_time or $hold->fulfillment_time ) ) { # this transited hold was cancelled or filled mid-transit

                $logger->info("circulator: we received a transit on a cancelled or filled hold " . $hold->id);
                $self->reshelve_copy(1);
                $self->cancelled_hold_transit(1);
                $self->notify_hold(0); # don't notify for cancelled holds
                $self->fake_hold_dest(0);
                return if $self->bail_out;

            } elsif ($hold and $hold->hold_type eq 'R') {

                $self->copy->status(OILS_COPY_STATUS_CATALOGING);
                $self->notify_hold(0); # No need to notify
                $self->fake_hold_dest(0);
                $self->noop(1); # Don't try and capture for other holds/transits now
                $self->update_copy();
                $hold->fulfillment_time('now');
                $self->bail_on_events($self->editor->event)
                    unless $self->editor->update_action_hold_request($hold);

            } else {

                # hold transited to correct location
                if($self->fake_hold_dest) {
                    $hold->pickup_lib($self->circ_lib);
                }
                $self->checkin_flesh_events;
                return;
            }
        } 

    } elsif( $U->copy_status($self->copy->status)->id == OILS_COPY_STATUS_IN_TRANSIT ) {

        $logger->warn("circulator: we have a copy ".$self->copy->barcode.
            " that is in-transit, but there is no transit.. repairing");
        $self->reshelve_copy(1);
        return if $self->bail_out;
    }

    if( $self->is_renewal ) {
        $self->finish_fines_and_voiding;
        return if $self->bail_out;
        $self->push_events(OpenILS::Event->new('SUCCESS'));
        return;
    }

   # ------------------------------------------------------------------------------
   # Circulations and transits are now closed where necessary.  Now go on to see if
   # this copy can fulfill a hold or needs to be routed to a different location
   # ------------------------------------------------------------------------------

    my $needed_for_something = 0; # formerly "needed_for_hold"

    if(!$self->noop) { # /not/ a no-op checkin, capture for hold or put item into transit

        if (!$self->remote_hold) {
            if ($self->use_booking) {
                my $potential_hold = $self->hold_capture_is_possible;
                my $potential_reservation = $self->reservation_capture_is_possible;

                if ($potential_hold and $potential_reservation) {
                    $logger->info("circulator: item could fulfill either hold or reservation");
                    $self->push_events(new OpenILS::Event(
                        "HOLD_RESERVATION_CONFLICT",
                        "hold" => $potential_hold,
                        "reservation" => $potential_reservation
                    ));
                    return if $self->bail_out;
                } elsif ($potential_hold) {
                    $needed_for_something =
                        $self->attempt_checkin_hold_capture;
                } elsif ($potential_reservation) {
                    $needed_for_something =
                        $self->attempt_checkin_reservation_capture;
                }
            } else {
                $needed_for_something = $self->attempt_checkin_hold_capture;
            }
        }
        return if $self->bail_out;
    
        unless($needed_for_something) {
            my $circ_lib = (ref $self->copy->circ_lib) ? 
                    $self->copy->circ_lib->id : $self->copy->circ_lib;
    
            if( $self->remote_hold ) {
                $circ_lib = $self->remote_hold->pickup_lib;
                $logger->warn("circulator: Copy ".$self->copy->barcode.
                    " is on a remote hold's shelf, sending to $circ_lib");
            }
    
            $logger->debug("circulator: circlib=$circ_lib, workstation=".$self->circ_lib);

            my $suppress_transit = 0;

            if( $circ_lib != $self->circ_lib and not ($self->hold_as_transit and $self->remote_hold) ) {
                my $suppress_transit_source = $U->ou_ancestor_setting($self->circ_lib, 'circ.transit.suppress_non_hold');
                if($suppress_transit_source && $suppress_transit_source->{value}) {
                    my $suppress_transit_dest = $U->ou_ancestor_setting($circ_lib, 'circ.transit.suppress_non_hold');
                    if($suppress_transit_dest && $suppress_transit_source->{value} eq $suppress_transit_dest->{value}) {
                        $logger->info("circulator: copy is within transit suppress group: ".$self->copy->barcode." ".$suppress_transit_source->{value});
                        $suppress_transit = 1;
                    }
                }
            }
 
            if( $suppress_transit or ( $circ_lib == $self->circ_lib and not ($self->hold_as_transit and $self->remote_hold) ) ) {
                # copy is where it needs to be, either for hold or reshelving
    
                $self->checkin_handle_precat();
                return if $self->bail_out;
    
            } else {
                # copy needs to transit "home", or stick here if it's a floating copy
                if ($can_float && ($self->manual_float || !$U->is_true($self->copy->floating->manual)) && !$self->remote_hold) { # Yep, floating, stick here
                    $self->checkin_changed(1);
                    $self->copy->circ_lib( $self->circ_lib );
                    $self->update_copy;
                } else {
                    my $bc = $self->copy->barcode;
                    $logger->info("circulator: copy $bc at the wrong location, sending to $circ_lib");
                    $self->checkin_build_copy_transit($circ_lib);
                    return if $self->bail_out;
                    $self->push_events(OpenILS::Event->new('ROUTE_ITEM', org => $circ_lib));
                }
            }
        }
    } else { # no-op checkin
        # XXX floating items still stick where they are even with no-op checkin?
        if ($self->copy->floating && $can_float) {
            $self->checkin_changed(1);
            $self->copy->circ_lib( $self->circ_lib );
            $self->update_copy;
        }
    }

    if($self->claims_never_checked_out and 
            $U->ou_ancestor_setting_value($self->circ->circ_lib, 'circ.claim_never_checked_out.mark_missing')) {

        # the item was not supposed to be checked out to the user and should now be marked as missing
        my $next_status = $self->next_copy_status->[0] || OILS_COPY_STATUS_MISSING;
        $self->copy->status($next_status);
        $self->update_copy;

    } else {
        $self->reshelve_copy unless $needed_for_something;
    }

    return if $self->bail_out;

    unless($self->checkin_changed) {

        $self->push_events(OpenILS::Event->new('NO_CHANGE'));
        my $stat = $U->copy_status($self->copy->status)->id;

        $self->hold($U->fetch_open_hold_by_copy($self->copy->id))
         if( $stat == OILS_COPY_STATUS_ON_HOLDS_SHELF );
        $self->bail_out(1); # no need to commit anything

    } else {

        $self->push_events(OpenILS::Event->new('SUCCESS')) 
            unless @{$self->events};
    }

    $self->finish_fines_and_voiding;

    OpenILS::Utils::Penalty->calculate_penalties(
        $self->editor, $self->patron->id, $self->circ_lib) if $self->patron;

    $self->checkin_flesh_events;
    return;
}

sub finish_fines_and_voiding {
    my $self = shift;
    return unless $self->circ;

    return unless $self->backdate or $self->void_overdues;

    # void overdues after fine generation to prevent concurrent DB access to overdue billings
    my $note = 'System: Amnesty Checkin' if $self->void_overdues;

    my $evt = $CC->void_or_zero_overdues(
        $self->editor, $self->circ, {backdate => $self->void_overdues ? undef : $self->backdate, note => $note});

    return $self->bail_on_events($evt) if $evt;

    # Make sure the circ is open or closed as necessary.
    $evt = $U->check_open_xact($self->editor, $self->circ->id);
    return $self->bail_on_events($evt) if $evt;

    return undef;
}


# if a deposit was paid for this item, push the event
# if called with a truthy param perform the void, depending on settings
sub check_circ_deposit {
    my $self = shift;
    my $void = shift;

    return unless $self->circ;

    my $deposit = $self->editor->search_money_billing(
        {   btype => 5, 
            xact => $self->circ->id, 
            voided => 'f'
        }, {idlist => 1})->[0];

    return unless $deposit;

    if ($void) {
         my $void_on_checkin = $U->ou_ancestor_setting_value(
             $self->circ_lib,OILS_SETTING_VOID_ITEM_DEPOSIT_ON_CHECKIN,$self->editor);
         if ( $void_on_checkin ) {
            my $evt = $CC->void_bills($self->editor,[$deposit], "DEPOSIT ITEM RETURNED");
            return $evt if $evt;
        }
    } else { # if void is unset this is just a check, notify that there was a deposit billing
        $self->push_events(OpenILS::Event->new('ITEM_DEPOSIT_PAID', payload => $deposit));
    }
}

sub reshelve_copy {
   my $self    = shift;
   my $force   = $self->force || shift;
   my $copy    = $self->copy;

   my $stat = $U->copy_status($copy->status)->id;

   my $next_status = $self->next_copy_status->[0] || OILS_COPY_STATUS_RESHELVING;

   if($force || (
      $stat != OILS_COPY_STATUS_ON_HOLDS_SHELF and
      $stat != OILS_COPY_STATUS_CATALOGING and
      $stat != OILS_COPY_STATUS_IN_TRANSIT and
      $stat != $next_status  )) {

        $copy->status( $next_status );
            $self->update_copy;
            $self->checkin_changed(1);
    }
}


# Returns true if the item is at the current location
# because it was transited there for a hold and the 
# hold has not been fulfilled
sub checkin_check_holds_shelf {
    my $self = shift;
    return 0 unless $self->copy;

    return 0 unless 
        $U->copy_status($self->copy->status)->id ==
            OILS_COPY_STATUS_ON_HOLDS_SHELF;

    # Attempt to clear shelf expired holds for this copy
    $holdcode->method_lookup('open-ils.circ.hold.clear_shelf.process')->run($self->editor->authtoken, $self->circ_lib, $self->copy->id)
        if($self->clear_expired);

    # find the hold that put us on the holds shelf
    my $holds = $self->editor->search_action_hold_request(
        { 
            current_copy => $self->copy->id,
            capture_time => { '!=' => undef },
            fulfillment_time => undef,
            cancel_time => undef,
        }
    );

    unless(@$holds) {
        $logger->warn("circulator: copy is on-holds-shelf, but there is no hold - reshelving");
        $self->reshelve_copy(1);
        return 0;
    }

    my $hold = $$holds[0];

    $logger->info("circulator: we found a captured, un-fulfilled hold [".
        $hold->id. "] for copy ".$self->copy->barcode);

    if( $hold->pickup_lib != $self->circ_lib and not $self->hold_as_transit ) {
        my $suppress_transit_circ = $U->ou_ancestor_setting($self->circ_lib, 'circ.transit.suppress_hold');
        if($suppress_transit_circ && $suppress_transit_circ->{value}) {
            my $suppress_transit_pickup = $U->ou_ancestor_setting($hold->pickup_lib, 'circ.transit.suppress_hold');
            if($suppress_transit_pickup && $suppress_transit_circ->{value} eq $suppress_transit_pickup->{value}) {
                $logger->info("circulator: hold is within hold transit suppress group .. we're done: ".$self->copy->barcode." ".$suppress_transit_circ->{value});
                $self->fake_hold_dest(1);
                return 1;
            }
        }
    }

    if( $hold->pickup_lib == $self->circ_lib and not $self->hold_as_transit ) {
        $logger->info("circulator: hold is for here .. we're done: ".$self->copy->barcode);
        return 1;
    }

    $logger->info("circulator: hold is not for here..");
    $self->remote_hold($hold);
    return 0;
}


sub checkin_handle_precat {
    my $self    = shift;
   my $copy    = $self->copy;

   if( $self->is_precat and ($copy->status != OILS_COPY_STATUS_CATALOGING) ) {
        $copy->status(OILS_COPY_STATUS_CATALOGING);
        $self->update_copy();
        $self->checkin_changed(1);
        $self->push_events(OpenILS::Event->new('ITEM_NOT_CATALOGED'));
   }
}


sub checkin_build_copy_transit {
    my $self            = shift;
    my $dest            = shift;
    my $copy       = $self->copy;
    my $transit    = Fieldmapper::action::transit_copy->new;

    # if we are transiting an item to the shelf shelf, it's a hold transit
    if (my $hold = $self->remote_hold) {
        $transit = Fieldmapper::action::hold_transit_copy->new;
        $transit->hold($hold->id);

        # the item is going into transit, remove any shelf-iness
        if ($hold->current_shelf_lib or $hold->shelf_time) {
            $hold->clear_current_shelf_lib;
            $hold->clear_shelf_time;
            return $self->bail_on_events($self->editor->event)
                unless $self->editor->update_action_hold_request($hold);
        }
    }

    #$dest  ||= (ref($copy->circ_lib)) ? $copy->circ_lib->id : $copy->circ_lib;
    $logger->info("circulator: transiting copy to $dest");

    $transit->source($self->circ_lib);
    $transit->dest($dest);
    $transit->target_copy($copy->id);
    $transit->source_send_time('now');
    $transit->copy_status( $U->copy_status($copy->status)->id );

    $logger->debug("circulator: setting copy status on transit: ".$transit->copy_status);

    if ($self->remote_hold) {
        return $self->bail_on_events($self->editor->event)
            unless $self->editor->create_action_hold_transit_copy($transit);
    } else {
        return $self->bail_on_events($self->editor->event)
            unless $self->editor->create_action_transit_copy($transit);
    }

    # ensure the transit is returned to the caller
    $self->transit($transit);

    $copy->status(OILS_COPY_STATUS_IN_TRANSIT);
    $self->update_copy;
    $self->checkin_changed(1);
}


sub hold_capture_is_possible {
    my $self = shift;
    my $copy = $self->copy;

    # we've been explicitly told not to capture any holds
    return 0 if $self->capture eq 'nocapture';

    # See if this copy can fulfill any holds
    my $hold = $holdcode->find_nearest_permitted_hold(
        $self->editor, $copy, $self->editor->requestor, 1 # check_only
    );
    return undef if ref $hold eq "HASH" and
        $hold->{"textcode"} eq "ACTION_HOLD_REQUEST_NOT_FOUND";
    return $hold;
}

sub reservation_capture_is_possible {
    my $self = shift;
    my $copy = $self->copy;

    # we've been explicitly told not to capture any holds
    return 0 if $self->capture eq 'nocapture';

    my $booking_ses = OpenSRF::AppSession->connect("open-ils.booking");
    my $resv = $booking_ses->request(
        "open-ils.booking.reservations.could_capture",
        $self->editor->authtoken, $copy->barcode
    )->gather(1);
    $booking_ses->disconnect;
    if (ref($resv) eq "HASH" and exists $resv->{"textcode"}) {
        $self->push_events($resv);
    } else {
        return $resv;
    }
}

# returns true if the item was used (or may potentially be used 
# in subsequent calls) to capture a hold.
sub attempt_checkin_hold_capture {
    my $self = shift;
    my $copy = $self->copy;

    # we've been explicitly told not to capture any holds
    return 0 if $self->capture eq 'nocapture';

    # See if this copy can fulfill any holds
    my ($hold, undef, $retarget) = $holdcode->find_nearest_permitted_hold( 
        $self->editor, $copy, $self->editor->requestor );

    if(!$hold) {
        $logger->debug("circulator: no potential permitted".
            "holds found for copy ".$copy->barcode);
        return 0;
    }

    if($self->capture ne 'capture') {
        # see if this item is in a hold-capture-delay location
        my $location = $self->copy->location;
        if(!ref($location)) {
            $location = $self->editor->retrieve_asset_copy_location($self->copy->location);
            $self->copy->location($location);
        }
        if($U->is_true($location->hold_verify)) {
            $self->bail_on_events(
                OpenILS::Event->new('HOLD_CAPTURE_DELAYED', copy_location => $location));
            return 1;
        }
    }

    $self->retarget($retarget);

    my $suppress_transit = 0;
    if( $hold->pickup_lib != $self->circ_lib and not $self->hold_as_transit ) {
        my $suppress_transit_circ = $U->ou_ancestor_setting($self->circ_lib, 'circ.transit.suppress_hold');
        if($suppress_transit_circ && $suppress_transit_circ->{value}) {
            my $suppress_transit_pickup = $U->ou_ancestor_setting($hold->pickup_lib, 'circ.transit.suppress_hold');
            if($suppress_transit_pickup && $suppress_transit_circ->{value} eq $suppress_transit_pickup->{value}) {
                $suppress_transit = 1;
                $hold->pickup_lib($self->circ_lib);
            }
        }
    }

    $logger->info("circulator: found permitted hold ".$hold->id." for copy, capturing...");

    $hold->clear_hopeless_date;
    $hold->current_copy($copy->id);
    $hold->capture_time('now');
    $self->put_hold_on_shelf($hold) 
        if ($suppress_transit || ($hold->pickup_lib == $self->circ_lib and not $self->hold_as_transit) );

    # prevent DB errors caused by fetching 
    # holds from storage, and updating through cstore
    $hold->clear_fulfillment_time;
    $hold->clear_fulfillment_staff;
    $hold->clear_fulfillment_lib;
    $hold->clear_expire_time; 
    $hold->clear_cancel_time;
    $hold->clear_prev_check_time unless $hold->prev_check_time;

    $U->simplereq('open-ils.circ',
    'open-ils.circ.hold_reset_reason_entry.create', $self->editor->authtoken, $hold->id, OILS_HOLD_CHECK_IN);
    $self->bail_on_events($self->editor->event)
        unless $self->editor->update_action_hold_request($hold);
    $self->hold($hold);
    $self->checkin_changed(1);

    return 0 if $self->bail_out;

    if( $suppress_transit or ( $hold->pickup_lib == $self->circ_lib && not $self->hold_as_transit ) ) {

        if ($hold->hold_type eq 'R') {
            $copy->status(OILS_COPY_STATUS_CATALOGING);
            $hold->fulfillment_time('now');
            $self->noop(1); # Block other transit/hold checks
            $self->bail_on_events($self->editor->event)
                unless $self->editor->update_action_hold_request($hold);
        } else {
            # This hold was captured in the correct location
            $copy->status(OILS_COPY_STATUS_ON_HOLDS_SHELF);
            $self->push_events(OpenILS::Event->new('SUCCESS'));

            #$self->do_hold_notify($hold->id);
            $self->notify_hold($hold->id);
        }

    } else {
    
        # Hold needs to be picked up elsewhere.  Build a hold
        # transit and route the item.
        $self->checkin_build_hold_transit();
        $copy->status(OILS_COPY_STATUS_IN_TRANSIT);
        return 0 if $self->bail_out;
        $self->push_events(OpenILS::Event->new('ROUTE_ITEM', org => $hold->pickup_lib));
    }

    # make sure we save the copy status
    $self->update_copy;
    return 0 if $copy->status == OILS_COPY_STATUS_CATALOGING;
    return 1;
}

sub attempt_checkin_reservation_capture {
    my $self = shift;
    my $copy = $self->copy;

    # we've been explicitly told not to capture any holds
    return 0 if $self->capture eq 'nocapture';

    my $booking_ses = OpenSRF::AppSession->connect("open-ils.booking");
    my $evt = $booking_ses->request(
        "open-ils.booking.resources.capture_for_reservation",
        $self->editor->authtoken,
        $copy->barcode,
        1 # don't update copy - we probably have it locked
    )->gather(1);
    $booking_ses->disconnect;

    if (ref($evt) ne "HASH" or not exists $evt->{"textcode"}) {
        $logger->warn(
            "open-ils.booking.resources.capture_for_reservation " .
            "didn't return an event!"
        );
    } else {
        if (
            $evt->{"textcode"} eq "RESERVATION_NOT_FOUND" and
            $evt->{"payload"}->{"fail_cause"} eq "not-transferable"
        ) {
            # not-transferable is an error event we'll pass on the user
            $logger->warn("reservation capture attempted against non-transferable item");
            $self->push_events($evt);
            return 0;
        } elsif ($evt->{"textcode"} eq "SUCCESS") {
            # Re-retrieve copy as reservation capture may have changed
            # its status and whatnot.
            $logger->info(
                "circulator: booking capture win on copy " . $self->copy->id
            );
            if (my $new_copy_status = $evt->{"payload"}->{"new_copy_status"}) {
                $logger->info(
                    "circulator: changing copy " . $self->copy->id .
                    "'s status from " . $self->copy->status . " to " .
                    $new_copy_status
                );
                $self->copy->status($new_copy_status);
                $self->update_copy;
            }
            $self->reservation($evt->{"payload"}->{"reservation"});

            if (exists $evt->{"payload"}->{"transit"}) {
                $self->push_events(
                    new OpenILS::Event(
                        "ROUTE_ITEM",
                        "org" => $evt->{"payload"}->{"transit"}->dest
                    )
                );
            }
            $self->checkin_changed(1);
            return 1;
        }
    }
    # other results are treated as "nothing to capture"
    return 0;
}

sub do_hold_notify {
    my( $self, $holdid ) = @_;

    my $e = new_editor(xact => 1);
    my $hold = $e->retrieve_action_hold_request($holdid) or return $e->die_event;
    $e->rollback;
    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    $ses->request('open-ils.trigger.event.autocreate', 'hold.available', $hold, $hold->pickup_lib);

    $logger->info("circulator: running delayed hold notify process");

#   my $notifier = OpenILS::Application::Circ::HoldNotify->new(
#       hold_id => $holdid, editor => new_editor(requestor=>$self->editor->requestor));

    my $notifier = OpenILS::Application::Circ::HoldNotify->new(
        hold_id => $holdid, requestor => $self->editor->requestor);

    $logger->debug("circulator: built hold notifier");

    if(!$notifier->event) {

        $logger->info("circulator: attempt at sending hold notification for hold $holdid");

        my $stat = $notifier->send_email_notify;
        if( $stat == '1' ) {
            $logger->info("circulator: hold notify succeeded for hold $holdid");
            return;
        } 

        $logger->debug("circulator:  * hold notify cancelled or failed for hold $holdid");

    } else {
        $logger->info("circulator: Not sending hold notification since the patron has no email address");
    }
}

sub retarget_holds {
    my $self = shift;
    $logger->info("circulator: retargeting holds @{$self->retarget} after opportunistic capture");
    my $ses = OpenSRF::AppSession->create('open-ils.hold-targeter');
    $ses->request('open-ils.hold-targeter.target', {hold => $self->retarget});

    my $cses = OpenSRF::AppSession->create('open-ils.circ');
    $cses->request('open-ils.circ.hold_reset_reason_entry.create', $self->editor->authtoken, $self->retarget,OILS_HOLD_BETTER_HOLD);

    # no reason to wait for the return value
    return;
}

sub checkin_build_hold_transit {
    my $self = shift;

   my $copy = $self->copy;
   my $hold = $self->hold;
   my $trans = Fieldmapper::action::hold_transit_copy->new;

    $logger->debug("circulator: building hold transit for ".$copy->barcode);

   $trans->hold($hold->id);
   $trans->source($self->circ_lib);
   $trans->dest($hold->pickup_lib);
   $trans->source_send_time("now");
   $trans->target_copy($copy->id);

    # when the copy gets to its destination, it will recover
    # this status - put it onto the holds shelf
   $trans->copy_status(OILS_COPY_STATUS_ON_HOLDS_SHELF);

    return $self->bail_on_events($self->editor->event)
        unless $self->editor->create_action_hold_transit_copy($trans);
}



sub process_received_transit {
    my $self = shift;
    my $copy = $self->copy;
    my $copyid = $self->copy->id;

    my $status_name = $U->copy_status($copy->status)->name;
    $logger->debug("circulator: attempting transit receive on ".
        "copy $copyid. Copy status is $status_name");

    my $transit = $self->transit;

    # Check if we are in a transit suppress range
    my $suppress_transit = 0;
    if ( $transit->dest != $self->circ_lib and not ( $self->hold_as_transit and $transit->copy_status == OILS_COPY_STATUS_ON_HOLDS_SHELF ) ) {
        my $suppress_setting = ($transit->copy_status == OILS_COPY_STATUS_ON_HOLDS_SHELF ?  'circ.transit.suppress_hold' : 'circ.transit.suppress_non_hold');
        my $suppress_transit_circ = $U->ou_ancestor_setting($self->circ_lib, $suppress_setting);
        if($suppress_transit_circ && $suppress_transit_circ->{value}) {
            my $suppress_transit_dest = $U->ou_ancestor_setting($transit->dest, $suppress_setting);
            if($suppress_transit_dest && $suppress_transit_dest->{value} eq $suppress_transit_circ->{value}) {
                $suppress_transit = 1;
                $self->fake_hold_dest(1) if $transit->copy_status == OILS_COPY_STATUS_ON_HOLDS_SHELF;
            }
        }
    }
    if( not $suppress_transit and ( $transit->dest != $self->circ_lib or ($self->hold_as_transit && $transit->copy_status == OILS_COPY_STATUS_ON_HOLDS_SHELF) ) ) {
        # - this item is in-transit to a different location
        # - Or we are capturing holds as transits, so why create a new transit?

        my $tid = $transit->id; 
        my $loc = $self->circ_lib;
        my $dest = $transit->dest;

        $logger->info("circulator: Fowarding transit on copy which is destined ".
            "for a different location. transit=$tid, copy=$copyid, current ".
            "location=$loc, destination location=$dest");

        my $evt = OpenILS::Event->new('ROUTE_ITEM', org => $dest, payload => {});

        # grab the associated hold object if available
        my $ht = $self->editor->retrieve_action_hold_transit_copy($tid);
        $self->hold($self->editor->retrieve_action_hold_request($ht->hold)) if $ht;

        return $self->bail_on_events($evt);
    }

    # The transit is received, set the receive time
    $transit->dest_recv_time('now');
    $self->bail_on_events($self->editor->event)
        unless $self->editor->update_action_transit_copy($transit);

    my $hold_transit = $self->editor->retrieve_action_hold_transit_copy($transit->id);

    $logger->info("circulator: Recovering original copy status in transit: ".$transit->copy_status);
    $copy->status( $transit->copy_status );
    $self->update_copy();
    return if $self->bail_out;

    my $ishold = 0;
    if($hold_transit) { 
        my $hold = $self->editor->retrieve_action_hold_request($hold_transit->hold);

        if ($hold) {
            # hold has arrived at destination, set shelf time
            $self->put_hold_on_shelf($hold);
            $self->bail_on_events($self->editor->event)
                unless $self->editor->update_action_hold_request($hold);
            return if $self->bail_out;

            $self->notify_hold($hold_transit->hold);
            $ishold = 1;
        } else {
            $hold_transit = undef;
            $self->cancelled_hold_transit(1);
            $self->reshelve_copy(1);
            $self->fake_hold_dest(0);
        }
    }

    $self->push_events( 
        OpenILS::Event->new(
        'SUCCESS', 
        ishold => $ishold,
      payload => { transit => $transit, holdtransit => $hold_transit } ));

    return $hold_transit;
}


# ------------------------------------------------------------------
# Sets the shelf_time and shelf_expire_time for a newly shelved hold
# ------------------------------------------------------------------
sub put_hold_on_shelf {
    my($self, $hold) = @_;
    $hold->shelf_time('now');
    $hold->current_shelf_lib($self->circ_lib);
    $holdcode->set_hold_shelf_expire_time($hold, $self->editor);
    return undef;
}

sub handle_fines {
   my $self = shift;
   my $reservation = shift;
   my $dt_parser = DateTime::Format::ISO8601->new;

   my $obj = $reservation ? $self->reservation : $self->circ;

    my $lost_bill_opts = $self->lost_bill_options;
    my $circ_lib = $lost_bill_opts->{circ_lib} if $lost_bill_opts;
    # first, restore any voided overdues for lost, if needed
    if ($self->needs_lost_bill_handling and !$self->void_overdues) {
        my $restore_od = $U->ou_ancestor_setting_value(
            $circ_lib, $lost_bill_opts->{ous_restore_overdue},
            $self->editor) || 0;
        $self->checkin_handle_lost_or_lo_now_found_restore_od($circ_lib)
            if $restore_od;
    }

    # next, handle normal overdue generation and apply stop_fines
    # XXX reservations don't have stop_fines
    # TODO revisit booking_reservation re: stop_fines support
    if ($reservation or !$obj->stop_fines) {
        my $skip_for_grace;

        # This is a crude check for whether we are in a grace period. The code
        # in generate_fines() does a more thorough job, so this exists solely
        # as a small optimization, and might be better off removed.

        # If we have a grace period
        if($obj->can('grace_period')) {
            # Parse out the due date
            my $due_date = $dt_parser->parse_datetime( clean_ISO8601($obj->due_date) );
            # Add the grace period to the due date
            $due_date->add(seconds => OpenILS::Utils::DateTime->interval_to_seconds($obj->grace_period));
            # Don't generate fines on circs still in grace period
            $skip_for_grace = $due_date > DateTime->now;
        }
        $CC->generate_fines({circs => [$obj], editor => $self->editor})
            unless $skip_for_grace;

        if (!$reservation and !$obj->stop_fines) {
            $obj->stop_fines(OILS_STOP_FINES_CHECKIN);
            $obj->stop_fines(OILS_STOP_FINES_RENEW) if $self->is_renewal;
            $obj->stop_fines(OILS_STOP_FINES_CLAIMS_NEVERCHECKEDOUT) if $self->claims_never_checked_out;
            $obj->stop_fines_time('now');
            $obj->stop_fines_time($self->backdate) if $self->backdate;
            $self->editor->update_action_circulation($obj);
        }
    }

    # finally, handle voiding of lost item and processing fees
    if ($self->needs_lost_bill_handling) {
        my $void_cost = $U->ou_ancestor_setting_value(
            $circ_lib, $lost_bill_opts->{ous_void_item_cost},
            $self->editor) || 0;
        my $void_proc_fee = $U->ou_ancestor_setting_value(
            $circ_lib, $lost_bill_opts->{ous_void_proc_fee},
            $self->editor) || 0;
        $self->checkin_handle_lost_or_lo_now_found(
            $lost_bill_opts->{void_cost_btype},
            $lost_bill_opts->{is_longoverdue}) if $void_cost;
        $self->checkin_handle_lost_or_lo_now_found(
            $lost_bill_opts->{void_fee_btype},
            $lost_bill_opts->{is_longoverdue}) if $void_proc_fee;
    }

   return undef;
}

sub checkin_handle_circ_start {
   my $self = shift;
   my $circ = $self->circ;
   my $copy = $self->copy;
   my $evt;
   my $obt;

   $self->backdate($circ->xact_start) if $self->claims_never_checked_out;

   # backdate the circ if necessary
   if($self->backdate) {
        my $evt = $self->checkin_handle_backdate;
        return $self->bail_on_events($evt) if $evt;
   }

    # Set the checkin vars since we have the item
    $circ->checkin_time( ($self->backdate) ? $self->backdate : 'now' );

    # capture the true scan time for back-dated checkins
    $circ->checkin_scan_time('now');

    $circ->checkin_staff($self->editor->requestor->id);
    $circ->checkin_lib($self->circ_lib);
    $circ->checkin_workstation($self->editor->requestor->wsid);

    my $circ_lib = (ref $self->copy->circ_lib) ?  
        $self->copy->circ_lib->id : $self->copy->circ_lib;
    my $stat = $U->copy_status($self->copy->status)->id;

    if ($stat == OILS_COPY_STATUS_LOST || $stat == OILS_COPY_STATUS_LOST_AND_PAID) {
        # we will now handle lost fines, but the copy will retain its 'lost'
        # status if it needs to transit home unless lost_immediately_available
        # is true
        #
        # if we decide to also delay fine handling until the item arrives home,
        # we will need to call lost fine handling code both when checking items
        # in and also when receiving transits
        $self->checkin_handle_lost($circ_lib);
    } elsif ($stat == OILS_COPY_STATUS_LONG_OVERDUE) {
        # same process as above.
        $self->checkin_handle_long_overdue($circ_lib);
    } elsif ($circ_lib != $self->circ_lib and $stat == OILS_COPY_STATUS_MISSING) {
        $logger->info("circulator: not updating copy status on checkin because copy is missing");
    } else {
        my $next_status = $self->next_copy_status->[0] || OILS_COPY_STATUS_RESHELVING;
        $self->copy->status($U->copy_status($next_status));
        $self->update_copy;
    }

    return undef;
}

sub checkin_handle_circ_finish {
    my $self = shift;
    my $e = $self->editor;
    my $circ = $self->circ;

    # Do one last check before the final circulation update to see 
    # if the xact_finish value should be set or not.
    #
    # The underlying money.billable_xact may have been updated to
    # reflect a change in xact_finish during checkin bills handling, 
    # however we can't simply refresh the circulation from the DB,
    # because other changes may be pending.  Instead, reproduce the
    # xact_finish check here.  It won't hurt to do it again.

    my $sum = $e->retrieve_money_billable_transaction_summary($circ->id);
    if ($sum) { # is this test still needed?

        my $balance = $sum->balance_owed;

        if ($balance == 0) {
            $circ->xact_finish('now');
        } else {
            $circ->clear_xact_finish;
        }

        $logger->info("circulator: $balance is owed on this circulation");
    }

    return $self->bail_on_events($e->event)
        unless $e->update_action_circulation($circ);

    return undef;
}

# ------------------------------------------------------------------
# See if we need to void billings, etc. for lost checkin
# ------------------------------------------------------------------
sub checkin_handle_lost {
    my $self = shift;
    my $circ_lib = shift;

    my $max_return = $U->ou_ancestor_setting_value($circ_lib, 
        OILS_SETTING_MAX_ACCEPT_RETURN_OF_LOST, $self->editor) || 0;

    $self->lost_bill_options({
        circ_lib => $circ_lib,
        ous_void_item_cost => OILS_SETTING_VOID_LOST_ON_CHECKIN,
        ous_void_proc_fee => OILS_SETTING_VOID_LOST_PROCESS_FEE_ON_CHECKIN,
        ous_restore_overdue => OILS_SETTING_RESTORE_OVERDUE_ON_LOST_RETURN,
        void_cost_btype => 3, 
        void_fee_btype => 4 
    });

    return $self->checkin_handle_lost_or_longoverdue(
        circ_lib => $circ_lib,
        max_return => $max_return,
        ous_immediately_available => OILS_SETTING_LOST_IMMEDIATELY_AVAILABLE,
        ous_use_last_activity => undef # not supported for LOST checkin
    );
}

# ------------------------------------------------------------------
# See if we need to void billings, etc. for long-overdue checkin
# note: not using constants below since they serve little purpose 
# for single-use strings that are descriptive in their own right 
# and mostly just complicate debugging.
# ------------------------------------------------------------------
sub checkin_handle_long_overdue {
    my $self = shift;
    my $circ_lib = shift;

    $logger->info("circulator: processing long-overdue checkin...");

    my $max_return = $U->ou_ancestor_setting_value($circ_lib, 
        'circ.max_accept_return_of_longoverdue', $self->editor) || 0;

    $self->lost_bill_options({
        circ_lib => $circ_lib,
        ous_void_item_cost => 'circ.void_longoverdue_on_checkin',
        ous_void_proc_fee => 'circ.void_longoverdue_proc_fee_on_checkin',
        is_longoverdue => 1,
        ous_restore_overdue => 'circ.restore_overdue_on_longoverdue_return',
        void_cost_btype => 10,
        void_fee_btype => 11
    });

    return $self->checkin_handle_lost_or_longoverdue(
        circ_lib => $circ_lib,
        max_return => $max_return,
        ous_immediately_available => 'circ.longoverdue_immediately_available',
        ous_use_last_activity => 
            'circ.longoverdue.use_last_activity_date_on_return'
    )
}

# last billing activity is last payment time, last billing time, or the 
# circ due date.  If the relevant "use last activity" org unit setting is 
# false/unset, then last billing activity is always the due date.
sub get_circ_last_billing_activity {
    my $self = shift;
    my $circ_lib = shift;
    my $setting = shift;
    my $date = $self->circ->due_date;

    return $date unless $setting and 
        $U->ou_ancestor_setting_value($circ_lib, $setting, $self->editor);

    my $xact = $self->editor->retrieve_money_billable_transaction([
        $self->circ->id,
        {flesh => 1, flesh_fields => {mbt => ['summary']}}
    ]);

    if ($xact->summary) {
        $date = $xact->summary->last_payment_ts || 
                $xact->summary->last_billing_ts || 
                $self->circ->due_date;
    }

    return $date;
}


sub checkin_handle_lost_or_longoverdue {
    my ($self, %args) = @_;

    my $circ = $self->circ;
    my $max_return = $args{max_return};
    my $circ_lib = $args{circ_lib};

    if ($max_return) {

        my $last_activity = 
            $self->get_circ_last_billing_activity(
                $circ_lib, $args{ous_use_last_activity});

        my $today = time();
        my @tm = reverse($last_activity =~ /([\d\.]+)/og);
        $tm[5] -= 1 if $tm[5] > 0;
        my $due = timelocal(int($tm[1]), int($tm[2]), 
            int($tm[3]), int($tm[4]), int($tm[5]), int($tm[6]));

        my $last_chance = 
            OpenILS::Utils::DateTime->interval_to_seconds($max_return) + int($due);

        $logger->info("MAX OD: $max_return LAST ACTIVITY: ".
            "$last_activity DUEDATE: ".$circ->due_date." TODAY: $today ".
                "DUE: $due LAST: $last_chance");

        $max_return = 0 if $today < $last_chance;
    }


    if ($max_return) {

        $logger->info("circulator: check-in of lost/lo item exceeds max ". 
            "return interval.  skipping fine/fee voiding, etc.");

    } elsif ($self->dont_change_lost_zero) { # we leave lost zero balance alone

        $logger->info("circulator: check-in of lost/lo item having a balance ".
            "of zero, skipping fine/fee voiding and reinstatement.");

    } else { # within max-return interval or no interval defined

        $logger->info("circulator: check-in of lost/lo item is within the ".
            "max return interval (or no interval is defined).  Proceeding ".
            "with fine/fee voiding, etc.");

        $self->needs_lost_bill_handling(1);
    }

    if ($circ_lib != $self->circ_lib) {
        # if the item is not home, check to see if we want to retain the
        # lost/longoverdue status at this point in the process

        my $immediately_available = $U->ou_ancestor_setting_value($circ_lib, 
            $args{ous_immediately_available}, $self->editor) || 0;

        if ($immediately_available) {
            # item status does not need to be retained, so give it a
            # reshelving status as if it were a normal checkin
            my $next_status = $self->next_copy_status->[0] || OILS_COPY_STATUS_RESHELVING;
            $self->copy->status($U->copy_status($next_status));
            $self->update_copy;
        } else {
            $logger->info("circulator: leaving lost/longoverdue copy".
                " status in place on checkin");
        }
    } else {
        # lost/longoverdue item is home and processed, treat like a normal 
        # checkin from this point on
        my $next_status = $self->next_copy_status->[0] || OILS_COPY_STATUS_RESHELVING;
        $self->copy->status($U->copy_status($next_status));
        $self->update_copy;
    }
}


sub checkin_handle_backdate {
    my $self = shift;

    # ------------------------------------------------------------------
    # clean up the backdate for date comparison
    # XXX We are currently taking the due-time from the original due-date,
    # not the input.  Do we need to do this?  This certainly interferes with
    # backdating of hourly checkouts, but that is likely a very rare case.
    # ------------------------------------------------------------------
    my $bd = clean_ISO8601($self->backdate);
    my $original_date = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($self->circ->due_date));
    my $new_date = DateTime::Format::ISO8601->new->parse_datetime($bd);
    $new_date->set_hour($original_date->hour());
    $new_date->set_minute($original_date->minute());
    if ($new_date >= DateTime->now) {
        # We can't say that the item will be checked in later...so assume someone's clock is wrong instead.
        # $self->backdate() autoload handler ignores undef values.  
        # Clear the backdate manually.
        $logger->info("circulator: ignoring future backdate: $new_date");
        delete $self->{backdate};
    } else {
        $self->backdate(clean_ISO8601($new_date->datetime()));
    }

    return undef;
}


sub check_checkin_copy_status {
    my $self = shift;
   my $copy = $self->copy;

   my $status = $U->copy_status($copy->status)->id;

   return undef
      if(   $self->new_copy_alerts ||
            $status == OILS_COPY_STATUS_AVAILABLE   ||
            $status == OILS_COPY_STATUS_CHECKED_OUT ||
            $status == OILS_COPY_STATUS_IN_PROCESS  ||
            $status == OILS_COPY_STATUS_ON_HOLDS_SHELF  ||
            $status == OILS_COPY_STATUS_IN_TRANSIT  ||
            $status == OILS_COPY_STATUS_CATALOGING  ||
            $status == OILS_COPY_STATUS_ON_RESV_SHELF  ||
            $status == OILS_COPY_STATUS_CANCELED_TRANSIT ||
            $status == OILS_COPY_STATUS_RESHELVING );

   return OpenILS::Event->new('COPY_STATUS_LOST', payload => $copy )
      if( $status == OILS_COPY_STATUS_LOST );

    return OpenILS::Event->new('COPY_STATUS_LOST_AND_PAID', payload => $copy)
        if ($status == OILS_COPY_STATUS_LOST_AND_PAID);

   return OpenILS::Event->new('COPY_STATUS_LONG_OVERDUE', payload => $copy )
      if( $status == OILS_COPY_STATUS_LONG_OVERDUE );

   return OpenILS::Event->new('COPY_STATUS_MISSING', payload => $copy )
      if( $status == OILS_COPY_STATUS_MISSING );

   return OpenILS::Event->new('COPY_BAD_STATUS', payload => $copy );
}



# --------------------------------------------------------------------------
# On checkin, we need to return as many relevant objects as we can
# --------------------------------------------------------------------------
sub checkin_flesh_events {
    my $self = shift;

    if( grep { $_->{textcode} eq 'SUCCESS' } @{$self->events} 
        and grep { $_->{textcode} eq 'ITEM_NOT_CATALOGED' } @{$self->events} ) {
            $self->events([grep { $_->{textcode} eq 'ITEM_NOT_CATALOGED' } @{$self->events}]);
    }

    my $record = $U->record_to_mvr($self->title) if($self->title and !$self->is_precat);

    my $hold;
    if($self->hold and !$self->hold->cancel_time) {
        $hold = $self->hold;
        $hold->notes($self->editor->search_action_hold_request_note({hold => $hold->id}));
    }

    if($self->circ) {
        # update our copy of the circ object and 
        # flesh the billing summary data
        $self->circ(
            $self->editor->retrieve_action_circulation([
                $self->circ->id, {
                    flesh => 2,
                    flesh_fields => {
                        circ => ['billable_transaction'],
                        mbt => ['summary']
                    }
                }
            ])
        );
    }

    if($self->patron) {
        # flesh some patron fields before returning
        $self->patron(
            $self->editor->retrieve_actor_user([
                $self->patron->id,
                {
                    flesh => 1,
                    flesh_fields => {
                        au => ['card', 'billing_address', 'mailing_address']
                    }
                }
            ])
        );
    }

    # Flesh the latest inventory.
    # NB: This survives the unflesh_copy below. Let's keep it that way.
    my $alci = $self->editor->search_asset_latest_inventory([
        {copy=>$self->copy->id},
        {flesh => 1,
         flesh_fields => {
             alci => ['inventory_workstation']
         }}]);
    if ($alci && $alci->[0]) {
        $self->copy->latest_inventory($alci->[0]);
    }

    for my $evt (@{$self->events}) {

        my $payload         = {};
        $payload->{copy}    = $U->unflesh_copy($self->copy);
        $payload->{volume}  = $self->volume;
        $payload->{record}  = $record,
        $payload->{circ}    = $self->circ;
        $payload->{transit} = $self->transit;
        $payload->{cancelled_hold_transit} = 1 if $self->cancelled_hold_transit;
        $payload->{hold}    = $hold;
        $payload->{patron}  = $self->patron;
        $payload->{reservation} = $self->reservation
            unless (not $self->reservation or $self->reservation->cancel_time);

        $evt->{payload}     = $payload;
    }
}

sub log_me {
    my( $self, $msg ) = @_;
    my $bc = ($self->copy) ? $self->copy->barcode :
        $self->copy_barcode;
    $bc ||= "";
    my $usr = ($self->patron) ? $self->patron->id : "";
    $logger->info("circulator: $msg requestor=".$self->editor->requestor->id.
        ", recipient=$usr, copy=$bc");
}


sub do_renew {
    my $self = shift;
    my $api = shift;
    $self->log_me("do_renew()");

    # Make sure there is an open circ to renew
    my $usrid = $self->patron->id if $self->patron;
    my $circ = $self->editor->search_action_circulation({
        target_copy => $self->copy->id,
        xact_finish => undef,
        checkin_time => undef,
        ($usrid ? (usr => $usrid) : ())
    })->[0];

    return $self->bail_on_events($self->editor->event) unless $circ;

    # A user is not allowed to renew another user's items without permission
    unless( $circ->usr eq $self->editor->requestor->id ) {
        return $self->bail_on_events($self->editor->events)
            unless $self->editor->allowed('RENEW_CIRC', $circ->circ_lib);
    }   

    $self->push_events(OpenILS::Event->new('MAX_RENEWALS_REACHED'))
        if $circ->renewal_remaining < 1;

    $self->push_events(OpenILS::Event->new('MAX_AUTO_RENEWALS_REACHED'))
        if $self->auto_renewal and $circ->auto_renewal_remaining < 1;
    # -----------------------------------------------------------------

    $self->parent_circ($circ->id);
    $self->renewal_remaining( $circ->renewal_remaining - 1 );
    $self->auto_renewal_remaining( $circ->auto_renewal_remaining - 1 ) if (defined($circ->auto_renewal_remaining));
    $self->circ($circ);

    # Opac renewal - re-use circ library from original circ (unless told not to)
    if($self->opac_renewal or $self->auto_renewal) {
        unless(defined($opac_renewal_use_circ_lib)) {
            my $use_circ_lib = $self->editor->retrieve_config_global_flag('circ.opac_renewal.use_original_circ_lib');
            if($use_circ_lib and $U->is_true($use_circ_lib->enabled)) {
                $opac_renewal_use_circ_lib = 1;
            }
            else {
                $opac_renewal_use_circ_lib = 0;
            }
        }
        $self->circ_lib($circ->circ_lib) if($opac_renewal_use_circ_lib);
    }

    # Desk renewal - re-use circ library from original circ (unless told not to)
    if($self->desk_renewal) {
        unless(defined($desk_renewal_use_circ_lib)) {
            my $use_circ_lib = $self->editor->retrieve_config_global_flag('circ.desk_renewal.use_original_circ_lib');
            if($use_circ_lib and $U->is_true($use_circ_lib->enabled)) {
                $desk_renewal_use_circ_lib = 1;
            }
            else {
                $desk_renewal_use_circ_lib = 0;
            }
        }
        $self->circ_lib($circ->circ_lib) if($desk_renewal_use_circ_lib);
    }

    # Check if expired patron is allowed to renew, and bail if not.
    my $expire = DateTime::Format::ISO8601->new->parse_datetime(clean_ISO8601($self->patron->expire_date));
    if (CORE::time > $expire->epoch) {
        my $allow_renewal = $U->ou_ancestor_setting_value($self->circ_lib, OILS_SETTING_ALLOW_RENEW_FOR_EXPIRED_PATRON);
        unless ($U->is_true($allow_renewal)) {
            return $self->bail_on_events(OpenILS::Event->new('PATRON_ACCOUNT_EXPIRED'));
        }
    }

    # Run the fine generator against the old circ
    # XXX This seems unnecessary, given that handle_fines runs in do_checkin
    # a few lines down.  Commenting out, for now.
    #$self->handle_fines;

    $self->run_renew_permit;

    # Check the item in
    $self->do_checkin();
    return if $self->bail_out;

    unless( $self->permit_override ) {
        $self->do_permit();
        return if $self->bail_out;
        $self->is_precat(1) if $self->have_event('ITEM_NOT_CATALOGED');
        $self->remove_event('ITEM_NOT_CATALOGED');
    }   

    $self->override_events;
    return if $self->bail_out;

    $self->events([]);
    $self->do_checkout();
}


sub remove_event {
    my( $self, $evt ) = @_;
    $evt = (ref $evt) ? $evt->{textcode} : $evt;
    $logger->debug("circulator: removing event from list: $evt");
    my @events = @{$self->events};
    $self->events( [ grep { $_->{textcode} ne $evt } @events ] );
}


sub have_event {
    my( $self, $evt ) = @_;
    $evt = (ref $evt) ? $evt->{textcode} : $evt;
    return grep { $_->{textcode} eq $evt } @{$self->events};
}


sub run_renew_permit {
    my $self = shift;

    if ($U->ou_ancestor_setting_value($self->circ_lib, 'circ.block_renews_for_holds')) {
        my ($hold, undef, $retarget) = $holdcode->find_nearest_permitted_hold(
            $self->editor, $self->copy, $self->editor->requestor, 1
        );
        $self->push_events(new OpenILS::Event("COPY_NEEDED_FOR_HOLD")) if $hold;
    }

    my $results = $self->run_indb_circ_test;
    $self->push_events($self->matrix_test_result_events)
        unless $self->circ_test_success;
}


# XXX: The primary mechanism for storing circ history is now handled
# by tracking real circulation objects instead of bibs in a bucket.
# However, this code is disabled by default and could be useful 
# some day, so may as well leave it for now.
sub append_reading_list {
    my $self = shift;

    return undef unless 
        $self->is_checkout and 
        $self->patron and 
        $self->copy and 
        !$self->is_noncat;


    # verify history is globally enabled and uses the bucket mechanism
    my $htype = OpenSRF::Utils::SettingsClient->new->config_value(
        apps => 'open-ils.circ' => app_settings => 'checkout_history_mechanism');

    return undef unless $htype and $htype eq 'bucket';

    my $e = new_editor(xact => 1, requestor => $self->editor->requestor);

    # verify the patron wants to retain the hisory
    my $setting = $e->search_actor_user_setting(
        {usr => $self->patron->id, name => 'circ.keep_checkout_history'})->[0];
    
    unless($setting and $setting->value) {
        $e->rollback;
        return undef;
    }

    my $bkt = $e->search_container_copy_bucket(
        {owner => $self->patron->id, btype => 'circ_history'})->[0];

    my $pos = 1;

    if($bkt) {
        # find the next item position
        my $last_item = $e->search_container_copy_bucket_item(
            {bucket => $bkt->id}, {order_by => {ccbi => 'pos desc'}, limit => 1})->[0];
        $pos = $last_item->pos + 1 if $last_item;

    } else {
        # create the history bucket if necessary
        $bkt = Fieldmapper::container::copy_bucket->new;
        $bkt->owner($self->patron->id);
        $bkt->name('');
        $bkt->btype('circ_history');
        $bkt->pub('f');
        $e->create_container_copy_bucket($bkt) or return $e->die_event;
    }

    my $item = Fieldmapper::container::copy_bucket_item->new;

    $item->bucket($bkt->id);
    $item->target_copy($self->copy->id);
    $item->pos($pos);

    $e->create_container_copy_bucket_item($item) or return $e->die_event;
    $e->commit;

    return undef;
}


sub make_trigger_events {
    my $self = shift;
    return unless $self->circ;
    $U->create_events_for_hook('checkout', $self->circ, $self->circ_lib) if $self->is_checkout;
    $U->create_events_for_hook('checkin',  $self->circ, $self->circ_lib) if $self->is_checkin;
    $U->create_events_for_hook('renewal',  $self->circ, $self->circ_lib) if $self->is_renewal;
}



sub checkin_handle_lost_or_lo_now_found {
    my ($self, $bill_type, $is_longoverdue) = @_;

    my $tag = $is_longoverdue ? "LONGOVERDUE" : "LOST";

    $logger->debug("voiding $tag item billings");
    my $result = $CC->void_or_zero_bills_of_type($self->editor, $self->circ, $self->copy, $bill_type, "$tag ITEM RETURNED");
    $self->bail_on_events($self->editor->event) if ($result);
}

sub checkin_handle_lost_or_lo_now_found_restore_od {
    my $self = shift;
    my $circ_lib = shift;
    my $is_longoverdue = shift;
    my $tag = $is_longoverdue ? "LONGOVERDUE" : "LOST";

    # ------------------------------------------------------------------
    # restore those overdue charges voided when item was set to lost
    # ------------------------------------------------------------------

    my $ods = $self->editor->search_money_billing([
        {
            xact => $self->circ->id,
            btype => 1
        },
        {
            order_by => {mb => 'billing_ts desc'}
        }
    ]);

    $logger->debug("returning ".scalar(@$ods)." overdue charges pre-$tag");
    # Because actual users get up to all kinds of unexpectedness, we
    # only recreate up to $circ->max_fine in bills.  I know you think
    # it wouldn't happen that bills could get created, voided, and
    # recreated more than once, but I guaran-damn-tee you that it will
    # happen.
    if ($ods && @$ods) {
        my $void_amount = 0;
        my $void_max = $self->circ->max_fine();
        # search for overdues voided the new way (aka "adjusted")
        my @billings = map {$_->id()} @$ods;
        my $voids = $self->editor->search_money_account_adjustment(
            {
                billing => \@billings
            }
        );
        if (@$voids) {
            map {$void_amount += $_->amount()} @$voids;
        } else {
            # if no adjustments found, assume they were voided the old way (aka "voided")
            for my $bill (@$ods) {
                if( $U->is_true($bill->voided) ) {
                    $void_amount += $bill->amount();
                }
            }
        }
        $CC->create_bill(
            $self->editor,
            ($void_amount < $void_max ? $void_amount : $void_max),
            $ods->[0]->btype(),
            $ods->[0]->billing_type(),
            $self->circ->id(),
            "System: $tag RETURNED - OVERDUES REINSTATED",
            $ods->[-1]->period_start(),
            $ods->[0]->period_end() # date this restoration the same as the last overdue (for possible subsequent fine generation)
        );
    }
}

1;
