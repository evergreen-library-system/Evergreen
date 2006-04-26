package OpenILS::Application::Circ::Circulate;
use base 'OpenSRF::Application';
use strict; use warnings;
use OpenSRF::EX qw(:try);
use Data::Dumper;
use OpenSRF::Utils::Cache;
use OpenSRF::AppSession;
use Digest::MD5 qw(md5_hex);
use OpenILS::Utils::ScriptRunner;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Circ::Holds;
use OpenILS::Application::Circ::Transit;
use OpenILS::Utils::PermitHold;
use OpenSRF::Utils::Logger qw(:logger);
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/:datetime/;

$Data::Dumper::Indent = 0;
my $apputils	= "OpenILS::Application::AppUtils";
my $U				= $apputils;
my $holdcode	= "OpenILS::Application::Circ::Holds";
my $transcode	= "OpenILS::Application::Circ::Transit";

my %scripts;			# - circulation script filenames
my $script_libs;		# - any additional script libraries
my %cache;				# - db objects cache
my %contexts;			# - Script runner contexts
my $cache_handle;		# - memcache handle

sub PRECAT_FINE_LEVEL { return 2; }
sub PRECAT_LOAN_DURATION { return 2; }

my %RECORD_FROM_COPY_CACHE;


# for security, this is a process-defined and not
# a client-defined variable
my $__isrenewal	= 0;

# ------------------------------------------------------------------------------
# Load the circ script from the config
# ------------------------------------------------------------------------------
sub initialize {

	my $self = shift;
	$cache_handle = OpenSRF::Utils::Cache->new('global');
	my $conf = OpenSRF::Utils::SettingsClient->new;
	my @pfx2 = ( "apps", "open-ils.circ","app_settings" );
	my @pfx = ( @pfx2, "scripts" );

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

	$logger->debug("Loaded rules scripts for circ: " .
		"circ permit patron: $p, circ permit copy: $c, ".
		"circ duration :$d , circ recurring fines : $f, " .
		"circ max fines : $m, circ renew permit : $pr");
}


# ------------------------------------------------------------------------------
# Loads the necessary circ objects and pushes them into the script environment
# Returns ( $data, $evt ).  if $evt is defined, then an
# unexpedted event occurred and should be dealt with / returned to the caller
# ------------------------------------------------------------------------------
sub create_circ_ctx {
	my %params = @_;
	$U->logmark;

	my $evt;
	my $ctx = \%params;

	$evt = _ctx_add_patron_objects($ctx, %params);
	return (undef,$evt) if $evt;

	if(!$params{noncat}) {
		if( $evt = _ctx_add_copy_objects($ctx, %params) ) {
			$ctx->{precat} = 1 if($evt->{textcode} eq 'COPY_NOT_FOUND')
		} else {
			$ctx->{precat} = 1 if ( $ctx->{copy}->call_number == -1 ); # special case copy
		}
	}

	_doctor_patron_object($ctx) if $ctx->{patron};
	_doctor_copy_object($ctx) if $ctx->{copy};

	if(!$ctx->{no_runner}) {
		_build_circ_script_runner($ctx);
		_add_script_runner_methods($ctx);
	}

	return $ctx;
}

sub _ctx_add_patron_objects {
	my( $ctx, %params) = @_;
	$U->logmark;

	# - patron standings are now handled in the penalty server...

	#if(!defined($cache{patron_standings})) {
	#	$cache{patron_standings} = $U->fetch_patron_standings();
	#}
	#$ctx->{patron_standings} = $cache{patron_standings};

	$cache{group_tree} = $U->fetch_permission_group_tree() unless $cache{group_tree};
	$ctx->{group_tree} = $cache{group_tree};

	$ctx->{patron_circ_summary} = 
		$U->fetch_patron_circ_summary($ctx->{patron}->id) 
		if $params{fetch_patron_circsummary};

	return undef;
}


sub _find_copy_by_attr {
	my %params = @_;
	$U->logmark;
	my $evt;

	my $copy = $params{copy} || undef;

	if(!$copy) {

		( $copy, $evt ) = 
			$U->fetch_copy($params{copyid}) if $params{copyid};
		return (undef,$evt) if $evt;

		if(!$copy) {
			( $copy, $evt ) = 
				$U->fetch_copy_by_barcode( $params{barcode} ) if $params{barcode};
			return (undef,$evt) if $evt;
		}
	}
	return ( $copy, $evt );
}

sub _ctx_add_copy_objects {
	my($ctx, %params)  = @_;
	$U->logmark;
	my $evt;
	my $copy;

	$cache{copy_statuses} = $U->fetch_copy_statuses 
		if( $params{fetch_copy_statuses} and !defined($cache{copy_statuses}) );

	$cache{copy_locations} = $U->fetch_copy_locations 
		if( $params{fetch_copy_locations} and !defined($cache{copy_locations}));

	$ctx->{copy_statuses} = $cache{copy_statuses};
	$ctx->{copy_locations} = $cache{copy_locations};

	($copy, $evt) = _find_copy_by_attr(%params);
	return $evt if $evt;

	if( $copy and !$ctx->{title} ) {
		$logger->debug("Copy status: " . $copy->status);

		my $r = $RECORD_FROM_COPY_CACHE{$copy->id};
		($r, $evt) = $U->fetch_record_by_copy( $copy->id ) unless $r;
		return $evt if $evt;
		$RECORD_FROM_COPY_CACHE{$copy->id} = $r;

		$ctx->{title} = $r;
		$ctx->{copy} = $copy;
	}

	return undef;
}


# ------------------------------------------------------------------------------
# Fleshes parts of the patron object
# ------------------------------------------------------------------------------
sub _doctor_copy_object {
	my $ctx = shift;
	$U->logmark;
	my $copy = $ctx->{copy} || return undef;

	$logger->debug("Doctoring copy object...");

	# set the copy status to a status name
	$copy->status( _get_copy_status( $copy, $ctx->{copy_statuses} ) );

	# set the copy location to the location object
	$copy->location( _get_copy_location( $copy, $ctx->{copy_locations} ) );

	$copy->circ_lib( $U->fetch_org_unit($copy->circ_lib) );
}


# ------------------------------------------------------------------------------
# Fleshes parts of the patron object
# ------------------------------------------------------------------------------
sub _doctor_patron_object {
	my $ctx = shift;
	$U->logmark;
	my $patron = $ctx->{patron} || return undef;

	# push the standing object into the patron
#	if(ref($ctx->{patron_standings})) {
#		for my $s (@{$ctx->{patron_standings}}) {
#			if( $s->id eq $ctx->{patron}->standing ) {
#				$patron->standing($s);
#				$logger->debug("Set patron standing to ". $s->value);
#			}
#		}
#	}

	# set the patron ptofile to the profile name
	$patron->profile( _get_patron_profile( 
		$patron, $ctx->{group_tree} ) ) if $ctx->{group_tree};

	# flesh the org unit
	$patron->home_ou( 
		$U->fetch_org_unit( $patron->home_ou ) ) if $patron;

}

# recurse and find the patron profile name from the tree
# another option would be to grab the groups for the patron
# and cycle through those until the "profile" group has been found
sub _get_patron_profile { 
	my( $patron, $group_tree ) = @_;
	return $group_tree if ($group_tree->id eq $patron->profile);
	return undef unless ($group_tree->children);

	for my $child (@{$group_tree->children}) {
		my $ret = _get_patron_profile( $patron, $child );
		return $ret if $ret;
	}
	return undef;
}

