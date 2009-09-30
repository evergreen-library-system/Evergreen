package OpenILS::Application::Circ::Circulate;
use strict; use warnings;
use base 'OpenILS::Application';
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Const qw/:const/;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";

my %scripts;
my $script_libs;
my $legacy_script_support = 0;

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

    $scripts{circ_permit_patron}    = $p;
    $scripts{circ_permit_copy}      = $c;
    $scripts{circ_duration}         = $d;
    $scripts{circ_recurring_fines}= $f;
    $scripts{circ_max_fines}        = $m;
    $scripts{circ_permit_renew} = $pr;

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
    method  => "run_method",
    api_name    => "open-ils.circ.checkin.override",
    signature   => q/@see open-ils.circ.checkin/
);

__PACKAGE__->register_method(
    method  => "run_method",
    api_name    => "open-ils.circ.renew.override",
    signature   => q/@see open-ils.circ.renew/,
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
    method  => "run_method",
    api_name    => "open-ils.circ.checkout.full");
__PACKAGE__->register_method(
    method  => "run_method",
    api_name    => "open-ils.circ.checkout.full.override");

__PACKAGE__->register_method(
    method  => "run_method",
    api_name    => "open-ils.circ.checkout.inspect",
    desc => q/
        Returns the circ matrix test result and, on success, the rule set and matrix test object
    /
);



sub run_method {
    my( $self, $conn, $auth, $args ) = @_;
    translate_legacy_args($args);
    my $api = $self->api_name;

    my $circulator = 
        OpenILS::Application::Circ::Circulator->new($auth, %$args);

    return circ_events($circulator) if $circulator->bail_out;

    # --------------------------------------------------------------------------
    # Go ahead and load the script runner to make sure we have all 
    # of the objects we need
    # --------------------------------------------------------------------------
    $circulator->is_renewal(1) if $api =~ /renew/;
    $circulator->is_checkin(1) if $api =~ /checkin/;

    if($legacy_script_support and not $circulator->is_checkin) {
        $circulator->mk_script_runner();
        $circulator->legacy_script_support(1);
        $circulator->circ_permit_patron($scripts{circ_permit_patron});
        $circulator->circ_permit_copy($scripts{circ_permit_copy});      
        $circulator->circ_duration($scripts{circ_duration});             
        $circulator->circ_permit_renew($scripts{circ_permit_renew});
    } else {
        $circulator->mk_env();
    }
    return circ_events($circulator) if $circulator->bail_out;

    
    $circulator->override(1) if $api =~ /override/o;

    if( $api =~ /checkout\.permit/ ) {
        $circulator->do_permit();

    } elsif( $api =~ /checkout.full/ ) {

        # requesting a precat checkout implies that any required
        # overrides have been performed.  Go ahead and re-override.
        $circulator->override(1) if $circulator->request_precat;
        $circulator->do_permit();
        $circulator->is_checkout(1);
        unless( $circulator->bail_out ) {
            $circulator->events([]);
            $circulator->do_checkout();
        }

    } elsif( $api =~ /inspect/ ) {
        my $data = $circulator->do_inspect();
        $circulator->editor->rollback;
        return $data;

    } elsif( $api =~ /checkout/ ) {
        $circulator->is_checkout(1);
        $circulator->do_checkout();

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
        $logger->info("circulator: bailing out with events: @ee");

        $circulator->editor->rollback;

    } else {
        $circulator->editor->commit;
    }

    $circulator->script_runner->cleanup if $circulator->script_runner;
    
    $conn->respond_complete(circ_events($circulator));

    unless($circulator->bail_out) {
        $circulator->do_hold_notify($circulator->notify_hold)
            if $circulator->notify_hold;
        $circulator->retarget_holds if $circulator->retarget;
        $circulator->append_reading_list;
        $circulator->make_trigger_events;
    }
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
    is_noncat
    is_precat
    request_precat
    is_checkin
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
    due_date
    fulfilled_holds
    transit
    checkin_changed
    force
    old_circ
    permit_override
    pending_checkouts
    cancelled_hold_transit
    opac_renewal
    phone_renewal
    desk_renewal
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
        $self->opac_renewal or $self->phone_renewal;

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
        $logger->info("circulator: pushing event ".$e->{textcode});
        push( @{$self->events}, $e ) unless
            grep { $_->{textcode} eq $e->{textcode} } @{$self->events};
    }
}

