package OpenILS::Application::Circ::Circulate;
use strict; use warnings;
use base 'OpenILS::Application';
use OpenSRF::EX qw(:try);
use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Const qw/:const/;
use OpenILS::Application::AppUtils;
use DateTime;
my $U = "OpenILS::Application::AppUtils";

my %scripts;
my $script_libs;
my $legacy_script_support = 0;
my $booking_status;
my $opac_renewal_use_circ_lib;

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
    flesh_fields => {acp => ['call_number','parts'], acn => ['record']}
};

sub initialize {

    my $self = shift;
    my $conf = OpenSRF::Utils::SettingsClient->new;
    my @pfx2 = ( "apps", "open-ils.circ","app_settings" );

    $legacy_script_support = $conf->config_value(@pfx2, 'legacy_script_support');
    $legacy_script_support = ($legacy_script_support and $legacy_script_support =~ /true/i);

    my $lb  = $conf->config_value(  @pfx2, 'script_path' );
    $lb = [ $lb ] unless ref($lb);
    $script_libs = $lb;

    return unless $legacy_script_support;

    my @pfx = ( @pfx2, "scripts" );
    my $p   = $conf->config_value(  @pfx, 'circ_permit_patron' );
    my $c   = $conf->config_value(  @pfx, 'circ_permit_copy' );
    my $d   = $conf->config_value(  @pfx, 'circ_duration' );
    my $f   = $conf->config_value(  @pfx, 'circ_recurring_fines' );
    my $m   = $conf->config_value(  @pfx, 'circ_max_fines' );
    my $pr  = $conf->config_value(  @pfx, 'circ_permit_renew' );

    $logger->error( "Missing circ script(s)" ) 
        unless( $p and $c and $d and $f and $m and $pr );

    $scripts{circ_permit_patron}   = $p;
    $scripts{circ_permit_copy}     = $c;
    $scripts{circ_duration}        = $d;
    $scripts{circ_recurring_fines} = $f;
    $scripts{circ_max_fines}       = $m;
    $scripts{circ_permit_renew}    = $pr;

    $logger->debug(
        "circulator: Loaded rules scripts for circ: " .
        "circ permit patron = $p, ".
        "circ permit copy = $c, ".
        "circ duration = $d, ".
        "circ recurring fines = $f, " .
        "circ max fines = $m, ".
        "circ renew permit = $pr.  ".
        "lib paths = @$lb. ".
        "legacy script support = ". ($legacy_script_support) ? 'yes' : 'no'
        );
}

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
                    { target_copy => $res_id_list, dest => $circulator->circ_lib, dest_recv_time => undef },
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
            
    

    # --------------------------------------------------------------------------
    # Go ahead and load the script runner to make sure we have all 
    # of the objects we need
    # --------------------------------------------------------------------------

    if ($circulator->use_booking) {
        $circulator->is_res_checkin($circulator->is_checkin(1))
            if $api =~ /reservation.return/ or (
                $api =~ /checkin/ and $circulator->seems_like_reservation()
            );

        $circulator->is_res_checkout(1) if $api =~ /reservation.pickup/;
    }

    $circulator->is_renewal(1) if $api =~ /renew/;
    $circulator->is_checkin(1) if $api =~ /checkin/;

    $circulator->mk_env();
    $circulator->noop(1) if $circulator->claims_never_checked_out;

    if($legacy_script_support and not $circulator->is_checkin) {
        $circulator->mk_script_runner();
        $circulator->legacy_script_support(1);
        $circulator->circ_permit_patron($scripts{circ_permit_patron});
        $circulator->circ_permit_copy($scripts{circ_permit_copy});      
        $circulator->circ_duration($scripts{circ_duration});             
        $circulator->circ_permit_renew($scripts{circ_permit_renew});
    }
    return circ_events($circulator) if $circulator->bail_out;

    
    $circulator->override(1) if $api =~ /override/o;

    if( $api =~ /checkout\.permit/ ) {
        $circulator->do_permit();

    } elsif( $api =~ /checkout.full/ ) {

        # requesting a precat checkout implies that any required
        # overrides have been performed.  Go ahead and re-override.
        $circulator->skip_permit_key(1);
        $circulator->override(1) if $circulator->request_precat;
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
        $circulator->is_checkout(1);
        $circulator->do_checkout();

    } elsif( $circulator->is_res_checkin ) {
        $circulator->do_reservation_return();
        $circulator->do_checkin() if ($circulator->copy());
    } elsif( $api =~ /checkin/ ) {
        $circulator->do_checkin();

    } elsif( $api =~ /renew/ ) {
        $circulator->is_renewal(1);
        $circulator->do_renew();
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

        $circulator->editor->commit;

        if ($circulator->generate_lost_overdue) {
            # Generating additional overdue billings has to happen after the 
            # main commit and before the final respond() so the caller can
            # receive the latest transaction summary.
            my $evt = $circulator->generate_lost_overdue_fines;
            $circulator->bail_on_events($evt) if $evt;
        }
    }
    
    $conn->respond_complete(circ_events($circulator));

    $circulator->script_runner->cleanup if $circulator->script_runner;

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
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::Circ::Holds;
use OpenILS::Application::Circ::Transit;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Application::Circ::ScriptBuilder;
use OpenILS::Const qw/:const/;
use OpenILS::Utils::Penalty;
use OpenILS::Application::Circ::CircCommon;
use Time::Local;

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
    copy
    copy_id
    copy_barcode
    patron
    patron_id
    patron_barcode
    script_runner
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
    retarget
    matrix_test_result
    circ_matrix_matchpoint
    circ_test_success
    legacy_script_support
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
    generate_lost_overdue
    clear_expired
    retarget_mode
    hold_as_transit
    fake_hold_dest
    limit_groups
    override_args
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
        $self->opac_renewal or $self->phone_renewal or $self->sip_renewal;

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