sub _get_copy_status {
	my( $copy, $cstatus ) = @_;
	$U->logmark;
	my $s = undef;
	for my $status (@$cstatus) {
		$s = $status if( $status->id eq $copy->status ) 
	}
	$logger->debug("Retrieving copy status: " . $s->name) if $s;
	return $s;
}

sub _get_copy_location {
	my( $copy, $locations ) = @_;
	$U->logmark;
	my $l = undef;
	for my $loc (@$locations) {
		$l = $loc if $loc->id eq $copy->location;
	}
	$logger->debug("Retrieving copy location: " . $l->name ) if $l;
	return $l;
}


# ------------------------------------------------------------------------------
# Constructs and shoves data into the script environment
# ------------------------------------------------------------------------------
sub _build_circ_script_runner {
	my $ctx = shift;
	$U->logmark;

	$logger->debug("Loading script environment for circulation");

	my $runner;
	if( $runner = $contexts{$ctx->{type}} ) {
		$runner->refresh_context;
	} else {
		$runner = OpenILS::Utils::ScriptRunner->new;
		$contexts{type} = $runner;
	}

	for(@$script_libs) {
		$logger->debug("Loading circ script lib path $_");
		$runner->add_path( $_ );
	}

	# Note: inserting the number 0 into the script turns into the
	# string "0", and thus evaluates to true in JS land
	# inserting undef will insert "", which evaluates to false

	$runner->insert( 'environment.patron',	$ctx->{patron}, 1);
	$runner->insert( 'environment.title',	$ctx->{title}, 1);
	$runner->insert( 'environment.copy',	$ctx->{copy}, 1);

	# circ script result
	$runner->insert( 'result', {} );
	#$runner->insert( 'result.event', 'SUCCESS' );
	$runner->insert( 'result.events', [] );

	if($__isrenewal) {
		$runner->insert('environment.isRenewal', 1);
	} else {
		$runner->insert('environment.isRenewal', undef);
	}

	if($ctx->{ishold} ) { 
		$runner->insert('environment.isHold', 1); 
	} else{ 
		$runner->insert('environment.isHold', undef) 
	}

	if( $ctx->{noncat} ) {
		$runner->insert('environment.isNonCat', 1);
		$runner->insert('environment.nonCatType', $ctx->{noncat_type});
	} else {
		$runner->insert('environment.isNonCat', undef);
	}

#	if(ref($ctx->{patron_circ_summary})) {
#		$runner->insert( 'environment.patronItemsOut', $ctx->{patron_circ_summary}->[0], 1 );
#		$runner->insert( 'environment.patronFines', $ctx->{patron_circ_summary}->[1], 1 );
#	}

	$ctx->{runner} = $runner;
	return $runner;
}


sub _add_script_runner_methods {
	my $ctx = shift;
	$U->logmark;
	my $runner = $ctx->{runner};

	if( $ctx->{copy} ) {
		
		# allows a script to fetch a hold that is currently targeting the
		# copy in question
		$runner->insert_method( 'environment.copy', '__OILS_FUNC_fetch_hold', sub {
				my $key = shift;
				my $hold = $holdcode->fetch_related_holds($ctx->{copy}->id);
				$hold = undef unless $hold;
				$runner->insert( $key, $hold, 1 );
			}
		);
	}
}

# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "permit_circ",
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
	method		=> 'permit_circ',
	api_name		=> 'open-ils.circ.checkout.permit.override',
	signature	=> q/@see open-ils.circ.checkout.permit/,
);

sub permit_circ {
	my( $self, $client, $authtoken, $params ) = @_;
	$U->logmark;

	my $override = $params->{override} = 1 if $self->api_name =~ /override/o;

	my ( $requestor, $patron, $ctx, $evt, $circ );

	# check permisson of the requestor
	( $requestor, $patron, $evt ) = 
		$U->checkses_requestor( 
		$authtoken, $params->{patron}, 'VIEW_PERMIT_CHECKOUT' );
	return $evt if $evt;

	# fetch and build the circulation environment
	if( !( $ctx = $params->{_ctx}) ) {

		( $ctx, $evt ) = create_circ_ctx( %$params, 
			patron							=> $patron, 
			requestor						=> $requestor, 
			type								=> 'circ',
			#fetch_patron_circ_summary	=> 1,
			fetch_copy_statuses			=> 1, 
			fetch_copy_locations			=> 1, 
			);
		return $evt if $evt;
	}

	$ctx->{authtoken} = $authtoken;

	$evt = undef;
	if( $ctx->{copy} and ($evt = _handle_claims_returned($ctx)) ) {
		return $evt unless $U->event_equals($evt, 'SUCCESS');
	}

	if($evt) { 
		$evt = undef;

	} else { 

		# no claims returned circ was found, check if there is any open circ
		if( !$ctx->{ishold} and !$__isrenewal and $ctx->{copy} ) {
			($circ, $evt) = $U->fetch_open_circulation($ctx->{copy}->id);
			return OpenILS::Event->new('OPEN_CIRCULATION_EXISTS') if $circ;
		}
	}


	$ctx->{permit_key} = _cache_permit_key();
	my $events = _run_permit_scripts($ctx);

	if( $override ) {
		$evt = override_events($requestor, $requestor->ws_ou, $events);
		return $evt if $evt;
		return OpenILS::Event->new('SUCCESS', payload => $ctx->{permit_key} );
	}

	return $events;
}

sub override_events {

	my( $requestor, $org, $events ) = @_;
	$events = [ $events ] unless ref($events) eq 'ARRAY';
	my @failed;

	for my $e (@$events) {
		my $tc = $e->{textcode};
		next if $tc eq 'SUCCESS';
		my $ov = "$tc.override";
		$logger->info("attempting to override event $ov");
		my $evt = $U->check_perms( $requestor->id, $org, $ov );
		return $evt if $evt;
	}

	return undef;
}


__PACKAGE__->register_method(
	method	=> "check_title_hold",
	api_name	=> "open-ils.circ.title_hold.is_possible",
	notes		=> q/
		Determines if a hold were to be placed by a given user,
		whether or not said hold would have any potential copies
		to fulfill it.
		@param authtoken The login session key
		@param params A hash of named params including:
			patronid  - the id of the hold recipient
			titleid (brn) - the id of the title to be held
			depth	- the hold range depth (defaults to 0)
	/);

sub check_title_hold {
	my( $self, $client, $authtoken, $params ) = @_;
	my %params = %$params;
	my $titleid = $params{titleid};

	my ( $requestor, $patron, $evt ) = $U->checkses_requestor( 
		$authtoken, $params{patronid}, 'VIEW_HOLD_PERMIT' );
	return $evt if $evt;

	my $rangelib	= $patron->home_ou;
	my $depth		= $params{depth} || 0;

	$logger->debug("Fetching ranged title tree for title $titleid, org $rangelib, depth $depth");

	my $org = $U->simplereq(
		'open-ils.actor', 
		'open-ils.actor.org_unit.retrieve', 
		$authtoken, $requestor->home_ou );

	my $limit	= 10;
	my $offset	= 0;
	my $title;

	while( $title = $U->storagereq(
				'open-ils.storage.biblio.record_entry.ranged_tree', 
				$titleid, $rangelib, $depth, $limit, $offset ) ) {

		last unless ref($title);

		for my $cn (@{$title->call_numbers}) {
	
			$logger->debug("Checking callnumber ".$cn->id." for hold fulfillment possibility");
	
			for my $copy (@{$cn->copies}) {
	
				$logger->debug("Checking copy ".$copy->id." for hold fulfillment possibility");
	
				return 1 if OpenILS::Utils::PermitHold::permit_copy_hold(
					{	patron				=> $patron, 
						requestor			=> $requestor, 
						copy					=> $copy,
						title					=> $title, 
						title_descriptor	=> $title->fixed_fields, # this is fleshed into the title object
						request_lib			=> $org } );
	
				$logger->debug("Copy ".$copy->id." for hold fulfillment possibility failed...");
			}
		}

		$offset += $limit;
	}

	return 0;
}


