package OpenILS::Application::Circ::Circulate;
use strict; use warnings;
use base 'OpenSRF::Application';
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw(:logger);
#use OpenILS::Application::Circ::Circulator;

my %scripts;
my $script_libs;

sub initialize {

	my $self = shift;
	my $conf = OpenSRF::Utils::SettingsClient->new;
	my @pfx2 = ( "apps", "open-ils.circ","app_settings" );
	my @pfx	= ( @pfx2, "scripts" );

	my $p		= $conf->config_value(	@pfx, 'circ_permit_patron' );
	my $c		= $conf->config_value(	@pfx, 'circ_permit_copy' );
	my $d		= $conf->config_value(	@pfx, 'circ_duration' );
	my $f		= $conf->config_value(	@pfx, 'circ_recurring_fines' );
	my $m		= $conf->config_value(	@pfx, 'circ_max_fines' );
	my $pr	= $conf->config_value(	@pfx, 'circ_permit_renew' );
	my $lb	= $conf->config_value(	@pfx2, 'script_path' );

	$logger->error( "Missing circ script(s)" ) 
		unless( $p and $c and $d and $f and $m and $pr );

	$scripts{circ_permit_patron}	= $p;
	$scripts{circ_permit_copy}		= $c;
	$scripts{circ_duration}			= $d;
	$scripts{circ_recurring_fines}= $f;
	$scripts{circ_max_fines}		= $m;
	$scripts{circ_permit_renew}	= $pr;

	$lb = [ $lb ] unless ref($lb);
	$script_libs = $lb;

	$logger->debug(
		"Loaded rules scripts for circ: " .
		"circ permit patron = $p, ".
		"circ permit copy = $c, ".
		"circ duration = $d, ".
		"circ recurring fines = $f, " .
		"circ max fines = $m, ".
		"circ renew permit = $pr.  ".
		"lib paths = @$lb");
}


__PACKAGE__->register_method(
	method	=> "run_method",
	api_name	=> "open-ils.circ.checkout.permit",
	notes		=> q/
		Determines if the given checkout can occur
		@param authtoken The login session key
		@param params A trailing hash of named params including 
			barcode : The copy barcode, 
			patron : The patron the checkout is occurring for, 
			renew : true or false - whether or not this is a renewal
		@return The event that occurred during the permit check.  
	/);


__PACKAGE__->register_method (
	method		=> 'run_method',
	api_name		=> 'open-ils.circ.checkout.permit.override',
	signature	=> q/@see open-ils.circ.checkout.permit/,
);


__PACKAGE__->register_method(
	method	=> "run_method",
	api_name	=> "open-ils.circ.checkout",
	notes => q/
		Checks out an item
		@param authtoken The login session key
		@param params A named hash of params including:
			copy			The copy object
			barcode		If no copy is provided, the copy is retrieved via barcode
			copyid		If no copy or barcode is provide, the copy id will be use
			patron		The patron's id
			noncat		True if this is a circulation for a non-cataloted item
			noncat_type	The non-cataloged type id
			noncat_circ_lib The location for the noncat circ.  
			precat		The item has yet to be cataloged
			dummy_title The temporary title of the pre-cataloded item
			dummy_author The temporary authr of the pre-cataloded item
				Default is the home org of the staff member
		@return The SUCCESS event on success, any other event depending on the error
	/);

__PACKAGE__->register_method(
	method	=> "run_method",
	api_name	=> "open-ils.circ.checkin",
	argc		=> 2,
	signature	=> q/
		Generic super-method for handling all copies
		@param authtoken The login session key
		@param params Hash of named parameters including:
			barcode	- The copy barcode
			force		- If true, copies in bad statuses will be checked in and give good statuses
			...
	/
);

__PACKAGE__->register_method(
	method	=> "run_method",
	api_name	=> "open-ils.circ.checkin.override",
	signature	=> q/@see open-ils.circ.checkin/
);

__PACKAGE__->register_method(
	method	=> "run_method",
	api_name	=> "open-ils.circ.renew.override",
	signature	=> q/@see open-ils.circ.renew/,
);