sub mk_permit_key {
    my $self = shift;
    my $key = md5_hex( time() . rand() . "$$" );
    $self->cache_handle->put_cache( "oils_permit_key_$key", 1, 300 );
    return $self->permit_key($key);
}

sub check_permit_key {
    my $self = shift;
    my $key = $self->permit_key;
    return 0 unless $key;
    my $k = "oils_permit_key_$key";
    my $one = $self->cache_handle->get_cache($k);
    $self->cache_handle->delete_cache($k);
    return ($one) ? 1 : 0;
}

sub mk_env {
    my $self = shift;
    my $e = $self->editor;

    # --------------------------------------------------------------------------
    # Grab the fleshed copy
    # --------------------------------------------------------------------------
    unless($self->is_noncat) {
        my $copy;
	    my $flesh = { 
		    flesh => 2, 
		    flesh_fields => {acp => ['call_number'], acn => ['record']} 
	    };
	    if($self->copy_id) {
		    $copy = $e->retrieve_asset_copy(
			    [$self->copy_id, $flesh ]) or return $e->event;
    
	    } elsif( $self->copy_barcode ) {
    
		    $copy = $e->search_asset_copy(
			    [{barcode => $self->copy_barcode, deleted => 'f'}, $flesh ])->[0];
	    }
    
        if($copy) {
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
	if( $self->patron_id ) {
		$patron = $e->retrieve_actor_user($self->patron_id) or return $e->event;

	} elsif( $self->patron_barcode ) {

		my $card = $e->search_actor_card( 
			{barcode => $self->patron_barcode})->[0] or return $e->event;

		$patron = $e->search_actor_user( 
			{card => $card->id})->[0] or return $e->event;

	} else {
		if( my $copy = $self->copy ) {
			my $circs = $e->search_action_circulation(
				{target_copy => $copy->id, checkin_time => undef});

			if( my $circ = $circs->[0] ) {
				$patron = $e->retrieve_actor_user($circ->usr)
					or return $e->event;
			}
		}
	}

    return $self->bail_on_events(OpenILS::Event->new('ACTOR_USER_NOT_FOUND'))
        unless $self->patron($patron) or $self->is_checkin;
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

            my $payload; # event payload

            if($old_circ->usr == $self->patron->id) {
                
                $payload = {old_circ => $old_circ};

                # If there is an open circulation on the checkout item and an auto-renew 
                # interval is defined, inform the caller that they should go 
                # ahead and renew the item instead of warning about open circulations.
    
                my $auto_renew_intvl = $U->ou_ancestor_setting_value(        
                    $self->editor->requestor->ws_ou, 
                    'circ.checkout_auto_renew_age', 
                    $self->editor
                );

                if($auto_renew_intvl) {
                    my $intvl_seconds = OpenSRF::Utils->interval_to_seconds($auto_renew_intvl);
                    my $checkout_time = DateTime::Format::ISO8601->new->parse_datetime( clense_ISO8601($old_circ->xact_start) );

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
            push(@allevents, OpenILS::Event->new(
                $LEGACY_CIRC_EVENT_MAP->{$_->{fail_part}} || $_->{fail_part}
                )) for @$results;
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

    $logger->info("circulator: permit_patron script returned events: @allevents") if @allevents;

    $self->push_events(@allevents);
}

sub run_indb_circ_test {
    my $self = shift;
    return $self->matrix_test_result if $self->matrix_test_result;

    my $dbfunc = ($self->is_renewal) ? 
        'action.item_user_renew_test' : 'action.item_user_circ_test';

    my $results = $self->editor->json_query(
        {   from => [
                $dbfunc,
                $self->editor->requestor->ws_ou,
                ($self->is_precat or $self->is_noncat) ? undef : $self->copy->id, 
                $self->patron->id,
            ]
        }
    );

    $self->circ_test_success($U->is_true($results->[0]->{success}));

    if(my $mp = $results->[0]->{matchpoint}) {
        $self->circ_matrix_matchpoint(
            $self->editor->retrieve_config_circ_matrix_matchpoint([
                $mp,
                {   flesh => 1,
                    flesh_fields => {ccmm => 
                        ['duration_rule', 'recurring_fine_rule', 'max_fine_rule']}
                }
            ])
        );
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
    };

    unless($self->circ_test_success) {
        push(@{$results->{failure_codes}}, 
            $_->{fail_part}) for @{$self->matrix_test_result};
        push(@{$results->{failure_events}}, 
            $LEGACY_CIRC_EVENT_MAP->{$_->{fail_part}} || $_->{fail_part}) 
                for @{$self->matrix_test_result};
    }

    if($self->circ_matrix_matchpoint) {
        my $duration_rule = $self->circ_matrix_matchpoint->duration_rule;
        my $recurring_fine_rule = $self->circ_matrix_matchpoint->recurring_fine_rule;
        my $max_fine_rule = $self->circ_matrix_matchpoint->max_fine_rule;
    
        my $policy = $self->get_circ_policy(
            $duration_rule, $recurring_fine_rule, $max_fine_rule);
    
        $$results{$_} = $$policy{$_} for keys %$policy;
    }

    return $results;
}

# ---------------------------------------------------------------------
# Loads the circ policy info for duration, recurring fine, and max
# fine based on the current copy
# ---------------------------------------------------------------------
sub get_circ_policy {
    my($self, $duration_rule, $recurring_fine_rule, $max_fine_rule) = @_;

    my $policy = {
        duration_rule => $duration_rule->name,
        recurring_fine_rule => $recurring_fine_rule->name,
        max_fine_rule => $max_fine_rule->name,
        max_fine => $self->get_max_fine_amount($max_fine_rule),
        fine_interval => $recurring_fine_rule->recurance_interval,
        renewal_remaining => $duration_rule->max_renewals
    };

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
        unless($self->circ_test_success) {
            push(@allevents, OpenILS::Event->new(
                $LEGACY_CIRC_EVENT_MAP->{$_->{fail_part}} || $_->{fail_part}
                )) for @$results;
        }
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

   for (@allevents) {
      $_->{payload} = $copy if 
            ($_->{textcode} eq 'COPY_NOT_AVAILABLE');
   }

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

    if(!$self->override) {
        return $self->bail_out(1) 
            if( @events > 1 or $events[0]->{textcode} ne 'SUCCESS' );
    }   

    $self->events([]);
    
   for my $e (@events) {
      my $tc = $e->{textcode};
      next if $tc eq 'SUCCESS';
      my $ov = "$tc.override";
      $logger->info("circulator: attempting to override event: $ov");

        return $self->bail_on_events($self->editor->event)
            unless( $self->editor->allowed($ov) );
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
    if($self->override) {

        $CR->checkin_time('now');   
        $CR->checkin_scan_time('now');   
        $CR->checkin_lib($self->editor->requestor->ws_ou);
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

    $self->apply_modified_due_date();
    return if $self->bail_out;

    return $self->bail_on_events($self->editor->event)
        unless $self->editor->create_action_circulation($self->circ);

    # refresh the circ to force local time zone for now
    $self->circ($self->editor->retrieve_action_circulation($self->circ->id));

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
    $self->push_events(
        OpenILS::Event->new('SUCCESS',
            payload  => {
                copy              => $U->unflesh_copy($self->copy),
                circ              => $self->circ,
                record            => $record,
                holds_fulfilled   => $self->fulfilled_holds,
                deposit_billing      => $self->deposit_billing,
                rental_billing       => $self->rental_billing
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
    $hold->fulfillment_lib($e->requestor->ws_ou);

    return $self->bail_on_events($e->event)
        unless $e->update_action_hold_request($hold);

    $holdcode->delete_hold_copy_maps($e, $hold->id);
    return $self->fulfilled_holds([$hold->id]);
}


# ------------------------------------------------------------------------------
# If the circ.checkout_fill_related_hold setting is turned on and no hold for
# the patron directly targets the checked out item, see if there is another hold 
# (with hold_type T or V) for the patron that could be fulfilled by the checked 
# out item.  Fulfill the oldest hold and only fulfill 1 of them.
# ------------------------------------------------------------------------------
sub find_related_user_hold {
    my($self, $copy, $patron) = @_;
    my $e = $self->editor;

    return undef if $self->volume->id == OILS_PRECAT_CALL_NUMBER; 

    return undef unless $U->ou_ancestor_setting_value(        
        $e->requestor->ws_ou, 'circ.checkout_fills_related_hold', $e);

    # find the oldest unfulfilled hold that has not yet hit the holds shelf.
    my $args = {
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

    my $hold_info = $e->json_query($args)->[0];
    return $e->retrieve_action_hold_request($hold_info->{id}) if $hold_info;
    return undef;
}


sub run_checkout_scripts {
    my $self = shift;

    my $evt;
    my $runner = $self->script_runner;

    my $duration;
    my $recurring;
    my $max_fine;
    my $duration_name;
    my $recurring_name;
    my $max_fine_name;

    if(!$self->legacy_script_support) {
        $self->run_indb_circ_test();
        $duration = $self->circ_matrix_matchpoint->duration_rule;
        $recurring = $self->circ_matrix_matchpoint->recurring_fine_rule;
        $max_fine = $self->circ_matrix_matchpoint->max_fine_rule;

    } else {

       $runner->load($self->circ_duration);

       my $result = $runner->run or 
            throw OpenSRF::EX::ERROR ("Circ Duration Script Died: $@");

       $duration_name   = $result->{durationRule};
       $recurring_name  = $result->{recurringFinesRule};
       $max_fine_name   = $result->{maxFine};
    }

    $duration_name = $duration->name if $duration;
    if( $duration_name ne OILS_UNLIMITED_CIRC_DURATION ) {

        unless($duration) {
            ($duration, $evt) = $U->fetch_circ_duration_by_name($duration_name);
            return $self->bail_on_events($evt) if $evt;
        
            ($recurring, $evt) = $U->fetch_recurring_fine_by_name($recurring_name);
            return $self->bail_on_events($evt) if $evt;
        
            ($max_fine, $evt) = $U->fetch_max_fine_by_name($max_fine_name);
            return $self->bail_on_events($evt) if $evt;
        }

    } else {

        # The item circulates with an unlimited duration
        $duration   = undef;
        $recurring  = undef;
        $max_fine   = undef;
    }

   $self->duration_rule($duration);
   $self->recurring_fines_rule($recurring);
   $self->max_fine_rule($max_fine);
}


sub build_checkout_circ_object {
    my $self = shift;

   my $circ       = Fieldmapper::action::circulation->new;
   my $duration   = $self->duration_rule;
   my $max        = $self->max_fine_rule;
   my $recurring  = $self->recurring_fines_rule;
   my $copy       = $self->copy;
   my $patron     = $self->patron;

    if( $duration ) {

        my $policy = $self->get_circ_policy($duration, $recurring, $max);

        my $dname = $duration->name;
        my $mname = $max->name;
        my $rname = $recurring->name;

        $logger->debug("circulator: building circulation ".
            "with duration=$dname, maxfine=$mname, recurring=$rname");
    
        $circ->duration($policy->{duration});
        $circ->recuring_fine($policy->{recurring_fine});
        $circ->duration_rule($duration->name);
        $circ->recuring_fine_rule($recurring->name);
        $circ->max_fine_rule($max->name);
        $circ->max_fine($policy->{max_fine});
        $circ->fine_interval($recurring->recurance_interval);
        $circ->renewal_remaining($duration->max_renewals);

    } else {

        $logger->info("circulator: copy found with an unlimited circ duration");
        $circ->duration_rule(OILS_UNLIMITED_CIRC_DURATION);
        $circ->recuring_fine_rule(OILS_UNLIMITED_CIRC_DURATION);
        $circ->max_fine_rule(OILS_UNLIMITED_CIRC_DURATION);
        $circ->renewal_remaining(0);
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
    $circ->xact_start(clense_ISO8601($self->checkout_time))
        if $self->checkout_time;

    # if a patron is renewing, 'requestor' will be the patron
    $circ->circ_staff($self->editor->requestor->id);
    $circ->due_date( $self->create_due_date($circ->duration) ) if $circ->duration;

    $self->circ($circ);
}


sub apply_modified_due_date {
    my $self = shift;
    my $circ = $self->circ;
    my $copy = $self->copy;

   if( $self->due_date ) {

        return $self->bail_on_events($self->editor->event)
            unless $self->editor->allowed('CIRC_OVERRIDE_DUE_DATE', $self->circ_lib);

      $circ->due_date(clense_ISO8601($self->due_date));

   } else {

      # if the due_date lands on a day when the location is closed
      return unless $copy and $circ->due_date;

        #my $org = (ref $copy->circ_lib) ? $copy->circ_lib->id : $copy->circ_lib;

        # due-date overlap should be determined by the location the item
        # is checked out from, not the owning or circ lib of the item
        my $org = $self->editor->requestor->ws_ou;

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
            $circ->due_date($dateinfo->{end});
      }
   }
}



sub create_due_date {
    my( $self, $duration ) = @_;

    # if there is a raw time component (e.g. from postgres), 
    # turn it into an interval that interval_to_seconds can parse
    $duration =~ s/(\d{2}):(\d{2}):(\d{2})/$1 h $2 m $3 s/o;

    # for now, use the server timezone.  TODO: use workstation org timezone
    my $due_date = DateTime->now(time_zone => 'local');

    # add the circ duration
    $due_date->add(seconds => OpenSRF::Utils->interval_to_seconds($duration));

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

   my $lib      = $self->noncat_circ_lib || $self->editor->requestor->ws_ou;
   my $count    = $self->noncat_count || 1;
   my $cotime   = clense_ISO8601($self->checkout_time) || "";

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


sub do_checkin {
    my $self = shift;
    $self->log_me("do_checkin()");

    return $self->bail_on_events(
        OpenILS::Event->new('ASSET_COPY_NOT_FOUND')) 
        unless $self->copy;

    if( $self->checkin_check_holds_shelf() ) {
        $self->bail_on_events(OpenILS::Event->new('NO_CHANGE'));
        $self->hold($U->fetch_open_hold_by_copy($self->copy->id));
        $self->checkin_flesh_events;
        return;
    }

    unless( $self->is_renewal ) {
        return $self->bail_on_events($self->editor->event)
            unless $self->editor->allowed('COPY_CHECKIN');
    }

    $self->push_events($self->check_copy_alert());
    $self->push_events($self->check_checkin_copy_status());

    # the renew code will have already found our circulation object
    unless( $self->is_renewal and $self->circ ) {
        my $circs = $self->editor->search_action_circulation(
            { target_copy => $self->copy->id, checkin_time => undef });
        $self->circ($$circs[0]);

        # for now, just warn if there are multiple open circs on a copy
        $logger->warn("circulator: we have ".scalar(@$circs).
            " open circs for copy " .$self->copy->id."!!") if @$circs > 1;
    }

    # run the fine generator against this circ, if this circ is there
    $self->generate_fines if ($self->circ);

    # if the circ is marked as 'claims returned', add the event to the list
    $self->push_events(OpenILS::Event->new('CIRC_CLAIMS_RETURNED'))
        if ($self->circ and $self->circ->stop_fines 
                and $self->circ->stop_fines eq OILS_STOP_FINES_CLAIMSRETURNED);

    $self->check_circ_deposit();

    # handle the overridable events 
    $self->override_events unless $self->is_renewal;
    return if $self->bail_out;
    
    if( $self->copy ) {
        $self->transit(
            $self->editor->search_action_transit_copy(
            { target_copy => $self->copy->id, dest_recv_time => undef })->[0]); 
    }

    if( $self->circ ) {
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
                return if $self->bail_out;

            } else {

                # hold transited to correct location
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
        $self->push_events(OpenILS::Event->new('SUCCESS'));
        return;
    }

   # ------------------------------------------------------------------------------
   # Circulations and transits are now closed where necessary.  Now go on to see if
   # this copy can fulfill a hold or needs to be routed to a different location
   # ------------------------------------------------------------------------------

    unless($self->noop) { # no-op checkins to not capture holds or put items into transit

        my $needed_for_hold = (!$self->remote_hold and $self->attempt_checkin_hold_capture());
        return if $self->bail_out;
    
        unless($needed_for_hold) {
            my $circ_lib = (ref $self->copy->circ_lib) ? 
                    $self->copy->circ_lib->id : $self->copy->circ_lib;
    
            if( $self->remote_hold ) {
                $circ_lib = $self->remote_hold->pickup_lib;
                $logger->warn("circulator: Copy ".$self->copy->barcode.
                    " is on a remote hold's shelf, sending to $circ_lib");
            }
    
            $logger->debug("circulator: circlib=$circ_lib, workstation=".$self->editor->requestor->ws_ou);
    
            if( $circ_lib == $self->editor->requestor->ws_ou ) {
    
                $self->checkin_handle_precat();
                return if $self->bail_out;
    
            } else {
    
                my $bc = $self->copy->barcode;
                $logger->info("circulator: copy $bc at the wrong location, sending to $circ_lib");
                $self->checkin_build_copy_transit($circ_lib);
                return if $self->bail_out;
                $self->push_events(OpenILS::Event->new('ROUTE_ITEM', org => $circ_lib));
            }
        }
    }

    $self->reshelve_copy;
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

    OpenILS::Utils::Penalty->calculate_penalties(
        $self->editor, $self->patron->id, $self->circ_lib) if $self->patron;

    $self->checkin_flesh_events;
    return;
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

    if( $hold->pickup_lib == $self->editor->requestor->ws_ou ) {
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

    #$dest  ||= (ref($copy->circ_lib)) ? $copy->circ_lib->id : $copy->circ_lib;
    $logger->info("circulator: transiting copy to $dest");

   $transit->source($self->editor->requestor->ws_ou);
   $transit->dest($dest);
   $transit->target_copy($copy->id);
   $transit->source_send_time('now');
   $transit->copy_status( $U->copy_status($copy->status)->id );

    $logger->debug("circulator: setting copy status on transit: ".$transit->copy_status);

    return $self->bail_on_events($self->editor->event)
        unless $self->editor->create_action_transit_copy($transit);

   $copy->status(OILS_COPY_STATUS_IN_TRANSIT);
    $self->update_copy;
    $self->checkin_changed(1);
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
        my $location = $self->editor->retrieve_asset_copy_location($self->copy->location);
        if($U->is_true($location->hold_verify)) {
            $self->bail_on_events(
                OpenILS::Event->new('HOLD_CAPTURE_DELAYED', copy_location => $location));
            return 1;
        }
    }

    $self->retarget($retarget);

    $logger->info("circulator: found permitted hold ".$hold->id." for copy, capturing...");

    $hold->current_copy($copy->id);
    $hold->capture_time('now');
    $hold->shelf_time('now') 
        if $hold->pickup_lib == $self->editor->requestor->ws_ou;

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

    if( $hold->pickup_lib == $self->editor->requestor->ws_ou ) {

        # This hold was captured in the correct location
        $copy->status(OILS_COPY_STATUS_ON_HOLDS_SHELF);
        $self->push_events(OpenILS::Event->new('SUCCESS'));

        #$self->do_hold_notify($hold->id);
        $self->notify_hold($hold->id);

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
    return 1;
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

        $logger->warn("circulator:  * hold notify failed for hold $holdid");

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
   $trans->source($self->editor->requestor->ws_ou);
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

    if( $transit->dest != $self->editor->requestor->ws_ou ) {
        # - this item is in-transit to a different location

        my $tid = $transit->id; 
        my $loc = $self->editor->requestor->ws_ou;
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
        $hold->shelf_time('now');
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


sub generate_fines {
   my $self = shift;
   my $evt;
   my $obt;

   my $st = OpenSRF::AppSession->connect('open-ils.storage');

   $st->request(
      'open-ils.storage.action.circulation.overdue.generate_fines',
      undef,
      $self->circ->id
   )->wait_complete;

   $st->disconnect;

   # refresh the circ in case the fine generator set the stop_fines field
   $self->circ($self->editor->retrieve_action_circulation($self->circ->id));

   return undef;
}

sub checkin_handle_circ {
   my $self = shift;
   my $circ = $self->circ;
   my $copy = $self->copy;
   my $evt;
   my $obt;

   # backdate the circ if necessary
   if($self->backdate) {
        $self->checkin_handle_backdate;
        return if $self->bail_out;
   }

   if($self->void_overdues) {
        my $evt = OpenILS::Application::Circ::CircCommon->void_overdues(
            $self->editor, $circ, undef, 'System: Amnesty Checkin'); # TODO i18n for system-generated notes
        return $self->bail_on_events($evt) if $evt;
   }

   if(!$circ->stop_fines) {
      $circ->stop_fines(OILS_STOP_FINES_CHECKIN);
      $circ->stop_fines(OILS_STOP_FINES_RENEW) if $self->is_renewal;
      $circ->stop_fines_time('now') unless $self->backdate;
      $circ->stop_fines_time($self->backdate) if $self->backdate;
   }

   # see if there are any fines owed on this circ.  if not, close it
    ($obt) = $U->fetch_mbts($circ->id, $self->editor);
    $circ->xact_finish('now') if( $obt and $obt->balance_owed == 0 );

    $logger->debug("circulator: ".$obt->balance_owed." is owed on this circulation");

    # Set the checkin vars since we have the item
    $circ->checkin_time( ($self->backdate) ? $self->backdate : 'now' );

    # capture the true scan time for back-dated checkins
    $circ->checkin_scan_time('now');

    $circ->checkin_staff($self->editor->requestor->id);
    $circ->checkin_lib($self->editor->requestor->ws_ou);
    $circ->checkin_workstation($self->editor->requestor->wsid);

    my $circ_lib = (ref $self->copy->circ_lib) ?  
        $self->copy->circ_lib->id : $self->copy->circ_lib;
    my $stat = $U->copy_status($self->copy->status)->id;

    # immediately available keeps items lost or missing items from going home before being handled
    my $lost_immediately_available = $U->ou_ancestor_setting_value(
        $circ_lib, OILS_SETTING_LOST_IMMEDIATELY_AVAILABLE, $self->editor) || 0;


    if ( (!$lost_immediately_available) && ($circ_lib != $self->editor->requestor->ws_ou) ) {

        if( ($stat == OILS_COPY_STATUS_LOST or $stat == OILS_COPY_STATUS_MISSING) ) {
            $logger->info("circulator: not updating copy status on checkin because copy is lost/missing");
        } else {
            $self->copy->status($U->copy_status(OILS_COPY_STATUS_RESHELVING));
            $self->update_copy;
        }

    } elsif ($stat == OILS_COPY_STATUS_LOST) {

        $self->checkin_handle_lost($circ_lib);

    } else {

        $self->copy->status($U->copy_status(OILS_COPY_STATUS_RESHELVING));
        $self->update_copy;
    }

    return $self->bail_on_events($self->editor->event)
        unless $self->editor->update_action_circulation($circ);

    # make sure the circ isn't closed if we just voided some fines
    $evt = OpenILS::Application::Circ::CircCommon->reopen_xact($self->editor, $circ->id);
    return $self->bail_on_events($evt) if $evt;

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

        $self->checkin_handle_lost_now_found(3) if $void_lost;
        $self->checkin_handle_lost_now_found(4) if $void_lost_fee;
        $self->checkin_handle_lost_now_found_restore_od() if $restore_od;
    }

    $self->copy->status($U->copy_status(OILS_COPY_STATUS_RESHELVING));
    $self->update_copy;
}


sub checkin_handle_backdate {
    my $self = shift;

    my $bd = $self->backdate;

    # ------------------------------------------------------------------
    # clean up the backdate for date comparison
    # we want any bills created on or after the backdate
    # ------------------------------------------------------------------
    $bd =~ s/^(\d{4}-\d{2}-\d{2}).*/$1/og;
    #$bd = "${bd}T23:59:59";

    my $bills = $self->editor->search_money_billing(
        { 
            billing_ts => { '>=' => $bd }, 
            xact => $self->circ->id, 
            btype => 1
        }
    );

    $logger->debug("backdate found ".scalar(@$bills)." bills to void");

    for my $bill (@$bills) {    
        unless( $U->is_true($bill->voided) ) {
            $logger->info("backdate voiding bill ".$bill->id);
            $bill->voided('t');
            $bill->void_time('now');
            $bill->voider($self->editor->requestor->id);
            my $n = $bill->note || "";
            $bill->note("$n\nSystem: VOIDED FOR BACKDATE");

            $self->bail_on_events($self->editor->event)
                unless $self->editor->update_money_billing($bill);
        }
    }
}




sub find_patron_from_copy {
    my $self = shift;
    my $circs = $self->editor->search_action_circulation(
        { target_copy => $self->copy->id, checkin_time => undef });
    my $circ = $circs->[0];
    return unless $circ;
    my $u = $self->editor->retrieve_actor_user($circ->usr)
        or return $self->bail_on_events($self->editor->event);
    $self->patron($u);
}

sub check_checkin_copy_status {
    my $self = shift;
   my $copy = $self->copy;

   my $islost     = 0;
   my $ismissing  = 0;
   my $evt        = undef;

   my $status = $U->copy_status($copy->status)->id;

   return undef
      if(   $status == OILS_COPY_STATUS_AVAILABLE   ||
            $status == OILS_COPY_STATUS_CHECKED_OUT ||
            $status == OILS_COPY_STATUS_IN_PROCESS  ||
            $status == OILS_COPY_STATUS_ON_HOLDS_SHELF  ||
            $status == OILS_COPY_STATUS_IN_TRANSIT  ||
            $status == OILS_COPY_STATUS_CATALOGING  ||
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
            $self->editor->retrieve_billable_transaction([
                $self->circ->id,
                {flesh => 1, flesh_fields => {mbt => ['summary']}}
            ])
        );
    }

    for my $evt (@{$self->events}) {

        my $payload         = {};
        $payload->{copy}    = $U->unflesh_copy($self->copy);
        $payload->{record}  = $record,
        $payload->{circ}    = $self->circ;
        $payload->{transit} = $self->transit;
        $payload->{cancelled_hold_transit} = 1 if $self->cancelled_hold_transit;
        $payload->{hold}    = $hold;
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
    my $circ;
    if ($usrid) {
        # If we have a patron, match them to the circ
        $circ = $self->editor->search_action_circulation(
            {target_copy => $self->copy->id, usr => $usrid,  stop_fines => undef})->[0];
    } else {
        $circ = $self->editor->search_action_circulation(
            {target_copy => $self->copy->id, stop_fines => undef})->[0];
    }

    if(!$circ) {
        if ($usrid) {
            $circ = $self->editor->search_action_circulation(
                {target_copy => $self->copy->id, usr => $usrid, stop_fines => OILS_STOP_FINES_MAX_FINES, checkin_time => undef})->[0];
        } else {
            $circ = $self->editor->search_action_circulation(
                {target_copy => $self->copy->id, stop_fines => OILS_STOP_FINES_MAX_FINES, checkin_time => undef})->[0];
        }
    }

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

    my $events = [];

    if(!$self->legacy_script_support) {
        my $results = $self->run_indb_circ_test;
        unless($self->circ_test_success) {
            push(@$events, $LEGACY_CIRC_EVENT_MAP->{$_->{fail_part}} || $_->{fail_part}) for @$results;
        }

    } else {

        my $runner = $self->script_runner;

        $runner->load($self->circ_permit_renew);
        my $result = $runner->run or 
            throw OpenSRF::EX::ERROR ("Circ Permit Renew Script Died: $@");
        $events = $result->{events};
        $self->mk_script_runner;
    }

    $logger->activity("circulator: circ_permit_renew for user ".
      $self->patron->id." returned events: @$events") if @$events;

    $self->push_events(OpenILS::Event->new($_)) for @$events;

    $logger->debug("circulator: re-creating script runner to be safe");
}


sub append_reading_list {
    my $self = shift;

    return undef unless 
        $self->is_checkout and 
        $self->patron and 
        $self->copy and 
        !$self->is_noncat;

    my $e = new_editor(xact => 1, requestor => $self->editor->requestor);

    # verify history is globally enabled and uses the bucket mechanism
    my $htype = OpenSRF::Utils::SettingsClient->new->config_value(
        apps => 'open-ils.circ' => app_settings => 'checkout_history_mechanism');

    unless($htype eq 'bucket') {
        $e->rollback;
        return undef;
    }

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
    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    $ses->request('open-ils.trigger.event.autocreate', 'checkout', $self->circ, $self->circ_lib) if $self->is_checkout;
    $ses->request('open-ils.trigger.event.autocreate', 'checkin', $self->circ, $self->circ_lib) if $self->is_checkin;
    $ses->request('open-ils.trigger.event.autocreate', 'renewal',  $self->circ, $self->circ_lib) if $self->is_renewal;

    # ignore response
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

1;