# Runs the patron and copy permit scripts
# if this is a non-cat circulation, the copy permit script 
# is not run
sub _run_permit_scripts {

	my $ctx			= shift;
	my $runner		= $ctx->{runner};
	my $patronid	= $ctx->{patron}->id;
	my $barcode		= ($ctx->{copy}) ? $ctx->{copy}->barcode : undef;
	my $key			= $ctx->{permit_key};

	my $penalties = $U->update_patron_penalties( 
		authtoken => $ctx->{authtoken}, 
		patron    => $ctx->{patron} 
	);

	$penalties = $penalties->{fatal_penalties};

	$logger->info("circ patron penalties user $patronid: @$penalties");

	if( $ctx->{noncat} ) {
		$logger->debug("Exiting circ permit early because item is a non-cataloged item");
		return OpenILS::Event->new('SUCCESS', payload => $key);
	}

	if($ctx->{precat}) {
		$logger->debug("Exiting circ permit early because copy is pre-cataloged");
		return OpenILS::Event->new('ITEM_NOT_CATALOGED', payload => $key);
	}

	if($ctx->{ishold}) {
		$logger->debug("Exiting circ permit early because request is for hold patron permit");
		return OpenILS::Event->new('SUCCESS');
	}

	$runner->load($scripts{circ_permit_copy});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Permit Copy Script Died: $@");

	# ---------------------------------------------------------------------
	# Capture all of the copy permit events
	# ---------------------------------------------------------------------
	my $copy_events = $runner->retrieve('result.events');
	$copy_events = [ split(/,/, $copy_events) ]; 
	$ctx->{circ_permit_copy_events} = $copy_events;
	$logger->activity("circ_permit_copy for copy ".
		"$barcode returned events: @$copy_events") if @$copy_events;

	my @allevents;
	push( @allevents, OpenILS::Event->new($_)) for @$penalties;
	push( @allevents, OpenILS::Event->new($_)) for @$copy_events;

	my $ae = _check_copy_alert($ctx->{copy});
	push( @allevents, $ae ) if $ae;

	return OpenILS::Event->new('SUCCESS', payload => $key) unless (@allevents);

	# uniquify the events
	my %hash = map { ($_->{ilsevent} => $_) } @allevents;
	@allevents = values %hash;

	for (@allevents) {
		$_->{payload} = $ctx->{copy}->status->id
			if ($_->{textcode} eq 'COPY_NOT_AVAILABLE');
	}

	return \@allevents;
}

sub _check_copy_alert {
	my $copy = shift;
	return OpenILS::Event->new('COPY_ALERT_MESSAGE', 
		payload => $copy->alert_message) if $copy->alert_message;
	return undef;
}

# takes copyid, patronid, and requestor id
sub _cache_permit_key {
	my $key = md5_hex( time() . rand() . "$$" );
	$logger->debug("Setting circ permit key to $key");
	$cache_handle->put_cache( "oils_permit_key_$key", 1, 300 );
	return $key;
}

sub _check_permit_key {
	my $key = shift;
	$logger->debug("Fetching circ permit key $key");
	my $k = "oils_permit_key_$key";
	my $one = $cache_handle->get_cache($k);
	$cache_handle->delete_cache($k);
	return ($one) ? 1 : 0;
}


# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "checkout",
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

sub checkout {
	my( $self, $client, $authtoken, $params ) = @_;
	$U->logmark;

	my ( $requestor, $patron, $ctx, $evt, $circ, $copy );
	my $key = $params->{permit_key};

	# if this is a renewal, then the requestor does not have to
	# have checkout privelages
	( $requestor, $evt ) = $U->checkses($authtoken) if $__isrenewal;
	( $requestor, $evt ) = $U->checksesperm( $authtoken, 'COPY_CHECKOUT' ) unless $__isrenewal;
	return $evt if $evt;

	if( $params->{patron} ) {
		( $patron, $evt ) = $U->fetch_user($params->{patron});
		return $evt if $evt;
	} else {
		( $patron, $evt ) = $U->fetch_user_by_barcode($params->{patron_barcode});
		return $evt if $evt;
	}

	# set the circ lib to the home org of the requestor if not specified
	my $circlib = (defined($params->{circ_lib})) ? 
		$params->{circ_lib} : $requestor->ws_ou;


	# Make sure the caller has a valid permit key or is 
	# overriding the permit can
	if( $params->{permit_override} ) {
		$evt = $U->check_perms(
			$requestor->id, $requestor->ws_ou, 'CIRC_PERMIT_OVERRIDE');
		return $evt if $evt;

	} else {
		return OpenILS::Event->new('CIRC_PERMIT_BAD_KEY') 
			unless _check_permit_key($key);
	}

	# if this is a non-cataloged item, check it out and return
	return _checkout_noncat( 
		$key, $requestor, $patron, %$params ) if $params->{noncat};

	# if this item has yet to be cataloged, make sure a dummy copy exists
	( $params->{copy}, $evt ) = _make_precat_copy(
		$requestor, $circlib, $params ) if $params->{precat};
	return $evt if $evt;


	# fetch and build the circulation environment
	if( !( $ctx = $params->{_ctx}) ) {
		( $ctx, $evt ) = create_circ_ctx( %$params, 
			patron							=> $patron, 
			requestor						=> $requestor, 
			session							=> $U->start_db_session(),
			type								=> 'circ',
			#fetch_patron_circ_summary	=> 1,
			fetch_copy_statuses			=> 1, 
			fetch_copy_locations			=> 1, 
			);
		return $evt if $evt;
	}
	$ctx->{session} = $U->start_db_session() unless $ctx->{session};

	# if the call doesn't know it's not cataloged..
	if(!$params->{precat}) {
		if( $ctx->{copy}->call_number eq '-1' ) {
			return OpenILS::Event->new('ITEM_NOT_CATALOGED');
		}
	}

	# this happens in permit.. but we need to check here for 'offline' requests
	($circ) = $U->fetch_open_circulation($ctx->{copy}->id);
	return OpenILS::Event->new('OPEN_CIRCULATION_EXISTS') if $circ;

	my $cid = ($params->{precat}) ? -1 : $ctx->{copy}->id;


	$ctx->{circ_lib} = $circlib;

	$evt = _run_checkout_scripts($ctx);
	return $evt if $evt;


	_build_checkout_circ_object($ctx);

	$evt = _apply_modified_due_date($ctx);
	return $evt if $evt;

	$evt = _commit_checkout_circ_object($ctx);
	return $evt if $evt;

	$evt = _update_checkout_copy($ctx);
	return $evt if $evt;

	my $holds;
	($holds, $evt) = _handle_related_holds($ctx);
	return $evt if $evt;


	$logger->debug("Checkout committing objects with session thread trace: ".$ctx->{session}->session_id);
	$U->commit_db_session($ctx->{session});
	my $record = $U->record_to_mvr($ctx->{title}) unless $ctx->{precat};

	$logger->activity("user ".$requestor->id." successfully checked out item ".
		$ctx->{copy}->barcode." to user ".$ctx->{patron}->id );


	# ------------------------------------------------------------------------------
	# Update the patron penalty info in the DB
	# ------------------------------------------------------------------------------
	$U->update_patron_penalties( 
		authtoken => $authtoken, 
		patron    => $ctx->{patron} ,
		background	=> 1,
	);

	return OpenILS::Event->new('SUCCESS', 
		payload	=> { 
			copy					=> $U->unflesh_copy($ctx->{copy}),
			circ					=> $ctx->{circ},
			record				=> $record,
			holds_fulfilled	=> $holds,
		} 
	)
}