__PACKAGE__->register_method(
	method	=> "run_method",
	api_name	=> "open-ils.circ.renew",
	notes		=> <<"	NOTES");
	PARAMS( authtoken, circ => circ_id );
	open-ils.circ.renew(login_session, circ_object);
	Renews the provided circulation.  login_session is the requestor of the
	renewal and if the logged in user is not the same as circ->usr, then
	the logged in user must have RENEW_CIRC permissions.
	NOTES


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
	$circulator->mk_script_runner;
	return circ_events($circulator) if $circulator->bail_out;

	$circulator->circ_permit_patron($scripts{circ_permit_patron});
	$circulator->circ_permit_copy($scripts{circ_permit_copy});		
	$circulator->circ_duration($scripts{circ_duration});			 
	$circulator->circ_permit_renew($scripts{circ_permit_renew});
	
	$circulator->override(1) if $api =~ /override/o;

	if( $api =~ /checkout\.permit/ ) {
		$circulator->do_permit();

	} elsif( $api =~ /checkout/ ) {
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
		my @e = @{$circulator->events};
		push( @ee, $_->{textcode} ) for @e;
		$logger->info("circulator: bailing out with events: @ee");
		$circulator->editor->xact_rollback;

	} else {
		$circulator->editor->commit;
	}

	$circulator->script_runner->cleanup;
	
	return circ_events($circulator);
}