sub mk_env {
    my $self = shift;
    my $e = $self->editor;

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
	
		my $expire = DateTime::Format::ISO8601->new->parse_datetime(
			cleanse_ISO8601($patron->expire_date));
	
		$self->bail_on_events(OpenILS::Event->new('PATRON_ACCOUNT_EXPIRED'))
			if( CORE::time > $expire->epoch ) ;
    }
}

# --------------------------------------------------------------------------
# This builds the script runner environment and fetches most of the
# objects we need
# --------------------------------------------------------------------------
sub mk_script_runner {
    my $self = shift;
    my $args = {};


    my @fields = 
        qw/copy copy_barcode copy_id patron 
            patron_id patron_barcode volume title editor/;

    # Translate our objects into the ScriptBuilder args hash
    $$args{$_} = $self->$_() for @fields;

    $args->{ignore_user_status} = 1 if $self->is_checkin;
    $$args{fetch_patron_by_circ_copy} = 1;
    $$args{fetch_patron_circ_info} = 1 unless $self->is_checkin;

    if( my $pco = $self->pending_checkouts ) {
        $logger->info("circulator: we were given a pending checkouts number of $pco");
        $$args{patronItemsOut} = $pco;
    }

    # This fetches most of the objects we need
    $self->script_runner(
        OpenILS::Application::Circ::ScriptBuilder->build($args));

    # Now we translate the ScriptBuilder objects back into self
    $self->$_($$args{$_}) for @fields;

    my @evts = @{$args->{_events}} if $args->{_events};

    $logger->debug("circulator: script builder returned events: @evts") if @evts;


    if(@evts) {
        # Anything besides ASSET_COPY_NOT_FOUND will stop processing
        if(!$self->is_noncat and 
            @evts == 1 and 
            $evts[0]->{textcode} eq 'ASSET_COPY_NOT_FOUND') {
                $self->is_precat(1);

        } else {
            my @e = grep { $_->{textcode} ne 'ASSET_COPY_NOT_FOUND' } @evts;
            return $self->bail_on_events(@e);
        }
    }

    if($self->copy) {
        $self->is_precat(1) if $self->copy->call_number == OILS_PRECAT_CALL_NUMBER;
        if($self->copy->deposit_amount and $self->copy->deposit_amount > 0) {
            $self->is_deposit(1) if $U->is_true($self->copy->deposit);
            $self->is_rental(1) unless $U->is_true($self->copy->deposit);
        }
    }

    # We can't renew if there is no copy
    return $self->bail_on_events(@evts) if 
        $self->is_renewal and !$self->copy;

    # Set some circ-specific flags in the script environment
    my $evt = "environment";
    $self->script_runner->insert("$evt.isRenewal", ($self->is_renewal) ? 1 : undef);

    if( $self->is_noncat ) {
      $self->script_runner->insert("$evt.isNonCat", 1);
      $self->script_runner->insert("$evt.nonCatType", $self->noncat_type);
    }

    if( $self->is_precat ) {
        $self->script_runner->insert("environment.isPrecat", 1, 1);
    }

    $self->script_runner->add_path( $_ ) for @$script_libs;

    return 1;
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
    my $holds   = $self->editor->search_action_hold_request(
        [
            { 
                current_copy        => $copy->id , 
                capture_time        => { '!=' => undef },
                cancel_time         => undef, 
                fulfillment_time    => undef 
            },
            { limit => 1 }
        ]
    );

    if( $holds and $$holds[0] ) {
        return undef if $$holds[0]->usr == $patron->id;
    }

    $logger->info("circulator: this copy is needed by a different patron to fulfill a hold");

    $self->push_events(OpenILS::Event->new('ITEM_ON_HOLDS_SHELF'));
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
                    my $intvl_seconds = OpenSRF::Utils->interval_to_seconds($auto_renew_intvl);
                    my $checkout_time = DateTime::Format::ISO8601->new->parse_datetime( cleanse_ISO8601($old_circ->xact_start) );

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
};