sub _make_precat_copy {
	my ( $requestor, $circlib, $params ) =  @_;
	$U->logmark;
	my( $copy, undef ) = _find_copy_by_attr(%$params);

	if($copy) {
		$logger->debug("Pre-cat copy already exists in checkout: ID=" . $copy->id);
		return ($copy, undef);
	}

	$logger->debug("Creating a new precataloged copy in checkout with barcode " . $params->{barcode});

	my $evt = OpenILS::Event->new(
		'BAD_PARAMS', desc => "Dummy title or author not provided" ) 
		unless ( $params->{dummy_title} and $params->{dummy_author} );
	return (undef, $evt) if $evt;

	$copy = Fieldmapper::asset::copy->new;
	$copy->circ_lib($circlib);
	$copy->creator($requestor->id);
	$copy->editor($requestor->id);
	$copy->barcode($params->{barcode});
	$copy->call_number(-1); #special CN for precat materials
	$copy->loan_duration(&PRECAT_LOAN_DURATION); 
	$copy->fine_level(&PRECAT_FINE_LEVEL);

	$copy->dummy_title($params->{dummy_title});
	$copy->dummy_author($params->{dummy_author});

	my $id = $U->storagereq(
		'open-ils.storage.direct.asset.copy.create', $copy );
	return (undef, $U->DB_UPDATE_FAILED($copy)) unless $copy;

	$logger->debug("Pre-cataloged copy successfully created");
	return $U->fetch_copy($id);
}


sub _run_checkout_scripts {
	my $ctx = shift;
	$U->logmark;
	my $evt;
	my $circ;

	my $runner = $ctx->{runner};

	$runner->insert('result.durationLevel');
	$runner->insert('result.durationRule');
	$runner->insert('result.recurringFinesRule');
	$runner->insert('result.recurringFinesLevel');
	$runner->insert('result.maxFine');

	$runner->load($scripts{circ_duration});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Duration Script Died: $@");
	my $duration = $runner->retrieve('result.durationRule');
	$logger->debug("Circ duration script yielded a duration rule of: $duration");

	$runner->load($scripts{circ_recurring_fines});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Recurring Fines Script Died: $@");
	my $recurring = $runner->retrieve('result.recurringFinesRule');
	$logger->debug("Circ recurring fines script yielded a rule of: $recurring");

	$runner->load($scripts{circ_max_fines});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Max Fine Script Died: $@");
	my $max_fine = $runner->retrieve('result.maxFine');
	$logger->debug("Circ max_fine fines script yielded a rule of: $max_fine");

	($duration, $evt) = $U->fetch_circ_duration_by_name($duration);
	return $evt if $evt;
	($recurring, $evt) = $U->fetch_recurring_fine_by_name($recurring);
	return $evt if $evt;
	($max_fine, $evt) = $U->fetch_max_fine_by_name($max_fine);
	return $evt if $evt;

	$ctx->{duration_level}			= $runner->retrieve('result.durationLevel');
	$ctx->{recurring_fines_level} = $runner->retrieve('result.recurringFinesLevel');
	$ctx->{duration_rule}			= $duration;
	$ctx->{recurring_fines_rule}	= $recurring;
	$ctx->{max_fine_rule}			= $max_fine;

	return undef;
}

sub _build_checkout_circ_object {
	my $ctx = shift;
	$U->logmark;

	my $circ			= new Fieldmapper::action::circulation;
	my $duration	= $ctx->{duration_rule};
	my $max			= $ctx->{max_fine_rule};
	my $recurring	= $ctx->{recurring_fines_rule};
	my $copy			= $ctx->{copy};
	my $patron 		= $ctx->{patron};
	my $dur_level	= $ctx->{duration_level};
	my $rec_level	= $ctx->{recurring_fines_level};

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
	$circ->circ_lib( $ctx->{circ_lib} );

	if( $__isrenewal ) {
		$logger->debug("Circ is a renewal.  Setting renewal_remaining to " . $ctx->{renewal_remaining} );
		$circ->opac_renewal(1); 
		$circ->renewal_remaining($ctx->{renewal_remaining});
		$circ->circ_staff($ctx->{requestor}->id);
	} 


	# if the user provided an overiding checkout time, 
	# (e.g. the checkout really happened several hours ago), then
	# we apply that here.  Does this need a perm??
	if( my $ds = _create_date_stamp($ctx->{checkout_time}) ) {
		$logger->debug("circ setting checkout_time to $ds");
		$circ->xact_start($ds);
	}

	# if a patron is renewing, 'requestor' will be the patron
	$circ->circ_staff($ctx->{requestor}->id ); 
	_set_circ_due_date($circ);
	$ctx->{circ} = $circ;
}

sub _apply_modified_due_date {
	my $ctx = shift;
	my $circ = $ctx->{circ};

	if( $ctx->{due_date} ) {

		my $evt = $U->check_perms(
			$ctx->{requestor}->id, $ctx->{circ_lib}, 'CIRC_OVERRIDE_DUE_DATE');
		return $evt if $evt;

		my $ds = _create_date_stamp($ctx->{due_date});
		$logger->debug("circ modifying  due_date to $ds");
		$circ->due_date($ds);

	}
	return undef;
}

sub _create_date_stamp {
	my $datestring = shift;
	return undef unless $datestring;
	$datestring = clense_ISO8601($datestring);
	$logger->debug("circ created date stamp => $datestring");
	return $datestring;
}

sub _create_due_date {
	my $duration = shift;
	$U->logmark;
	my ($sec,$min,$hour,$mday,$mon,$year) = 
		gmtime(OpenSRF::Utils->interval_to_seconds($duration) + int(time()));
	$year += 1900; $mon += 1;
	my $due_date = sprintf(
   	'%s-%0.2d-%0.2dT%s:%0.2d:%0.2d-00',
   	$year, $mon, $mday, $hour, $min, $sec);
	return $due_date;
}

sub _set_circ_due_date {
	my $circ = shift;
	$U->logmark;
	my $dd = _create_due_date($circ->duration);
	$logger->debug("Checkout setting due date on circ to: $dd");
	$circ->due_date($dd);
}

# Sets the editor, edit_date, un-fleshes the copy, and updates the copy in the DB
sub _update_checkout_copy {
	my $ctx = shift;
	$U->logmark;
	my $copy = $ctx->{copy};

	my $s = $U->copy_status_from_name('checked out');
	$copy->status( $s->id ) if $s;

	my $evt = $U->update_copy( session => $ctx->{session}, 
		copy => $copy, editor => $ctx->{requestor}->id );
	return (undef,$evt) if $evt;

	return undef;
}