sub circ_events {
	my $circ = shift;
	my @e = @{$circ->events};
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
		$$args{is_precat} = $$args{precat};
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

sub PRECAT_FINE_LEVEL { return 2; }
sub PRECAT_LOAN_DURATION { return 2; }
my $U				= "OpenILS::Application::AppUtils";
my $holdcode	= "OpenILS::Application::Circ::Holds";
my $transcode	= "OpenILS::Application::Circ::Transit";

sub DESTROY { }


# --------------------------------------------------------------------------
# Add a pile of automagic getter/setter methods
# --------------------------------------------------------------------------
my @AUTOLOAD_FIELDS = qw/
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
	is_noncat
	is_precat
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
/;


sub AUTOLOAD {
	my $self = shift;
	my $type = ref($self) or die "$self is not an object";
	my $data = shift;
	my $name = $AUTOLOAD;
	$name =~ s/.*://o;   

	unless (grep { $_ eq $name } @AUTOLOAD_FIELDS) {
		$logger->error("$type: invalid autoload field: $name");
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
	$self->editor( 
		new_editor(xact => 1, authtoken => $auth) );

	unless( $self->editor->checkauth ) {
		$self->bail_on_events($self->editor->event);
		return $self;
	}

	$self->cache_handle(OpenSRF::Utils::Cache->new('global'));

	$self->$_($args{$_}) for keys %args;

	$self->circ_lib(
		($self->circ_lib) ? $self->circ_lib : $self->editor->requestor->ws_ou);

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
	my $key	= $self->permit_key;
	return 0 unless $key;
	my $k = "oils_permit_key_$key";
	my $one = $self->cache_handle->get_cache($k);
	$self->cache_handle->delete_cache($k);
	return ($one) ? 1 : 0;
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
	$$args{fetch_patron_by_circ_copy} = 1;
	$$args{fetch_patron_circ_info} = 1;

	# This fetches most of the objects we need
	$self->script_runner(
		OpenILS::Application::Circ::ScriptBuilder->build($args));

	# Now we translate the ScriptBuilder objects back into self
	$self->$_($$args{$_}) for @fields;

	my @evts = @{$args->{_events}} if $args->{_events};

	$logger->debug("script builder returned events: : @evts") if @evts;


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

	$self->is_precat(1) if $self->copy and $self->copy->call_number == -1;

	# Set some circ-specific flags in the script environment
	my $evt = "environment";
	$self->script_runner->insert("$evt.isRenewal", ($self->is_renewal) ? 1 : undef);

	if( $self->is_noncat ) {
      $self->script_runner->insert("$evt.isNonCat", 1);
      $self->script_runner->insert("$evt.nonCatType", $self->noncat_type);
	}

	$self->script_runner->add_path( $_ ) for @$script_libs;

	return 1;
}




# --------------------------------------------------------------------------
# Does the circ permit work
# --------------------------------------------------------------------------
sub do_permit {
	my $self = shift;

	unless( $self->editor->requestor->id == $self->patron->id ) {
		return $self->bail_on_events($self->editor->event)
			unless( $self->editor->allowed('VIEW_PERMIT_CHECKOUT') );
	}

	$self->do_copy_checks();
	return if $self->bail_out;
	$self->run_patron_permit_scripts();
	$self->run_copy_permit_scripts() 
		unless $self->is_precat or $self->is_noncat;
	$self->override_events() unless $self->is_renewal;
	return if $self->bail_out;

	if( $self->is_precat ) {
		$self->push_events(
			OpenILS::Event->new(
				'ITEM_NOT_CATALOGED', payload => $self->mk_permit_key));
		return $self->bail_out(1) unless $self->is_renewal;
	}

	$self->push_events(
      OpenILS::Event->new(
			'SUCCESS', 
			payload => $self->mk_permit_key));
}


sub do_copy_checks {
	my $self = shift;
	my $copy = $self->copy;
	return unless $copy;

	my $stat = (ref $copy->status) ? $copy->status->id : $copy->status;

	# We cannot check out a copy if it is in-transit
	if( $stat == $U->copy_status_from_name('in transit')->id ) {
		return $self->bail_on_events(OpenILS::Event->new('COPY_IN_TRANSIT'));
	}

	$self->handle_claims_returned();
	return if $self->bail_out;

	# no claims returned circ was found, check if there is any open circ
	unless( $self->is_renewal ) {
		my $circs = $self->editor->search_action_circulation(
			{ target_copy => $copy->id, stop_fines_time => undef }
		);

		return $self->bail_on_events(
			OpenILS::Event->new('OPEN_CIRCULATION_EXISTS')) if @$circs;
	}
}


# ---------------------------------------------------------------------
# This pushes any patron-related events into the list but does not
# set bail_out for any events
# ---------------------------------------------------------------------
sub run_patron_permit_scripts {
	my $self 		= shift;
	my $runner		= $self->script_runner;
	my $patronid	= $self->patron->id;

	# ---------------------------------------------------------------------
	# Find all of the fatal penalties currently set on the user
	# ---------------------------------------------------------------------
	my $penalties = $U->update_patron_penalties( 
		authtoken => $self->editor->authtoken,
		patron    => $self->patron,
	);

	$penalties = $penalties->{fatal_penalties};

	# ---------------------------------------------------------------------
	# Now run the patron permit script 
	# ---------------------------------------------------------------------
	$runner->load($self->circ_permit_patron);
	my $result = $runner->run or 
		throw OpenSRF::EX::ERROR ("Circ Permit Patron Script Died: $@");

	my $patron_events = $result->{events};
	my @allevents; 
	push( @allevents, OpenILS::Event->new($_)) for (@$penalties, @$patron_events);

	$logger->info("circulator: permit_patron script returned events: @allevents") if @allevents;

	$self->push_events(@allevents);
}


sub run_copy_permit_scripts {
	my $self = shift;
	my $copy = $self->copy || return;
	my $runner = $self->script_runner;
	
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
	my @allevents;
   push( @allevents, OpenILS::Event->new($_)) for @$copy_events;

	# See if this copy has an alert message
	my $ae = $self->check_copy_alert();
	push( @allevents, $ae ) if $ae;

   # uniquify the events
   my %hash = map { ($_->{ilsevent} => $_) } @allevents;
   @allevents = values %hash;


	# If the script says the copy is not available, put the status
	# in as the payload for that event
	my $stat = ref($copy->status) ? $copy->status->id : $copy->status;
   for (@allevents) {
      $_->{payload} = $stat if 
			($_->{textcode} eq 'COPY_NOT_AVAILABLE');
   }

	$logger->info("circulator: permit_copy script returned events: @allevents") if @allevents;

	$self->push_events(@allevents);
}


sub check_copy_alert {
	my $self = shift;
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
			unless( $self->editor->allowed($ov)	);
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
			target_copy		=> $copy->id,
			stop_fines		=> 'CLAIMSRETURNED',
			checkin_time	=> undef,
		}
	);

	return unless ($CR = $CR->[0]);	

	my $evt;

	# - If the caller has set the override flag, we will check the item in
	if($self->override) {

		$CR->checkin_time('now');	
		$CR->checkin_lib($self->editor->requestor->ws_ou);
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
		$self->script_runner->insert("environment.isPrecat", 1, 1);
		$self->make_precat_copy;
		return if $self->bail_out;

	} elsif( $self->copy->call_number == -1 ) {
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

	$self->copy->status($U->copy_status_from_name('checked out'));
	$self->update_copy;
	return if $self->bail_out;

	$self->handle_checkout_holds();
	return if $self->bail_out;

   # ------------------------------------------------------------------------------
   # Update the patron penalty info in the DB
   # ------------------------------------------------------------------------------
   $U->update_patron_penalties(
      authtoken => $self->editor->authtoken,
      patron    => $self->patron,
      background  => 1,
   );

	my $record = $U->record_to_mvr($self->title) unless $self->is_precat;
	$self->push_events(
		OpenILS::Event->new('SUCCESS',
			payload  => {
				copy              => $U->unflesh_copy($self->copy),
				circ              => $self->circ,
				record            => $record,
				holds_fulfilled   => $self->fulfilled_holds,
			}
		)
	);
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

	return $self->bail_on_events($self->editor->event)
		unless $self->editor->update_asset_copy($self->copy);

	$copy->status($stat) if $stat;
	$copy->location($loc) if $loc;
	$copy->circ_lib($circ_lib) if $circ_lib;
}


sub bail_on_events {
	my( $self, @evts ) = @_;
	$self->push_events(@evts);
	$self->bail_out(1);
}

sub handle_checkout_holds {
   my $self    = shift;

   my $copy    = $self->copy;
   my $patron  = $self->patron;
	my $holds	= $self->editor->search_action_hold_request(
		{ current_copy =>  $copy->id , fulfillment_time => undef });

   my @fulfilled;

   # XXX We should only fulfill one hold here...
   # XXX If a hold was transited to the user who is checking out
   # the item, we need to make sure that hold is what's grabbed
   if(@$holds) {

      # for now, just sort by id to get what should be the oldest hold
      $holds = [ sort { $a->id <=> $b->id } @$holds ];
      my @myholds = grep { $_->usr eq $patron->id } @$holds;
      my @altholds   = grep { $_->usr ne $patron->id } @$holds;

      if(@myholds) {
         my $hold = $myholds[0];

         $logger->debug("Related hold found in checkout: " . $hold->id );

         $hold->current_copy($copy->id); # just make sure it's set
         # if the hold was never officially captured, capture it.
         $hold->capture_time('now') unless $hold->capture_time;
         $hold->fulfillment_time('now');
			return $self->bail_on_events($self->editor->event)
				unless $self->editor->update_action_hold_request($hold);

         push( @fulfilled, $hold->id );
      }

      # If there are any holds placed for other users that point to this copy,
      # then we need to un-target those holds so the targeter can pick a new copy
      for(@altholds) {

         $logger->info("Un-targeting hold ".$_->id.
            " because copy ".$copy->id." is getting checked out");

         $_->clear_current_copy;
			return $self->bail_on_event($self->editor->event)
				unless $self->editor->update_action_hold_request($_);
      }
   }

	$self->fulfilled_holds(\@fulfilled);
}



sub run_checkout_scripts {
	my $self = shift;

	my $evt;
   my $runner = $self->script_runner;
   $runner->load($self->circ_duration);

   my $result = $runner->run or 
		throw OpenSRF::EX::ERROR ("Circ Duration Script Died: $@");

   my $duration   = $result->{durationRule};
   my $dur_level  = $result->{durationLevel};
   my $recurring  = $result->{recurringFinesRule};
   my $max_fine   = $result->{maxFine};
   my $rec_fines_level = $result->{recurringFinesLevel};

   ($duration, $evt) = $U->fetch_circ_duration_by_name($duration);
	return $self->bail_on_events($evt) if $evt;
   ($recurring, $evt) = $U->fetch_recurring_fine_by_name($recurring);
	return $self->bail_on_events($evt) if $evt;
   ($max_fine, $evt) = $U->fetch_max_fine_by_name($max_fine);
	return $self->bail_on_events($evt) if $evt;

   $self->duration_level($dur_level);
   $self->recurring_fines_level($rec_fines_level);
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
   my $dur_level  = $self->duration_level;
   my $rec_level  = $self->recurring_fines_level;

   $circ->duration( $duration->shrt ) if ($dur_level == 1);
   $circ->duration( $duration->normal ) if ($dur_level == 2);
   $circ->duration( $duration->extended ) if ($dur_level == 3);

   $circ->recuring_fine( $recurring->low ) if ($rec_level =~ /low/io);
   $circ->recuring_fine( $recurring->normal ) if ($rec_level =~ /normal/io);
   $circ->recuring_fine( $recurring->high ) if ($rec_level =~ /high/io);

   $circ->duration_rule( $duration->name );
   $circ->recuring_fine_rule( $recurring->name );
   $circ->max_fine_rule( $max->name );
   $circ->max_fine( $max->amount );

   $circ->fine_interval($recurring->recurance_interval);
   $circ->renewal_remaining( $duration->max_renewals );
   $circ->target_copy( $copy->id );
   $circ->usr( $patron->id );
   $circ->circ_lib( $self->circ_lib );

   if( $self->is_renewal ) {
      $circ->opac_renewal(1);
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
	$circ->due_date( $self->create_due_date($circ->duration) );

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
      return unless $copy;

		my $org = (ref $copy->circ_lib) ? $copy->circ_lib->id : $copy->circ_lib;

      $logger->info("circ searching for closed date overlap on lib $org".
			" with an item due date of ".$circ->due_date );

      my $dateinfo = $U->storagereq(
         'open-ils.storage.actor.org_unit.closed_date.overlap', 
			$org, $circ->due_date );

      if($dateinfo) {
         $logger->info("$dateinfo : circ due data / close date overlap found : due_date=".
            $circ->due_date." start=". $dateinfo->{start}.", end=".$dateinfo->{end});

            # XXX make the behavior more dynamic
            # for now, we just push the due date to after the close date
            $circ->due_date($dateinfo->{end});
      }
   }
}



sub create_due_date {
	my( $self, $duration ) = @_;
   my ($sec,$min,$hour,$mday,$mon,$year) =
      gmtime(OpenSRF::Utils->interval_to_seconds($duration) + int(time()));
   $year += 1900; $mon += 1;
   my $due_date = sprintf(
      '%s-%0.2d-%0.2dT%s:%0.2d:%0.2d-00',
      $year, $mon, $mday, $hour, $min, $sec);
   return $due_date;
}



sub make_precat_copy {
	my $self = shift;
	my $copy = $self->copy;

   if($copy) {
      $logger->debug("Pre-cat copy already exists in checkout: ID=" . $copy->id);

      $copy->editor($self->editor->requestor->id);
      $copy->edit_date('now');
      $copy->dummy_title($self->dummy_title);
      $copy->dummy_author($self->dummy_author);

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
   $copy->call_number(-1); #special CN for precat materials
   $copy->loan_duration(&PRECAT_LOAN_DURATION);
   $copy->fine_level(&PRECAT_FINE_LEVEL);

   $copy->dummy_title($self->dummy_title || "");
   $copy->dummy_author($self->dummy_author || "");

	unless( $self->copy($self->editor->create_asset_copy($copy)) ) {
		$self->bail_out(1);
		$self->push_events($self->editor->event);
		return;
	}	

	# this is a little bit of a hack, but we need to 
	# get the copy into the script runner
	$self->script_runner->insert("environment.copy", $copy, 1);
}


sub checkout_noncat {
	my $self = shift;

	my $circ;
	my $evt;

   my $lib 		= $self->noncat_circ_lib || $self->editor->requestor->ws_ou;
   my $count 	= $self->noncat_count || 1;
   my $cotime 	= clense_ISO8601($self->checkout_time) || "";

   $logger->info("circ creating $count noncat circs with checkout time $cotime");

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

	unless( $self->is_renewal ) {
		return $self->bail_on_events($self->editor->event)
			unless $self->editor->allowed('COPY_CHECKIN');
	}

	$self->push_events($self->check_copy_alert());
	$self->push_events($self->check_checkin_copy_status());


	# the renew code will have already found our circulation object
	unless( $self->is_renewal and $self->circ ) {

		# first lets see if we have a good old fashioned open circulation
		my $circ = $self->editor->search_action_circulation(
			{ target_copy => $self->copy->id, stop_fines => undef } )->[0];

		if(!$circ) {
			# if not, lets look for other circs we can check in
			$circ = $self->editor->search_action_circulation(
				{ 
					target_copy => $self->copy->id, 
					xact_finish => undef,
					stop_fines	=> [ 'CLAIMSRETURNED', 'LOST', 'LONGOVERDUE' ]
				} )->[0];
		}

		$self->circ($circ);
	}


	# if the circ is marked as 'claims returned', add the event to the list
	$self->push_events(OpenILS::Event->new('CIRC_CLAIMS_RETURNED'))
		if ($self->circ and $self->circ->stop_fines 
				and $self->circ->stop_fines eq 'CLAIMSRETURNED');

	# handle the overridable events 
	$self->override_events unless $self->is_renewal;
	
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
			return $self->bail_on_events($e);	
		}

		if( $hold_transit ) {
			$self->checkin_flesh_events;
			return;
		} 
	}

	if( $self->is_renewal ) {
		$self->push_events(OpenILS::Event->new('SUCCESS'));
		return;
	}

   # ------------------------------------------------------------------------------
   # Circulations and transits are now closed where necessary.  Now go on to see if
   # this copy can fulfill a hold or needs to be routed to a different location
   # ------------------------------------------------------------------------------

	if( $self->attempt_checkin_hold_capture() ) {
		return if $self->bail_out;

   } else { # not needed for a hold

		my $circ_lib = (ref $self->copy->circ_lib) ? 
				$self->copy->circ_lib->id : $self->copy->circ_lib;

		$logger->debug("circulator: circlib=$circ_lib, workstation=".$self->editor->requestor->ws_ou);

      if( $circ_lib == $self->editor->requestor->ws_ou ) {

			$self->checkin_handle_precat();
			return if $self->bail_out;

      } else {

			$self->checkin_build_copy_transit();
			return if $self->bail_out;
			$self->push_events(OpenILS::Event->new('ROUTE_ITEM', org => $circ_lib));
      }
   }


	$self->reshelve_copy;
	return if $self->bail_out;

	unless($self->checkin_changed) {

		$self->push_events(OpenILS::Event->new('NO_CHANGE'));
		my $stat = (ref $self->copy->status) ? $self->copy->status->id : $self->copy->status;

     	$self->hold($U->fetch_open_hold_by_copy($self->copy->id))
         if( $stat == $U->copy_status_from_name('on holds shelf')->id );
		$self->bail_out(1); # no need to commit anything

	} else {
		$self->push_events(OpenILS::Event->new('SUCCESS')) 
			unless @{$self->events};
	}

	$self->checkin_flesh_events;
	return;
}