# ---------------------------------------------------------------------
# This pushes any patron-related events into the list but does not
# set bail_out for any events
# ---------------------------------------------------------------------
sub run_patron_permit_scripts {
    my $self        = shift;
    my $runner      = $self->script_runner;
    my $patronid    = $self->patron->id;

    my @allevents; 

    if(!$self->legacy_script_support) {

        my $results = $self->run_indb_circ_test;
        unless($self->circ_test_success) {
            # no_item result is OK during noncat checkout
            unless(@$results == 1 && $results->[0]->{fail_part} eq 'no_item' and $self->is_noncat) {
                push @allevents, $self->matrix_test_result_events;
            }
        }

    } else {

        # --------------------------------------------------------------------- 
        # # Now run the patron permit script 
        # ---------------------------------------------------------------------
        $runner->load($self->circ_permit_patron);
        my $result = $runner->run or 
            throw OpenSRF::EX::ERROR ("Circ Permit Patron Script Died: $@");

        my $patron_events = $result->{events};

        OpenILS::Utils::Penalty->calculate_penalties($self->editor, $self->patron->id, $self->circ_lib);
        my $mask = ($self->is_renewal) ? 'RENEW' : 'CIRC';
        my $penalties = OpenILS::Utils::Penalty->retrieve_penalties($self->editor, $patronid, $self->circ_lib, $mask);
        $penalties = $penalties->{fatal_penalties};

        for my $pen (@$penalties) {
            my $event = OpenILS::Event->new($pen->name);
            $event->{desc} = $pen->label;
            push(@allevents, $event);
        }

        push(@allevents, OpenILS::Event->new($_)) for (@$patron_events);
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
        $self->circ_matrix_matchpoint->hard_due_date($self->editor->retrieve_config_hard_due_date($results->[0]->{hard_due_date}));
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
    my $runner = $self->script_runner;

    my @allevents;

    if(!$self->legacy_script_support) {
        my $results = $self->run_indb_circ_test;
        push @allevents, $self->matrix_test_result_events
            unless $self->circ_test_success;
    } else {
    
       # ---------------------------------------------------------------------
       # Capture all of the copy permit events
       # ---------------------------------------------------------------------
       $runner->load($self->circ_permit_copy);
       my $result = $runner->run or 
            throw OpenSRF::EX::ERROR ("Circ Permit Copy Script Died: $@");
       my $copy_events = $result->{events};

       # ---------------------------------------------------------------------
       # Now collect all of the events together
       # ---------------------------------------------------------------------
       push( @allevents, OpenILS::Event->new($_)) for @$copy_events;
    }

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
    # Update the patron penalty info in the DB.  Run it for permit-overrides 
    # since the penalties are not updated during the permit phase
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
# When an item is checked out, see if we can fulfill a hold for this patron
# ------------------------------------------------------------------------------
sub handle_checkout_holds {
   my $self    = shift;
   my $copy    = $self->copy;
   my $patron  = $self->patron;

   my $e = $self->editor;
   $self->fulfilled_holds([]);

   # pre/non-cats can't fulfill a hold
   return if $self->is_precat or $self->is_noncat;

    my $hold = $e->search_action_hold_request({   
        current_copy        => $copy->id , 
        cancel_time         => undef, 
        fulfillment_time    => undef,
        '-or' => [
            {expire_time => undef},
            {expire_time => {'>' => 'now'}}
        ]
    })->[0];

    if($hold and $hold->usr != $patron->id) {
        # reset the hold since the copy is now checked out
    
        $logger->info("circulator: un-targeting hold ".$hold->id.
            " because copy ".$copy->id." is getting checked out");

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

    $logger->debug("circulator: checkout fulfilling hold " . $hold->id);

    # if the hold was never officially captured, capture it.
    $hold->current_copy($copy->id);
    $hold->capture_time('now') unless $hold->capture_time;
    $hold->fulfillment_time('now');
    $hold->fulfillment_staff($e->requestor->id);
    $hold->fulfillment_lib($self->circ_lib);

    return $self->bail_on_events($e->event)
        unless $e->update_action_hold_request($hold);

    $holdcode->delete_hold_copy_maps($e, $hold->id);
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

    return undef if $self->volume->id == OILS_PRECAT_CALL_NUMBER; 

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
    my $runner = $self->script_runner;

    my $duration;
    my $recurring;
    my $max_fine;
    my $hard_due_date;
    my $duration_name;
    my $recurring_name;
    my $max_fine_name;
    my $hard_due_date_name;

    if(!$self->legacy_script_support) {
        $self->run_indb_circ_test();
        $duration = $self->circ_matrix_matchpoint->duration_rule;
        $recurring = $self->circ_matrix_matchpoint->recurring_fine_rule;
        $max_fine = $self->circ_matrix_matchpoint->max_fine_rule;
        $hard_due_date = $self->circ_matrix_matchpoint->hard_due_date;

    } else {

       $runner->load($self->circ_duration);

       my $result = $runner->run or 
            throw OpenSRF::EX::ERROR ("Circ Duration Script Died: $@");

       $duration_name   = $result->{durationRule};
       $recurring_name  = $result->{recurringFinesRule};
       $max_fine_name   = $result->{maxFine};
       $hard_due_date_name  = $result->{hardDueDate};
    }

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
      $circ->renewal_remaining($self->renewal_remaining);
      $circ->circ_staff($self->editor->requestor->id);
   }


    # if the user provided an overiding checkout time,
    # (e.g. the checkout really happened several hours ago), then
    # we apply that here.  Does this need a perm??
    $circ->xact_start(cleanse_ISO8601($self->checkout_time))
        if $self->checkout_time;

    # if a patron is renewing, 'requestor' will be the patron
    $circ->circ_staff($self->editor->requestor->id);
    $circ->due_date( $self->create_due_date($circ->duration, $duration_date_ceiling, $duration_date_ceiling_force) ) if $circ->duration;

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

    $self->generate_fines(1);
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

       $circ->due_date(cleanse_ISO8601($self->due_date));

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
        my $bookings = $booking_ses->request(
            'open-ils.booking.reservations.filtered_id_list', $self->editor->authtoken,
            { resource => $booking_item->id, search_start => 'now', search_end => $circ->due_date, fields => { cancel_time => undef, return_time => undef}}
        )->gather(1);
        $booking_ses->disconnect;
        
        my $dt_parser = DateTime::Format::ISO8601->new;
        my $due_date = $dt_parser->parse_datetime( cleanse_ISO8601($circ->due_date) );

        for my $bid (@$bookings) {

            my $booking = $self->editor->retrieve_booking_reservation( $bid );

            my $booking_start = $dt_parser->parse_datetime( cleanse_ISO8601($booking->start_time) );
            my $booking_end = $dt_parser->parse_datetime( cleanse_ISO8601($booking->end_time) );

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

            $circ->due_date(cleanse_ISO8601($due_date->strftime('%FT%T%z')));
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

      $circ->due_date(cleanse_ISO8601($self->due_date));

   } else {

      # if the due_date lands on a day when the location is closed
      return unless $copy and $circ->due_date;

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



sub create_due_date {
    my( $self, $duration, $date_ceiling, $force_date ) = @_;

    # if there is a raw time component (e.g. from postgres), 
    # turn it into an interval that interval_to_seconds can parse
    $duration =~ s/(\d{2}):(\d{2}):(\d{2})/$1 h $2 m $3 s/o;

    # for now, use the server timezone.  TODO: use workstation org timezone
    my $due_date = DateTime->now(time_zone => 'local');

    # add the circ duration
    $due_date->add(seconds => OpenSRF::Utils->interval_to_seconds($duration));

    if($date_ceiling) {
        my $cdate = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($date_ceiling));
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

    # this is a little bit of a hack, but we need to 
    # get the copy into the script runner
    $self->script_runner->insert("environment.copy", $copy, 1) if $self->script_runner;
}


sub checkout_noncat {
    my $self = shift;

    my $circ;
    my $evt;

   my $lib      = $self->noncat_circ_lib || $self->circ_lib;
   my $count    = $self->noncat_count || 1;
   my $cotime   = cleanse_ISO8601($self->checkout_time) || "";

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

# If a copy goes into transit and is then checked in before the transit checkin 
# interval has expired, push an event onto the overridable events list.
sub check_transit_checkin_interval {
    my $self = shift;

    # only concerned with in-transit items
    return unless $U->copy_status($self->copy->status)->id == OILS_COPY_STATUS_IN_TRANSIT;

    # no interval, no problem
    my $interval = $U->ou_ancestor_setting_value($self->circ_lib, 'circ.transit.min_checkin_interval');
    return unless $interval;

    # capture the transit so we don't have to fetch it again later during checkin
    $self->transit(
        $self->editor->search_action_transit_copy(
            {target_copy => $self->copy->id, dest_recv_time => undef}
        )->[0]
    ); 

    # transit from X to X for whatever reason has no min interval
    return if $self->transit->source == $self->transit->dest;

    my $seconds = OpenSRF::Utils->interval_to_seconds($interval);
    my $t_start = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($self->transit->source_send_time));
    my $horizon = $t_start->add(seconds => $seconds);

    # See if we are still within the transit checkin forbidden range
    $self->push_events(OpenILS::Event->new('TRANSIT_CHECKIN_INTERVAL_BLOCK')) 
        if $horizon > DateTime->now;
}

# Retarget local holds at checkin
sub checkin_retarget {
    my $self = shift;
    return unless $self->retarget_mode =~ m/retarget/; # Retargeting?
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
            my $tresult = $U->storagereq('open-ils.storage.action.hold_request.copy_targeter', undef, $_->{id}, $self->copy->id);
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

    # run the fine generator against this circ, if this circ is there
    $self->generate_fines_start if $self->circ;

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
    
    if( $self->copy and !$self->transit ) {
        $self->transit(
            $self->editor->search_action_transit_copy(
                { target_copy => $self->copy->id, dest_recv_time => undef }
            )->[0]
        ); 
    }

    if( $self->circ ) {
        $self->generate_fines_finish;
        $self->checkin_handle_circ;
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

            if( $hold and $hold->cancel_time ) { # this transited hold was cancelled mid-transit

                $logger->info("circulator: we received a transit on a cancelled hold " . $hold->id);
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
    
                if ($U->is_true( $self->copy->floating ) && !$self->remote_hold) { # copy is floating, stick here
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
        if ($U->is_true( $self->copy->floating )) { # XXX floating items still stick where they are even with no-op checkin?
            $self->checkin_changed(1);
            $self->copy->circ_lib( $self->circ_lib );
            $self->update_copy;
        }
    }

    if($self->claims_never_checked_out and 
            $U->ou_ancestor_setting_value($self->circ->circ_lib, 'circ.claim_never_checked_out.mark_missing')) {

        # the item was not supposed to be checked out to the user and should now be marked as missing
        $self->copy->status(OILS_COPY_STATUS_MISSING);
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

    # gather any updates to the circ after fine generation, if there was a circ
    $self->generate_fines_finish;

    return unless $self->backdate or $self->void_overdues;

    # void overdues after fine generation to prevent concurrent DB access to overdue billings
    my $note = 'System: Amnesty Checkin' if $self->void_overdues;

    my $evt = OpenILS::Application::Circ::CircCommon->void_overdues(
        $self->editor, $self->circ, $self->backdate, $note);

    return $self->bail_on_events($evt) if $evt;

    # make sure the circ isn't closed if we just voided some fines
    $evt = OpenILS::Application::Circ::CircCommon->reopen_xact($self->editor, $self->circ->id);
    return $self->bail_on_events($evt) if $evt;

    return undef;
}


# if a deposit was payed for this item, push the event
sub check_circ_deposit {
    my $self = shift;
    return unless $self->circ;
    my $deposit = $self->editor->search_money_billing(
        {   btype => 5, 
            xact => $self->circ->id, 
            voided => 'f'
        }, {idlist => 1})->[0];

    $self->push_events(OpenILS::Event->new(
        'ITEM_DEPOSIT_PAID', payload => $deposit)) if $deposit;
}

sub reshelve_copy {
   my $self    = shift;
   my $force   = $self->force || shift;
   my $copy    = $self->copy;

   my $stat = $U->copy_status($copy->status)->id;

   if($force || (
      $stat != OILS_COPY_STATUS_ON_HOLDS_SHELF and
      $stat != OILS_COPY_STATUS_CATALOGING and
      $stat != OILS_COPY_STATUS_IN_TRANSIT and
      $stat != OILS_COPY_STATUS_RESHELVING  )) {

        $copy->status( OILS_COPY_STATUS_RESHELVING );
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
                $self->hold->pickup_lib($self->circ_lib);
            }
        }
    }

    $logger->info("circulator: found permitted hold ".$hold->id." for copy, capturing...");

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
    my $ses = OpenSRF::AppSession->create('open-ils.storage');
    $ses->request('open-ils.storage.action.hold_request.copy_targeter', undef, $self->retarget);
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

        # hold has arrived at destination, set shelf time
        $self->put_hold_on_shelf($hold);
        $self->bail_on_events($self->editor->event)
            unless $self->editor->update_action_hold_request($hold);
        return if $self->bail_out;

        $self->notify_hold($hold_transit->hold);
        $ishold = 1;
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



sub generate_fines {
   my $self = shift;
   my $reservation = shift;

   $self->generate_fines_start($reservation);
   $self->generate_fines_finish($reservation);

   return undef;
}

sub generate_fines_start {
   my $self = shift;
   my $reservation = shift;
   my $dt_parser = DateTime::Format::ISO8601->new;

   my $obj = $reservation ? $self->reservation : $self->circ;

   # If we have a grace period
   if($obj->can('grace_period')) {
      # Parse out the due date
      my $due_date = $dt_parser->parse_datetime( cleanse_ISO8601($obj->due_date) );
      # Add the grace period to the due date
      $due_date->add(seconds => OpenSRF::Utils->interval_to_seconds($obj->grace_period));
      # Don't generate fines on circs still in grace period
      return undef if ($due_date > DateTime->now);
   }

   if (!exists($self->{_gen_fines_req})) {
      $self->{_gen_fines_req} = OpenSRF::AppSession->create('open-ils.storage') 
          ->request(
             'open-ils.storage.action.circulation.overdue.generate_fines',
             $obj->id
          );
   }

   return undef;
}

sub generate_fines_finish {
   my $self = shift;
   my $reservation = shift;

   return undef unless $self->{_gen_fines_req};

   my $id = $reservation ? $self->reservation->id : $self->circ->id;

   $self->{_gen_fines_req}->wait_complete;
   delete($self->{_gen_fines_req});

   # refresh the circ in case the fine generator set the stop_fines field
   $self->reservation($self->editor->retrieve_booking_reservation($id)) if $reservation;
   $self->circ($self->editor->retrieve_action_circulation($id)) if !$reservation;

   return undef;
}

sub checkin_handle_circ {
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

   if(!$circ->stop_fines) {
      $circ->stop_fines(OILS_STOP_FINES_CHECKIN);
      $circ->stop_fines(OILS_STOP_FINES_RENEW) if $self->is_renewal;
      $circ->stop_fines(OILS_STOP_FINES_CLAIMS_NEVERCHECKEDOUT) if $self->claims_never_checked_out;
      $circ->stop_fines_time('now');
      $circ->stop_fines_time($self->backdate) if $self->backdate;
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

    if ($stat == OILS_COPY_STATUS_LOST) {
        # we will now handle lost fines, but the copy will retain its 'lost'
        # status if it needs to transit home unless lost_immediately_available
        # is true
        #
        # if we decide to also delay fine handling until the item arrives home,
        # we will need to call lost fine handling code both when checking items
        # in and also when receiving transits
        $self->checkin_handle_lost($circ_lib);
    } elsif ($circ_lib != $self->circ_lib and $stat == OILS_COPY_STATUS_MISSING) {
        $logger->info("circulator: not updating copy status on checkin because copy is missing");
    } else {
        $self->copy->status($U->copy_status(OILS_COPY_STATUS_RESHELVING));
        $self->update_copy;
    }


    # see if there are any fines owed on this circ.  if not, close it
    ($obt) = $U->fetch_mbts($circ->id, $self->editor);
    $circ->xact_finish('now') if( $obt and $obt->balance_owed == 0 );

    $logger->debug("circulator: ".$obt->balance_owed." is owed on this circulation");

    return $self->bail_on_events($self->editor->event)
        unless $self->editor->update_action_circulation($circ);

    return undef;
}


# ------------------------------------------------------------------
# See if we need to void billings for lost checkin
# ------------------------------------------------------------------
sub checkin_handle_lost {
    my $self = shift;
    my $circ_lib = shift;
    my $circ = $self->circ;

    my $max_return = $U->ou_ancestor_setting_value(
        $circ_lib, OILS_SETTING_MAX_ACCEPT_RETURN_OF_LOST, $self->editor) || 0;

    if ($max_return) {

        my $today = time();
        my @tm = reverse($circ->due_date =~ /([\d\.]+)/og);
        $tm[5] -= 1 if $tm[5] > 0;
        my $due = timelocal(int($tm[1]), int($tm[2]), int($tm[3]), int($tm[4]), int($tm[5]), int($tm[6]));

        my $last_chance = OpenSRF::Utils->interval_to_seconds($max_return) + int($due);
        $logger->info("MAX OD: ".$max_return."  DUEDATE: ".$circ->due_date."  TODAY: ".$today."  DUE: ".$due."  LAST: ".$last_chance);

        $max_return = 0 if $today < $last_chance;
    }

    if (!$max_return){  # there's either no max time to accept returns defined or we're within that time

        my $void_lost = $U->ou_ancestor_setting_value(
            $circ_lib, OILS_SETTING_VOID_LOST_ON_CHECKIN, $self->editor) || 0;
        my $void_lost_fee = $U->ou_ancestor_setting_value(
            $circ_lib, OILS_SETTING_VOID_LOST_PROCESS_FEE_ON_CHECKIN, $self->editor) || 0;
        my $restore_od = $U->ou_ancestor_setting_value(
            $circ_lib, OILS_SETTING_RESTORE_OVERDUE_ON_LOST_RETURN, $self->editor) || 0;
        $self->generate_lost_overdue(1) if $U->ou_ancestor_setting_value(
            $circ_lib, OILS_SETTING_GENERATE_OVERDUE_ON_LOST_RETURN, $self->editor);

        $self->checkin_handle_lost_now_found(3) if $void_lost;
        $self->checkin_handle_lost_now_found(4) if $void_lost_fee;
        $self->checkin_handle_lost_now_found_restore_od($circ_lib) if $restore_od && ! $self->void_overdues;
    }

    if ($circ_lib != $self->circ_lib) {
        # if the item is not home, check to see if we want to retain the lost
        # status at this point in the process
        my $immediately_available = $U->ou_ancestor_setting_value($circ_lib, OILS_SETTING_LOST_IMMEDIATELY_AVAILABLE, $self->editor) || 0;

        if ($immediately_available) {
            # lost item status does not need to be retained, so give it a
            # reshelving status as if it were a normal checkin
            $self->copy->status($U->copy_status(OILS_COPY_STATUS_RESHELVING));
            $self->update_copy;
        } else {
            $logger->info("circulator: not updating copy status on checkin because copy is lost");
        }
    } else {
        # lost item is home and processed, treat like a normal checkin from
        # this point on
        $self->copy->status($U->copy_status(OILS_COPY_STATUS_RESHELVING));
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
    my $bd = cleanse_ISO8601($self->backdate);
    my $original_date = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($self->circ->due_date));
    my $new_date = DateTime::Format::ISO8601->new->parse_datetime($bd);
    $bd = cleanse_ISO8601($new_date->ymd . 'T' . $original_date->strftime('%T%z'));

    $self->backdate($bd);
    return undef;
}


sub check_checkin_copy_status {
    my $self = shift;
   my $copy = $self->copy;

   my $status = $U->copy_status($copy->status)->id;

   return undef
      if(   $status == OILS_COPY_STATUS_AVAILABLE   ||
            $status == OILS_COPY_STATUS_CHECKED_OUT ||
            $status == OILS_COPY_STATUS_IN_PROCESS  ||
            $status == OILS_COPY_STATUS_ON_HOLDS_SHELF  ||
            $status == OILS_COPY_STATUS_IN_TRANSIT  ||
            $status == OILS_COPY_STATUS_CATALOGING  ||
            $status == OILS_COPY_STATUS_ON_RESV_SHELF  ||
            $status == OILS_COPY_STATUS_RESHELVING );

   return OpenILS::Event->new('COPY_STATUS_LOST', payload => $copy )
      if( $status == OILS_COPY_STATUS_LOST );

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
        # if we checked in a circulation, flesh the billing summary data
        $self->circ->billable_transaction(
            $self->editor->retrieve_money_billable_transaction([
                $self->circ->id,
                {flesh => 1, flesh_fields => {mbt => ['summary']}}
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
        $self->barcode;
    $bc ||= "";
    my $usr = ($self->patron) ? $self->patron->id : "";
    $logger->info("circulator: $msg requestor=".$self->editor->requestor->id.
        ", recipient=$usr, copy=$bc");
}


sub do_renew {
    my $self = shift;
    $self->log_me("do_renew()");

    # Make sure there is an open circ to renew that is not
    # marked as LOST, CLAIMSRETURNED, or LONGOVERDUE
    my $usrid = $self->patron->id if $self->patron;
    my $circ = $self->editor->search_action_circulation({
        target_copy => $self->copy->id,
        xact_finish => undef,
        checkin_time => undef,
        ($usrid ? (usr => $usrid) : ()),
        '-or' => [
            {stop_fines => undef},
            {stop_fines => OILS_STOP_FINES_MAX_FINES}
        ]
    })->[0];

    return $self->bail_on_events($self->editor->event) unless $circ;

    # A user is not allowed to renew another user's items without permission
    unless( $circ->usr eq $self->editor->requestor->id ) {
        return $self->bail_on_events($self->editor->events)
            unless $self->editor->allowed('RENEW_CIRC', $circ->circ_lib);
    }   

    $self->push_events(OpenILS::Event->new('MAX_RENEWALS_REACHED'))
        if $circ->renewal_remaining < 1;

    # -----------------------------------------------------------------

    $self->parent_circ($circ->id);
    $self->renewal_remaining( $circ->renewal_remaining - 1 );
    $self->circ($circ);

    # Opac renewal - re-use circ library from original circ (unless told not to)
    if($self->opac_renewal) {
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

    # Run the fine generator against the old circ
    $self->generate_fines_start;

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

    if(!$self->legacy_script_support) {
        my $results = $self->run_indb_circ_test;
        $self->push_events($self->matrix_test_result_events)
            unless $self->circ_test_success;
    } else {

        my $runner = $self->script_runner;

        $runner->load($self->circ_permit_renew);
        my $result = $runner->run or 
            throw OpenSRF::EX::ERROR ("Circ Permit Renew Script Died: $@");
        if ($result->{"events"}) {
            $self->push_events(
                map { new OpenILS::Event($_) } @{$result->{"events"}}
            );
            $logger->activity(
                "circulator: circ_permit_renew for user " .
                $self->patron->id . " returned " .
                scalar(@{$result->{"events"}}) . " event(s)"
            );
        }

        $self->mk_script_runner;
    }

    $logger->debug("circulator: re-creating script runner to be safe");
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



sub checkin_handle_lost_now_found {
    my ($self, $bill_type) = @_;

    # ------------------------------------------------------------------
    # remove charge from patron's account if lost item is returned
    # ------------------------------------------------------------------

    my $bills = $self->editor->search_money_billing(
        {
            xact => $self->circ->id,
            btype => $bill_type
        }
    );

    $logger->debug("voiding lost item charge of  ".scalar(@$bills));
    for my $bill (@$bills) {
        if( !$U->is_true($bill->voided) ) {
            $logger->info("lost item returned - voiding bill ".$bill->id);
            $bill->voided('t');
            $bill->void_time('now');
            $bill->voider($self->editor->requestor->id);
            my $note = ($bill->note) ? $bill->note . "\n" : '';
            $bill->note("${note}System: VOIDED FOR LOST ITEM RETURNED");

            $self->bail_on_events($self->editor->event)
                unless $self->editor->update_money_billing($bill);
        }
    }
}

sub checkin_handle_lost_now_found_restore_od {
    my $self = shift;
    my $circ_lib = shift;

    # ------------------------------------------------------------------
    # restore those overdue charges voided when item was set to lost
    # ------------------------------------------------------------------

    my $ods = $self->editor->search_money_billing(
        {
                xact => $self->circ->id,
                btype => 1
        }
    );

    $logger->debug("returning overdue charges pre-lost  ".scalar(@$ods));
    for my $bill (@$ods) {
        if( $U->is_true($bill->voided) ) {
                $logger->info("lost item returned - restoring overdue ".$bill->id);
                $bill->voided('f');
                $bill->clear_void_time;
                $bill->voider($self->editor->requestor->id);
                my $note = ($bill->note) ? $bill->note . "\n" : '';
                $bill->note("${note}System: LOST RETURNED - OVERDUES REINSTATED");

                $self->bail_on_events($self->editor->event)
                        unless $self->editor->update_money_billing($bill);
        }
    }
}

# ------------------------------------------------------------------
# Lost-then-found item checked in.  This sub generates new overdue
# fines, beyond the point of any existing and possibly voided 
# overdue fines, up to the point of final checkin time (or max fine
# amount).  
# ------------------------------------------------------------------
sub generate_lost_overdue_fines {
    my $self = shift;
    my $circ = $self->circ;
    my $e = $self->editor;

    # Re-open the transaction so the fine generator can see it
    if($circ->xact_finish or $circ->stop_fines) {
        $e->xact_begin;
        $circ->clear_xact_finish;
        $circ->clear_stop_fines;
        $circ->clear_stop_fines_time;
        $e->update_action_circulation($circ) or return $e->die_event;
        $e->xact_commit;
    }

    $e->xact_begin; # generate_fines expects an in-xact editor
    $self->generate_fines;
    $circ = $self->circ; # generate fines re-fetches the circ
    
    my $update = 0;

    # Re-close the transaction if no money is owed
    my ($obt) = $U->fetch_mbts($circ->id, $e);
    if ($obt and $obt->balance_owed == 0) {
        $circ->xact_finish('now');
        $update = 1;
    }

    # Set stop fines if the fine generator didn't have to
    unless($circ->stop_fines) {
        $circ->stop_fines(OILS_STOP_FINES_CHECKIN);
        $circ->stop_fines_time('now');
        $update = 1;
    }

    # update the event data sent to the caller within the transaction
    $self->checkin_flesh_events;

    if ($update) {
        $e->update_action_circulation($circ) or return $e->die_event;
        $e->commit;
    } else {
        $e->rollback;
    }

    return undef;
}

1;