# commits the circ object to the db then fleshes the circ with rules objects
sub _commit_checkout_circ_object {

	my $ctx = shift;
	my $circ = $ctx->{circ};
	$U->logmark;

	$circ->clear_id;
	my $r = $ctx->{session}->request(
		"open-ils.storage.direct.action.circulation.create", $circ )->gather(1);

	return $U->DB_UPDATE_FAILED($circ) unless $r;

	$logger->debug("Created a new circ object in checkout: $r");

	$circ->id($r);
	$circ->duration_rule($ctx->{duration_rule});
	$circ->max_fine_rule($ctx->{max_fine_rule});
	$circ->recuring_fine_rule($ctx->{recurring_fines_rule});

	return undef;
}


# sees if there are any holds that this copy 
sub _handle_related_holds {

	my $ctx		= shift;
	my $copy		= $ctx->{copy};
	my $patron	= $ctx->{patron};
	my $holds	= $holdcode->fetch_related_holds($copy->id);
	$U->logmark;
	my @fulfilled;

	# XXX We should only fulfill one hold here...
	# XXX If a hold was transited to the user who is checking out
	# the item, we need to make sure that hold is what's grabbed
	if(ref($holds) && @$holds) {

		# for now, just sort by id to get what should be the oldest hold
		$holds = [ sort { $a->id <=> $b->id } @$holds ];
		$holds = [ grep { $_->usr eq $patron->id } @$holds ];

		if(@$holds) {
			my $hold = $holds->[0];

			$logger->debug("Related hold found in checkout: " . $hold->id );

			$hold->current_copy($copy->id); # just make sure it's set
			# if the hold was never officially captured, capture it.
			$hold->capture_time('now') unless $hold->capture_time;
			$hold->fulfillment_time('now');
			my $r = $ctx->{session}->request(
				"open-ils.storage.direct.action.hold_request.update", $hold )->gather(1);
			return (undef,$U->DB_UPDATE_FAILED( $hold )) unless $r;
			push( @fulfilled, $hold->id );
		}
	}

	return (\@fulfilled, undef);
}

sub _checkout_noncat {
	my ( $key, $requestor, $patron, %params ) = @_;
	my( $circ, $circlib, $evt );
	$U->logmark;

	$circlib = $params{noncat_circ_lib} || $requestor->ws_ou;

	my $count = $params{noncat_count} || 1;
	my $cotime = _create_date_stamp($params{checkout_time}) || "";
	$logger->info("circ creating $count noncat circs with checkout time $cotime");
	for(1..$count) {
		( $circ, $evt ) = OpenILS::Application::Circ::NonCat::create_non_cat_circ(
			$requestor->id, $patron->id, $circlib, $params{noncat_type}, $cotime );
		return $evt if $evt;
	}

	return OpenILS::Event->new( 
		'SUCCESS', payload => { noncat_circ => $circ } );
}


__PACKAGE__->register_method(
	method	=> "generic_receive",
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
	method	=> "generic_receive",
	api_name	=> "open-ils.circ.checkin.override",
	signature	=> q/@see open-ils.circ.checkin/
);

sub generic_receive {
	my( $self, $conn, $authtoken, $params ) = @_;
	my( $ctx, $requestor, $evt );

	( $requestor, $evt ) = $U->checkses($authtoken) if $__isrenewal;
	( $requestor, $evt ) = $U->checksesperm( 
		$authtoken, 'COPY_CHECKIN' ) unless $__isrenewal;
	return $evt if $evt;

	# load up the circ objects
	if( !( $ctx = $params->{_ctx}) ) {
		( $ctx, $evt ) = create_circ_ctx( %$params, 
			requestor						=> $requestor, 
			session							=> $U->start_db_session(),
			type								=> 'circ',
			fetch_copy_statuses			=> 1, 
			fetch_copy_locations			=> 1, 
			no_runner						=> 1,  
			);
		return $evt if $evt;
	}
	$ctx->{override} = 1 if $self->api_name =~ /override/o;
	$ctx->{session} = $U->start_db_session() unless $ctx->{session};
	$ctx->{authtoken} = $authtoken;
	my $session = $ctx->{session};

	my $copy = $ctx->{copy};
	$U->unflesh_copy($copy);
	return OpenILS::Event->new('COPY_NOT_FOUND') unless $copy;

	$logger->info("Checkin copy called by user ".
		$requestor->id." for copy ".$copy->id);

	# ------------------------------------------------------------------------------
	# Update the patron penalty info in the DB
	# ------------------------------------------------------------------------------
	$U->update_patron_penalties( 
		authtoken => $authtoken, 
		patron    => $ctx->{patron},
		background => 1
	);

	return $self->checkin_do_receive($conn, $ctx);
}

sub checkin_do_receive {

	my( $self, $connection, $ctx ) = @_;

	my $evt;
	my $copy			= $ctx->{copy};
	my $session		= $ctx->{session};
	my $requestor	= $ctx->{requestor};
	my $change		= 0; # did we actually do anything?
	my $circ;

	my @eventlist;

	# does the copy have an attached alert message?
	my $ae = _check_copy_alert($copy);
	push(@eventlist, $ae) if $ae;

	# is the copy is an a status we can't automatically resolve?
	$evt = _checkin_check_copy_status($ctx);
	push( @eventlist, $evt ) if $evt;


	# - see if the copy has an open circ attached
	($ctx->{circ}, $evt)	= $U->fetch_open_circulation($copy->id);
	return $evt if ($evt and $__isrenewal); # renewals require a circulation
	$evt = undef;
	$circ = $ctx->{circ};

	# if the circ is marked as 'claims returned', add the event to the list
	push( @eventlist, 'CIRC_CLAIMS_RETURNED' ) 
		if ($circ and $circ->stop_fines eq 'CLAIMSRETURNED');

	# override or die
	if(@eventlist) {
		if($ctx->{override}) {
			$evt = override_events($requestor, $requestor->ws_ou, \@eventlist );
			return $evt if $evt;
		} else {
			return \@eventlist;
		}
	}

	($ctx->{transit})	= $U->fetch_open_transit_by_copy($copy->id);

	if( $ctx->{circ} ) {

		# There is an open circ on this item, close it out.
		$change	= 1;
		$evt		= _checkin_handle_circ($ctx);
		return $evt if $evt;

	} elsif( $ctx->{transit} ) {

		# is this item currently in transit?
		$change			= 1;
		$evt				= $transcode->transit_receive( $copy, $requestor, $session );
		my $holdtrans	= $evt->{holdtransit};
		($ctx->{hold})	= $U->fetch_hold($holdtrans->hold) if $holdtrans;

		if( ! $U->event_equals($evt, 'SUCCESS') ) {

			# either an error occurred or a ROUTE_ITEM was generated and the 
			# item must be forwarded on to its destination.
			return _checkin_flesh_event($ctx, $evt);

		} else {

			if($holdtrans) {

				# copy was received as a hold transit.  Copy is at target lib
				# and hold transit is complete.  We're done here...
				$U->commit_db_session($session);
				return _checkin_flesh_event($ctx, $evt);
			}
			$evt = undef;
		}
	}

	# ------------------------------------------------------------------------------
	# Circulations and transits are now closed where necessary.  Now go on to see if
	# this copy can fulfill a hold or needs to be routed to a different location
	# ------------------------------------------------------------------------------


	# If it's a renewal, we're done
	if($__isrenewal) {
		$U->commit_db_session($session);
		return OpenILS::Event->new('SUCCESS');
	}

	# Now, let's see if this copy is needed for a hold
	my ($hold) = $holdcode->find_local_hold( $session, $copy, $requestor ); 

	if($hold) {

		$ctx->{hold}	= $hold;
		$change			= 1;
		
		# Capture the hold with this copy
		return $evt if ($evt = _checkin_capture_hold($ctx));

		if( $hold->pickup_lib == $requestor->ws_ou ) {

			# This hold was captured in the correct location
			$evt = OpenILS::Event->new('SUCCESS');

		} else {

			# Hold needs to be picked up elsewhere.  Build a hold 
			# transit and route the item.
			return $evt if ($evt =_checkin_build_hold_transit($ctx));
			$evt = OpenILS::Event->new('ROUTE_ITEM', org => $hold->pickup_lib);
		}

	} else { # not needed for a hold

		if( $copy->circ_lib == $requestor->ws_ou ) {

			# Copy is in the right place.
			$evt = OpenILS::Event->new('SUCCESS');

			# if the item happens to be a pre-cataloged item, send it
			# to cataloging and return the event
			my( $e, $c, $err ) = _checkin_handle_precat($ctx);
			return $err if $err;
			$change		= 1 if $c;
			$evt			= $e if $e;

		} else {

			# Copy wants to go home. Transit it there.
			return $evt if ( $evt = _checkin_build_generic_copy_transit($ctx) );
			$evt			= OpenILS::Event->new('ROUTE_ITEM', org => $copy->circ_lib);
			$change		= 1;
		}
	}


	# ------------------------------------------------------------------
	# if the copy is not in a state that should persist,
	# set the copy to reshelving if it's not already there
	# ------------------------------------------------------------------
	my ($c, $e) = _reshelve_copy($ctx);
	return $e if $e;
	$change = $c unless $change;

	if(!$change) {

		$evt = OpenILS::Event->new('NO_CHANGE');
		($ctx->{hold}) = $U->fetch_open_hold_by_copy($copy->id) 
			if( $copy->status == $U->copy_status_from_name('on holds shelf')->id );

	} else {

		$U->commit_db_session($session);
	}

	$logger->activity("checkin by user ".$requestor->id." on item ".
		$ctx->{copy}->barcode." completed with event ".$evt->{textcode});

	return _checkin_flesh_event($ctx, $evt);
}