sub reshelve_copy {
   my $self    = shift;
   my $copy    = $self->copy;
   my $force   = $self->force;

   my $stat = ref($copy->status) ? $copy->status->id : $copy->status;

   if($force || (
      $stat != $U->copy_status_from_name('on holds shelf')->id and
      $stat != $U->copy_status_from_name('available')->id and
      $stat != $U->copy_status_from_name('cataloging')->id and
      $stat != $U->copy_status_from_name('in transit')->id and
      $stat != $U->copy_status_from_name('reshelving')->id) ) {

      	$copy->status( $U->copy_status_from_name('reshelving') );
			$self->update_copy;
			$self->checkin_changed(1);
	}
}


sub checkin_handle_precat {
	my $self 	= shift;
   my $copy    = $self->copy;
   my $catstat = $U->copy_status_from_name('cataloging');

   if( $self->is_precat and ($copy->status != $catstat->id) ) {
      $copy->status($catstat);
		$self->update_copy();
		$self->checkin_changed(1);
		$self->push_events(OpenILS::Event->new('ITEM_NOT_CATALOGED'));
   }
}


sub checkin_build_copy_transit {
	my $self			= shift;
   my $copy       = $self->copy;
   my $transit    = Fieldmapper::action::transit_copy->new;

   $transit->source($self->editor->requestor->ws_ou);
   $transit->dest( (ref($copy->circ_lib)) ? $copy->circ_lib->id : $copy->circ_lib );
   $transit->target_copy($copy->id);
   $transit->source_send_time('now');
   $transit->copy_status( (ref $copy->status) ? $copy->status->id : $copy->status );

	return $self->bail_on_events($self->editor->event)
		unless $self->editor->create_action_transit_copy($transit);

   $copy->status($U->copy_status_from_name('in transit'));
	$self->update_copy;
	$self->checkin_changed(1);
}


sub attempt_checkin_hold_capture {
	my $self = shift;
	my $copy = $self->copy;

	# See if this copy can fulfill any holds
	my ($hold) = $holdcode->find_nearest_permitted_hold(
		OpenSRF::AppSession->create('open-ils.storage'), 
		$copy, $self->editor->requestor );

	if(!$hold) {
		$logger->debug("circulator: no potential permitted".
			"holds found for copy ".$copy->barcode);
		return undef;
	}

	$logger->info("circulator: found permitted hold ".
		$hold->id . " for copy, capturing...");

	$hold->current_copy($copy->id);
	$hold->capture_time('now');

	# prevent some DB errors
	$hold->clear_fulfillment_time;
	$hold->clear_fulfillment_staff;
	$hold->clear_fulfillment_lib;
	$hold->clear_expire_time; 

	$self->bail_on_events($self->editor->event)
		unless $self->editor->update_action_hold_request($hold);
	$self->hold($hold);
	$self->checkin_changed(1);

	return 1 if $self->bail_out;

	if( $hold->pickup_lib == $self->editor->requestor->ws_ou ) {

		# This hold was captured in the correct location
   	$copy->status( $U->copy_status_from_name('on holds shelf') );
		$self->push_events(OpenILS::Event->new('SUCCESS'));
	
	} else {
	
		# Hold needs to be picked up elsewhere.  Build a hold
		# transit and route the item.
		$self->checkin_build_hold_transit();
   	$copy->status($U->copy_status_from_name('in transit') );
		return 1 if $self->bail_out;
		$self->push_events(
			OpenILS::Event->new('ROUTE_ITEM', org => $hold->pickup_lib));
	}

	# make sure we save the copy status
	$self->update_copy;
	return 1;
}