sub _reshelve_copy {

	my $ctx = shift;
	my $copy		= $ctx->{copy};
	my $reqr		= $ctx->{requestor};
	my $session	= $ctx->{session};

	my $stat = ref($copy->status) ? $copy->status->id : $copy->status;

	if($stat != $U->copy_status_from_name('on holds shelf')->id and 
		$stat != $U->copy_status_from_name('available')->id and 
		$stat != $U->copy_status_from_name('cataloging')->id and 
		$stat != $U->copy_status_from_name('in transit')->id and 
		$stat != $U->copy_status_from_name('reshelving')->id ) {

		$copy->status( $U->copy_status_from_name('reshelving')->id );

		my $evt = $U->update_copy( 
			copy		=> $copy,
			editor	=> $reqr->id,
			session	=> $session,
			);

		return( 1, $evt );
	}
	return undef;
}




# returns undef if there are no 'open' claims-returned circs attached
# to the given copy.  if there is an open claims-returned circ, 
# then we check for override mode.  if in override, mark the claims-returned
# circ as checked in.  if not, return event.
sub _handle_claims_returned {
	my $ctx	= shift;
	my $copy = $ctx->{copy};

	my $CR	= _fetch_open_claims_returned($copy->id);
	return undef unless $CR;

	# - If the caller has set the override flag, we will check the item in
	if($ctx->{override}) {

		$CR->checkin_time('now');	
		$CR->checkin_lib($ctx->{requestor}->ws_ou);
		$CR->checkin_staff($ctx->{requestor}->id);

		my $stat = $U->storagereq(
			'open-ils.storage.direct.action.circulation.update', $CR);
		return $U->DB_UPDATE_FAILED($CR) unless $stat;
		return OpenILS::Event->new('SUCCESS');

	} else {
		# - if not in override mode, return the CR event
		return OpenILS::Event->new('CIRC_CLAIMS_RETURNED');
	}
}


sub _fetch_open_claims_returned {
	my $copyid = shift;
	my $trans = $U->storagereq(
		'open-ils.storage.direct.action.circulation.search_where',
		{	
			target_copy		=> $copyid, 
			stop_fines		=> 'CLAIMSRETURNED',
			checkin_time	=> undef,
		}
	);
	return $$trans[0] if $trans && $$trans[0];
	return undef;
}

# - if the copy is has the 'in process' status, set it to reshelving
#sub _check_in_process {
	#my $ctx = shift;
#
	#my $copy = $ctx->{copy};
	#my $reqr	= $ctx->{requestor};
	#my $ses	= $ctx->{session};
##
	#my $stat = $U->copy_status_from_name('in process');
	#my $rstat = $U->copy_status_from_name('reshelving');
#
	#if( $stat->id == $copy->status->id ) {
		#$logger->info("marking 'in-process' copy ".$copy->id." as 'reshelving'");
		#$copy->status( $rstat->id );
		#my $evt = $U->update_copy( 
			#copy		=> $copy,
			#editor	=> $reqr->id,
			#session	=> $ses
			#);
		#return $evt if $evt;
#
		#$copy->status( $rstat ); # - reflesh the copy status
	#}
	#return undef;
#}


# returns (ITEM_NOT_CATALOGED, change_occurred, $error_event) where necessary
sub _checkin_handle_precat {

	my $ctx		= shift;
	my $copy		= $ctx->{copy};
	my $evt		= undef;
	my $errevt	= undef;
	my $change	= 0;

	my $catstat = $U->copy_status_from_name('cataloging');

	if( $ctx->{precat} ) {

		$evt = OpenILS::Event->new('ITEM_NOT_CATALOGED');

		if( $copy->status != $catstat->id ) {
			$copy->status($catstat->id);

			return (undef, 0, $errevt) if (
				$errevt = $U->update_copy(
					copy		=> $copy, 
					editor	=> $ctx->{requestor}->id, 
					session	=> $ctx->{session} ));
			$change = 1;

		}
	}

	return ($evt, $change, undef);
}