sub checkin_build_hold_transit {
	my $self = shift;

   my $copy = $self->copy;
   my $hold = $self->hold;
   my $trans = Fieldmapper::action::hold_transit_copy->new;

	my $stat = (ref $copy->status) ? $copy->status->id : $copy->status;
   $trans->hold($hold->id);
   $trans->source($self->editor->requestor->ws_ou);
   $trans->dest($hold->pickup_lib);
   $trans->source_send_time("now");
   $trans->target_copy($copy->id);
   $trans->copy_status($stat);

	return $self->bail_on_events($self->editor->event)
		unless $self->editor->create_action_hold_transit_copy($trans);
}



sub process_received_transit {
	my $self = shift;
	my $copy = $self->copy;
   my $copyid = $self->copy->id;

   my $status_name = $U->copy_status_to_name($copy->status);
   $logger->debug("circulator: attempting transit receive on ".
		"copy $copyid. Copy status is $status_name");

	my $transit = $self->transit;

   if( $transit->dest != $self->editor->requestor->ws_ou ) {
      $logger->activity("Fowarding transit on copy which is destined ".
         "for a different location. copy=$copyid,current ".
         "location=".$self->editor->requestor->ws_ou.",destination location=".$transit->dest);

		$self->bail_on_events(
			OpenILS::Event->new('ROUTE_ITEM', org => $transit->dest ));
   }

   # The transit is received, set the receive time
   $transit->dest_recv_time('now');
	$self->bail_on_events($self->editor->event)
		unless $self->editor->update_action_transit_copy($transit);

	my $hold_transit = $self->editor->search_action_hold_transit_copy(
		{ hold => $transit->id }
	);

   $logger->info("Recovering original copy status in transit: ".$transit->copy_status);
   $copy->status( $transit->copy_status );
	$self->update_copy();
	return if $self->bail_out;

	my $ishold = ($hold_transit) ? 1 : 0;

	$self->push_events( 
		OpenILS::Event->new(
		'SUCCESS', 
		ishold => $ishold,
      payload => { transit => $transit, holdtransit => $hold_transit } ));

	return $hold_transit;
}


sub checkin_handle_circ {
   my $self = shift;
	$U->logmark;

   my $circ = $self->circ;
   my $copy = $self->copy;
   my $evt;
   my $obt;

   # backdate the circ if necessary
   if($self->backdate) {
		$self->handle_backdate;
		return if $self->bail_out;
   }

   if(!$circ->stop_fines) {
      $circ->stop_fines('CHECKIN');
      $circ->stop_fines('RENEW') if $self->is_renewal;
      $circ->stop_fines_time('now');
   }

   # see if there are any fines owed on this circ.  if not, close it
	$obt = $self->editor->retrieve_money_open_billable_transaction_summary($circ->id);
   $circ->xact_finish('now') if( $obt->balance_owed == 0 );

   # Set the checkin vars since we have the item
   $circ->checkin_time('now');
   $circ->checkin_staff($self->editor->requestor->id);
   $circ->checkin_lib($self->editor->requestor->ws_ou);

	$self->copy->status($U->copy_status_from_name('reshelving'));
	$self->update_copy;

	return $self->bail_on_events($self->editor->event)
		unless $self->editor->update_action_circulation($circ);
}


sub checkin_handle_backdate {
	my $self = shift;

	my $bills = $self->editor->search_money_billing(
		{ billing_ts => { ">=" => $self->backdate }, "xact" => $self->circ->id }
	);

	for my $bill (@$bills) {	
		if( !$bill->voided or $bill->voided =~ /f/i ) {
			$bill->voided('t');
			my $n = $bill->note || "";
			$bill->note("$n\nSystem: VOIDED FOR BACKDATE");

			$self->bail_on_events($self->editor->event)
				unless $self->editor->update_money_billing($bill);
		}
	}
}