# returns the appropriate event for the given copy status
# if the copy is not in a 'special' status, undef is returned
sub _checkin_check_copy_status {
	my $ctx	= shift;
	my $copy = $ctx->{copy};
	my $reqr	= $ctx->{requestor};
	my $ses	= $ctx->{session};

	my $islost		= 0;
	my $ismissing	= 0;
	my $evt			= undef;

	my $status = ref($copy->status) ? $copy->status->id : $copy->status;

	return undef 
		if(	$status == $U->copy_status_from_name('available')->id		||
				$status == $U->copy_status_from_name('checked out')->id	||
				$status == $U->copy_status_from_name('in transit')->id	||
				$status == $U->copy_status_from_name('reshelving')->id );

	return OpenILS::Event->new('COPY_STATUS_LOST', payload => $copy ) 
		if( $status == $U->copy_status_from_name('lost')->id );

	return OpenILS::Event->new('COPY_STATUS_MISSING', payload => $copy ) 
		if( $status == $U->copy_status_from_name('missing')->id );

	return OpenILS::Event->new('COPY_BAD_STATUS', payload => $copy );



#	my $rstat = $U->copy_status_from_name('reshelving');
#	my $stat = (ref($copy->status)) ? $copy->status->id : $copy->status;
#
#	if( $stat == $U->copy_status_from_name('lost')->id ) {
#		$islost = 1;
#		$evt = OpenILS::Event->new('COPY_STATUS_LOST', payload => $copy );
#
#	} elsif( $stat == $U->copy_status_from_name('missing')->id) {
#		$ismissing = 1;
#		$evt = OpenILS::Event->new('COPY_STATUS_MISSING', payload => $copy );
#	}
#
#	return (undef,$evt) if(!$ctx->{override});
#
#	# we're are now going to attempt to override the failure 
#	# and set the copy to reshelving
#	my $e;
#	my $copyid = $copy->id;
#	my $userid = $reqr->id;
#	if( $islost ) {
#
#		# - make sure we have permission
#		$e = $U->check_perms( $reqr->id, 
#			$copy->circ_lib, 'COPY_STATUS_LOST.override');
#		return (undef,$e) if $e;
#		$copy->status( $rstat->id );
#
#		# XXX if no fines are owed in the circ, close it out - will this happen later anyway?
#		#my $circ = $U->storagereq(
#		#	'open-ils.storage.direct.action.circulation
#
#		$logger->activity("user $userid overriding 'lost' copy status for copy $copyid");
#
#	} elsif( $ismissing ) {
#
#		# - make sure we have permission
#		$e = $U->check_perms( $reqr->id, 
#			$copy->circ_lib, 'COPY_STATUS_MISSING.override');
#		return (undef,$e) if $e;
#		$copy->status( $rstat->id );
#		$logger->activity("user $userid overriding 'missing' copy status for copy $copyid");
#	}
#
#	if( $islost or $ismissing ) {
#
#		# - update the copy with the new status
#		$evt = $U->update_copy(
#			copy		=> $copy,
#			editor	=> $reqr->id,
#			session	=> $ses
#		);
#		return (undef,$evt) if $evt;
#		$copy->status( $rstat );
#	}
#
#	return (1);


}

# Just gets the copy back home.  Returns undef on success, event on error
sub _checkin_build_generic_copy_transit {

	my $ctx			= shift;
	my $requestor	= $ctx->{requestor};
	my $copy			= $ctx->{copy};
	my $transit		= Fieldmapper::action::transit_copy->new;
	my $session		= $ctx->{session};

	$logger->activity("User ". $requestor->id ." creating a ".
		" new copy transit for copy ".$copy->id." to org ".$copy->circ_lib);

	$transit->source($requestor->ws_ou);
	$transit->dest($copy->circ_lib);
	$transit->target_copy($copy->id);
	$transit->source_send_time('now');
	$transit->copy_status($copy->status);
	
	$logger->debug("Creating new copy_transit in DB");

	my $s = $session->request(
		"open-ils.storage.direct.action.transit_copy.create", $transit )->gather(1);
	return $U->DB_UPDATE_FAILED($transit) unless $s;

	$logger->info("Checkin copy successfully created new transit: $s");

	$copy->status($U->copy_status_from_name('in transit')->id );

	return $U->update_copy( copy => $copy, 
			editor => $requestor->id, session => $session );
	
}


# returns event on error, undef on success
sub _checkin_build_hold_transit {
	my $ctx = shift;

	my $copy = $ctx->{copy};
	my $hold = $ctx->{hold};
	my $trans = Fieldmapper::action::hold_transit_copy->new;

	$trans->hold($hold->id);
	$trans->source($ctx->{requestor}->ws_ou);
	$trans->dest($hold->pickup_lib);
	$trans->source_send_time("now");
	$trans->target_copy($copy->id);
	$trans->copy_status($copy->status);

	my $id = $ctx->{session}->request(
		"open-ils.storage.direct.action.hold_transit_copy.create", $trans )->gather(1);
	return $U->DB_UPDATE_FAILED($trans) unless $id;

	$logger->info("Checkin copy successfully created hold transit: $id");

	$copy->status($U->copy_status_from_name('in transit')->id );
	return $U->update_copy( copy => $copy, 
			editor => $ctx->{requestor}->id, session => $ctx->{session} );
}

# Returns event on error, undef on success
sub _checkin_capture_hold {
	my $ctx = shift;
	my $copy = $ctx->{copy};
	my $hold = $ctx->{hold}; 

	$logger->debug("Checkin copy capturing hold ".$hold->id);

	$hold->current_copy($copy->id);
	$hold->capture_time('now'); 

	my $stat = $ctx->{session}->request(
		"open-ils.storage.direct.action.hold_request.update", $hold)->gather(1);
	return $U->DB_UPDATE_FAILED($hold) unless $stat;

	$copy->status( $U->copy_status_from_name('on holds shelf')->id );

	return $U->update_copy( copy => $copy, 
			editor => $ctx->{requestor}->id, session => $ctx->{session} );
}

# fleshes an event with the relevant objects from the context
sub _checkin_flesh_event {
	my $ctx = shift;
	my $evt = shift;

	my $payload				= {};
	$payload->{copy}		= $U->unflesh_copy($ctx->{copy});
	$payload->{record}	= $U->record_to_mvr($ctx->{title}) if($ctx->{title} and !$ctx->{precat});
	$payload->{circ}		= $ctx->{circ} if $ctx->{circ};
	$payload->{transit}	= $ctx->{transit} if $ctx->{transit};
	$payload->{hold}		= $ctx->{hold} if $ctx->{hold};

	$evt->{payload} = $payload;
	return $evt;
}


# Closes out the circulation, puts the copy into reshelving.
# Voids any bills attached to this circ after the backdate time 
# if a backdate is provided
sub _checkin_handle_circ { 

	my $ctx = shift;

	my $circ = $ctx->{circ};
	my $copy = $ctx->{copy};
	my $requestor	= $ctx->{requestor};
	my $session		= $ctx->{session};
	my $evt;
	my $obt;

	$logger->info("Handling circulation [".$circ->id."] found in checkin...");

	#$ctx->{longoverdue}		= 1 if ($circ->stop_fines =~ /longoverdue/io);
	#$ctx->{claimsreturned}	= 1 if ($circ->stop_fines =~ /claimsreturned/io);

	# backdate the circ if necessary
	if(my $backdate = $ctx->{backdate}) {
		return $evt if ($evt = 
			_checkin_handle_backdate($backdate, $circ, $requestor, $session, 1));
	}


	if(!$circ->stop_fines) {
		$circ->stop_fines('CHECKIN');
		$circ->stop_fines('RENEW') if $__isrenewal;
		$circ->stop_fines_time('now');
	}

	# see if there are any fines owed on this circ.  if not, close it
	( $obt, $evt ) = $U->fetch_open_billable_transaction($circ->id);
	return $evt if $evt;
	$circ->xact_finish('now') if( $obt->balance_owed <= 0 );

	# Set the checkin vars since we have the item
	$circ->checkin_time('now');
	$circ->checkin_staff($requestor->id);
	$circ->checkin_lib($requestor->ws_ou);


#	$copy->status($U->copy_status_from_name('reshelving')->id);
#	$evt = $U->update_copy( session => $session, 
#		copy => $copy, editor => $requestor->id );
#	return $evt if $evt;

	$ctx->{session}->request(
		'open-ils.storage.direct.action.circulation.update', $circ )->gather(1);

	return undef;
}

sub _set_copy_reshelving {
	my( $copy, $reqr, $session ) = @_;

	$logger->info("Setting copy ".$copy->id." to reshelving");
	$copy->status($U->copy_status_from_name('reshelving')->id);

	my $evt = $U->update_copy( 
		session	=> $session, 
		copy		=> $copy, 
		editor	=> $reqr
		);
	return $evt if $evt;
}

# returns event on error, undef on success
# This voids all bills attached to the given circulation that occurred
# after the backdate 
# THIS DOES NOT CLOSE THE CIRC if there are no more fines on the item
sub _checkin_handle_backdate {
	my( $backdate, $circ, $requestor, $session, $closecirc ) = @_;

	$logger->activity("User ".$requestor->id.
		" backdating circ [".$circ->target_copy."] to date: $backdate");

	my $bills = $session->request( # XXX Verify this call is correct
		"open-ils.storage.direct.money.billing.search_where.atomic",
		billing_ts => { ">=" => $backdate }, "xact" => $circ->id )->gather(1);

	if($bills) {
		for my $bill (@$bills) {
			$bill->voided('t');
			my $s = $session->request(
				"open-ils.storage.direct.money.billing.update", $bill)->gather(1);
			return $U->DB_UPDATE_FAILED($bill) unless $s;
		}
	}

	# if the caller elects to attempt to close the circulation
	# transaction, then it will be closed if there are not further
	# charges on the transaction
	#if( $closecirc ) {
		#my ( $obt, $evt ) = $U->fetch_open_billable_transaction($circ->id);
	   #return $evt if $evt;
		#$circ->xact_finish($backdate) if $obt->balance_owed <= 0;
	#}

	return undef;
}


sub _find_patron_from_params {
	my $params = shift;

	my $patron;
	my $copy;
	my $circ;
	my $evt;

	if(my $barcode = $params->{barcode}) {
		$logger->debug("circ finding user from params with barcode $barcode");
		($copy, $evt) = $U->fetch_copy_by_barcode($barcode);
		return (undef, undef, $evt) if $evt;
		($circ, $evt) = $U->fetch_open_circulation($copy->id);
		return (undef, undef, $evt) if $evt;
		($patron, $evt) = $U->fetch_user($circ->usr);
		return (undef, undef, $evt) if $evt;
	}
	return ($patron, $copy);
}


# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "renew",
	api_name	=> "open-ils.circ.renew",
	notes		=> <<"	NOTES");
	PARAMS( authtoken, circ => circ_id );
	open-ils.circ.renew(login_session, circ_object);
	Renews the provided circulation.  login_session is the requestor of the
	renewal and if the logged in user is not the same as circ->usr, then
	the logged in user must have RENEW_CIRC permissions.
	NOTES

sub renew {
	my( $self, $client, $authtoken, $params ) = @_;
	$U->logmark;

	my ( $requestor, $patron, $ctx, $evt, $circ, $copy );
	$__isrenewal = 1;

	# fetch the patron object one way or another
	if( $params->{patron} ) {
		( $patron, $evt ) = $U->fetch_user($params->{patron});
		if($evt) { $__isrenewal = 0; return $evt; }

	} elsif( $params->{patron_barcode} ) {
		( $patron, $evt ) = $U->fetch_user_by_barcode($params->{patron_barcode});
		if($evt) { $__isrenewal = 0; return $evt; }

	} else {
		($patron, $copy, $evt) = _find_patron_from_params($params);
		return $evt if $evt;
		$params->{copy} = $copy;
	}

	# verify our login session
	($requestor, $evt) = $U->checkses($authtoken);
	if($evt) { $__isrenewal = 0; return $evt; }

	# make sure we have permission to perform a renewal
	if( $requestor->id ne $patron->id ) {
		$evt = $U->check_perms($requestor->id, $patron->ws_ou, 'RENEW_CIRC');
		if($evt) { $__isrenewal = 0; return $evt; }
	}


	# fetch and build the circulation environment
	( $ctx, $evt ) = create_circ_ctx( %$params, 
		patron							=> $patron, 
		requestor						=> $requestor, 
		patron							=> $patron, 
		type								=> 'circ',
		#fetch_patron_circ_summary	=> 1,
		fetch_copy_statuses			=> 1, 
		fetch_copy_locations			=> 1, 
		);
	if($evt) { $__isrenewal = 0; return $evt; }
	$params->{_ctx} = $ctx;

	# make sure they have some renewals left and make sure the circulation exists
	($circ, $evt) = _check_renewal_remaining($ctx);
	if($evt) { $__isrenewal = 0; return $evt; }
	$ctx->{old_circ} = $circ;
	my $renewals = $circ->renewal_remaining - 1;

	# run the renew permit script
	$evt = _run_renew_scripts($ctx);
	if($evt) { $__isrenewal = 0; return $evt; }

	# checkin the cop
	#$ctx->{patron} = $ctx->{patron}->id;
	$evt = $self->generic_receive($client, $authtoken, $ctx );
		#{ barcode => $params->{barcode}, patron => $params->{patron}} );

	if( !$U->event_equals($evt, 'SUCCESS') ) {
		$__isrenewal = 0; return $evt; 
	}

	# re-fetch the context since objects have changed in the checkin
	( $ctx, $evt ) = create_circ_ctx( %$params, 
		patron							=> $patron, 
		requestor						=> $requestor, 
		patron							=> $patron, 
		type								=> 'circ',
		#fetch_patron_circ_summary	=> 1,
		fetch_copy_statuses			=> 1, 
		fetch_copy_locations			=> 1, 
		);
	if($evt) { $__isrenewal = 0; return $evt; }
	$params->{_ctx} = $ctx;
	$ctx->{renewal_remaining} = $renewals;

	# run the circ permit scripts
	if( $ctx->{permit_override} ) {
		$evt = $U->check_perms(
			$requestor->id, $ctx->{copy}->circ_lib->id, 'CIRC_PERMIT_OVERRIDE');
		if($evt) { $__isrenewal = 0; return $evt; }

	} else {
		$evt = $self->permit_circ( $client, $authtoken, $params );
		if( $U->event_equals($evt, 'ITEM_NOT_CATALOGED')) {
			#$ctx->{precat} = 1;
			$params->{precat} = 1;

		} else {
			if(!$U->event_equals($evt, 'SUCCESS')) {
				if($evt) { $__isrenewal = 0; return $evt; }
			}
		}
		$params->{permit_key} = $evt->{payload};
	}


	# checkout the item again
	$params->{patron} = $ctx->{patron}->id;
	$evt = $self->checkout($client, $authtoken, $params );

	$logger->activity("user ".$requestor->id." renewl of item ".
		$ctx->{copy}->barcode." completed with event ".$evt->{textcode});

	$__isrenewal = 0;
	return $evt;
}

sub _check_renewal_remaining {
	my $ctx = shift;
	$U->logmark;
	my( $circ, $evt ) = $U->fetch_open_circulation($ctx->{copy}->id);
	return (undef, $evt) if $evt;
	$evt = OpenILS::Event->new(
		'MAX_RENEWALS_REACHED') if $circ->renewal_remaining < 1;
	return ($circ, $evt);
}

sub _run_renew_scripts {
	my $ctx = shift;
	my $runner = $ctx->{runner};
	$U->logmark;

	$runner->load($scripts{circ_permit_renew});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Permit Renew Script Died: $@");

	my $events = $runner->retrieve('result.events');
	$events = [ split(/,/, $events) ]; 
	$logger->activity("circ_permit_renew for user ".
		$ctx->{patron}->id." returned events: @$events") if @$events;

	my @allevents;
	push( @allevents, OpenILS::Event->new($_)) for @$events;
	return \@allevents if  @allevents;

	return undef;
}

	


1;