# XXX Legacy version for Circ.pm support
sub _checkin_handle_backdate {
   my( $backdate, $circ, $requestor, $session, $closecirc ) = @_;

   my $bills = $session->request(
      "open-ils.storage.direct.money.billing.search_where.atomic",
      billing_ts => { ">=" => $backdate }, "xact" => $circ->id )->gather(1);

   if($bills) {
      for my $bill (@$bills) {
         $bill->voided('t');
         my $n = $bill->note || "";
         $bill->note($n . "\nSystem: VOIDED FOR BACKDATE");
         my $s = $session->request(
            "open-ils.storage.direct.money.billing.update", $bill)->gather(1);
         return $U->DB_UPDATE_FAILED($bill) unless $s;
      }
   }
}






sub find_patron_from_copy {
	my $self = shift;
	my $circs = $self->editor->search_action_circulation(
		{ target_copy => $self->copy->id, stop_fines_time => undef });
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

   my $status = ref($copy->status) ? $copy->status->id : $copy->status;

   return undef
      if(   $status == $U->copy_status_from_name('available')->id    ||
            $status == $U->copy_status_from_name('checked out')->id  ||
            $status == $U->copy_status_from_name('in process')->id   ||
            $status == $U->copy_status_from_name('in transit')->id   ||
            $status == $U->copy_status_from_name('reshelving')->id );

   return OpenILS::Event->new('COPY_STATUS_LOST', payload => $copy )
      if( $status == $U->copy_status_from_name('lost')->id );

   return OpenILS::Event->new('COPY_STATUS_MISSING', payload => $copy )
      if( $status == $U->copy_status_from_name('missing')->id );

   return OpenILS::Event->new('COPY_BAD_STATUS', payload => $copy );
}



# --------------------------------------------------------------------------
# On checkin, we need to return as many relevant objects as we can
# --------------------------------------------------------------------------
sub checkin_flesh_events {
	my $self = shift;

	for my $evt (@{$self->events}) {

		my $payload          = {};
		$payload->{copy}     = $U->unflesh_copy($self->copy);
		$payload->{record}   = $U->record_to_mvr($self->title) if($self->title and !$self->is_precat);
		$payload->{circ}     = $self->circ;
		$payload->{transit}  = $self->transit;
		$payload->{hold}     = $self->hold;
		
		$evt->{payload} = $payload;
	}
}


sub do_renew {
	my $self = shift;
	$self->is_renewal(1);

	#$self->find_patron_from_copy unless $self->patron;

	unless( $self->is_renewal ) {
		return $self->bail_on_events($self->editor->events)
			unless $self->editor->allowed('RENEW_CIRC');
	}	

	# Make sure there is an open circ to renew that is not
	# marked as LOST, CLAIMSRETURNED, or LONGOVERDUE
	my $circ = $self->editor->search_action_circulation(
			{ target_copy => $self->copy->id, stop_fines => undef } )->[0];

	return $self->bail_on_events($self->editor->event) unless $circ;

	$self->push_events(OpenILS::Event->new('MAX_RENEWALS_REACHED'))
		if $circ->renewal_remaining < 1;

	# -----------------------------------------------------------------

	$self->renewal_remaining( $circ->renewal_remaining - 1 );
	$self->renewal_remaining(0) if $self->renewal_remaining < 0;
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
   my $runner = $self->script_runner;

   $runner->load($self->circ_permit_renew);
   my $result = $runner->run or 
		throw OpenSRF::EX::ERROR ("Circ Permit Renew Script Died: $@");
   my $events = $result->{events};

   $logger->activity("circ_permit_renew for user ".
      $self->patron->id." returned events: @$events") if @$events;

	$self->push_events(OpenILS::Event->new($_)) for @$events;
}




