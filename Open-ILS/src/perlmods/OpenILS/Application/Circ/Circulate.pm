package OpenILS::Application::Circ::Circulate;
use base 'OpenSRF::Application';
use strict; use warnings;
use OpenSRF::EX qw(:try);
use Data::Dumper;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::ScriptRunner;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Circ::Holds;
$Data::Dumper::Indent = 0;
my $apputils = "OpenILS::Application::AppUtils";
my $holdcode = "OpenILS::Application::Circ::Holds";

my %scripts;			# - circulation script filenames

my $script_libs;		# - any additional script libraries
my %cache;

my %contexts;			# - Script runner contexts

# ------------------------------------------------------------------------------
# Load the circ script from the config
# ------------------------------------------------------------------------------
sub initialize {

	my $self = shift;
	my $conf = OpenSRF::Utils::SettingsClient->new;
	my @pfx2 = ( "apps", "open-ils.circ","app_settings" );
	my @pfx = ( @pfx2, "scripts" );

	my $p		= $conf->config_value(	@pfx, 'circ_permit_patron' );
	my $c		= $conf->config_value(	@pfx, 'circ_permit_copy' );
	my $d		= $conf->config_value(	@pfx, 'circ_duration' );
	my $f		= $conf->config_value(	@pfx, 'circ_recurring_fines' );
	my $m		= $conf->config_value(	@pfx, 'circ_max_fines' );
	my $pr	= $conf->config_value(	@pfx, 'renew_permit' );
	my $ph	= $conf->config_value(	@pfx, 'hold_permit' );
	my $lb	= $conf->config_value(	@pfx2, 'script_path' );

	$logger->error( "Missing circ script(s)" ) 
		unless( $p and $c and $d and $f and $m and $pr and $ph );

	$scripts{circ_permit_patron}	= $p;
	$scripts{circ_permit_copy}		= $c;
	$scripts{circ_duration}			= $d;
	$scripts{circ_recurring_fines}= $f;
	$scripts{circ_max_fines}		= $m;
	$scripts{circ_renew_permit}	= $pr;
	$scripts{hold_permit}			= $ph;

	$lb = [ $lb ] unless ref($lb);
	$script_libs = $lb;

	$logger->debug("Loaded rules scripts for circ: " .
		"circ permit patron: $p, circ permit copy: $c, ".
		"circ duration :$d , circ recurring fines : $f, " .
		"circ max fines : $m, circ renew permit : $pr, permit hold: $ph");
}


# ------------------------------------------------------------------------------
# Loads the necessary circ objects and pushes them into the script environment
# Returns ( $data, $evt ).  if $evt is defined, then an
# unexpedted event occurred and should be dealt with / returned to the caller
# ------------------------------------------------------------------------------
sub create_circ_ctx {
	my %params = @_;

	my $evt;
	my $ctx = {};

	$ctx->{type}			= $params{type};
	$ctx->{renew}			= $params{renew};
	$ctx->{noncat}			= $params{noncat};
	$ctx->{noncat_type}	= $params{noncat_type};

	$evt = _ctx_add_patron_objects($ctx, %params);
	return $evt if $evt;

	if( ($params{copy} or $params{copyid} or $params{barcode}) and !$params{noncat} ) {
		$evt = _ctx_add_copy_objects($ctx, %params);
		return $evt if $evt;
	}

	_doctor_patron_object($ctx) if $ctx->{patron};
	_doctor_copy_object($ctx) if $ctx->{copy};
	_doctor_circ_objects($ctx);
	_build_circ_script_runner($ctx);
	_add_script_runner_methods( $ctx );

	return $ctx;
}

sub _ctx_add_patron_objects {
	my( $ctx, %params) = @_;

	$ctx->{patron}	= $params{patron};

	if(!defined($cache{patron_standings})) {
		$cache{patron_standings} = $apputils->fetch_patron_standings();
		$cache{group_tree} = $apputils->fetch_permission_group_tree();
	}

	$ctx->{patron_standings} = $cache{patron_standings};
	$ctx->{group_tree} = $cache{group_tree};

	$ctx->{patron_circ_summary} = 
		$apputils->fetch_patron_circ_summary($ctx->{patron}->id) 
		if $params{fetch_patron_circsummary};

	return undef;
}


sub _ctx_add_copy_objects {
	my($ctx, %params)  = @_;
	my $evt;

	$cache{copy_statuses} = $apputils->fetch_copy_statuses 
		if( $params{fetch_copy_statuses} and !defined($cache{copy_statuses}) );

	$cache{copy_locations} = $apputils->fetch_copy_locations 
		if( $params{fetch_copy_locations} and !defined($cache{copy_locations}));

	$ctx->{copy_statuses} = $cache{copy_statuses};
	$ctx->{copy_locations} = $cache{copy_locations};

	my $copy = $params{copy} if $params{copy};

	if(!$copy) {

		( $copy, $evt ) = 
			$apputils->fetch_copy($params{copyid}) if $params{copyid};
		return $evt if $evt;

		if(!$copy) {
			( $copy, $evt ) = 
				$apputils->fetch_copy_by_barcode( $params{barcode} ) if $params{barcode};
			return $evt if $evt;
		}
	}

	$ctx->{copy} = $copy;

	( $ctx->{title}, $evt ) = $apputils->fetch_record_by_copy( $ctx->{copy}->id );
	return $evt if $evt;

	return undef;
}


# ------------------------------------------------------------------------------
# Fleshes parts of the patron object
# ------------------------------------------------------------------------------
sub _doctor_copy_object {

	my $ctx = shift;
	my $copy = $ctx->{copy};

	# set the copy status to a status name
	$copy->status( _get_copy_status( 
		$copy, $ctx->{copy_statuses} ) ) if $copy;

	# set the copy location to the location object
	$copy->location( _get_copy_location( 
		$copy, $ctx->{copy_locations} ) ) if $copy;

}


# ------------------------------------------------------------------------------
# Fleshes parts of the copy object
# ------------------------------------------------------------------------------
sub _doctor_patron_object {
	my $ctx = shift;
	my $patron = $ctx->{patron};

	# push the standing object into the patron
	if(ref($ctx->{patron_standings})) {
		for my $s (@{$ctx->{patron_standings}}) {
			$patron->standing($s) if ( $s->id eq $ctx->{patron}->standing );
		}
	}

	# set the patron ptofile to the profile name
	$patron->profile( _get_patron_profile( 
		$patron, $ctx->{group_tree} ) ) if $ctx->{group_tree};

	# flesh the org unit
	$patron->home_ou( 
		$apputils->fetch_org_unit( $patron->home_ou ) ) if $patron;

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
	for my $status (@$cstatus) {
		return $status if( $status->id eq $copy->status ) 
	}
	return undef;
}

sub _get_copy_location {
	my( $copy, $locations ) = @_;
	for my $loc (@$locations) {
		return $loc if $loc->id eq $copy->location;
	}
}


# ------------------------------------------------------------------------------
# Constructs and shoves data into the script environment
# ------------------------------------------------------------------------------
sub _build_circ_script_runner {
	my $ctx = shift;

	$logger->debug("Loading script environment for circulation");

	my $runner;
	if( $runner = $contexts{$ctx->{type}} ) {
		$runner->refresh_context;
	} else {
		$runner = OpenILS::Utils::ScriptRunner->new unless $runner;
		$contexts{type} = $runner;
	}

	for(@$script_libs) {
		$logger->debug("Loading circ script lib path $_");
		$runner->add_path( $_ );
	}

	$runner->insert( 'environment.patron',		$ctx->{patron}, 1);
	$runner->insert( 'environment.title',		$ctx->{title}, 1);
	$runner->insert( 'environment.copy',		$ctx->{copy}, 1);

	# circ script result
	$runner->insert( 'result', {} );
	$runner->insert( 'result.event', 'SUCCESS' );

	$runner->insert('environment.isRenewal', 1) if $ctx->{renew};
	$runner->insert('environment.isNonCat', 1) if $ctx->{noncat};
	$runner->insert('environment.nonCatType', $ctx->{noncat_type}) if $ctx->{noncat};

	if(ref($ctx->{patron_circ_summary})) {
		$runner->insert( 'environment.patronItemsOut', $ctx->{patron_circ_summary}->[0], 1 );
		$runner->insert( 'environment.patronFines', $ctx->{patron_circ_summary}->[1], 1 );
	}

	$ctx->{runner} = $runner;
	return $runner;
}


sub _add_script_runner_methods {
	my $ctx = shift;
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
		@param params A trailing list of named params including 
			barcode : The copy barcode, 
			patron : The patron the checkout is occurring for, 
			renew : true or false - whether or not this is a renewal
		@return The event that occurred during the permit check.  
			If all is well, the SUCCESS event is returned
	/);

sub permit_circ {
	my( $self, $client, $authtoken, %params ) = @_;

	my ( $requestor, $patron, $ctx, $evt );

	# check permisson of the requestor
	( $requestor, $patron, $evt ) = 
		$apputils->checkses_requestor( 
		$authtoken, $params{patron}, 'VIEW_PERMIT_CHECKOUT' );
	return $evt if $evt;

	# fetch and build the circulation environment
	( $ctx, $evt ) = create_circ_ctx( %params, 
		patron							=> $patron, 
		type								=> 'permit',
		fetch_patron_circ_summary	=> 1,
		fetch_copy_statuses			=> 1, 
		fetch_copy_locations			=> 1, 
		);
	return $evt if $evt;

	return _run_permit_scripts($ctx);
}


# Runs the patron and copy permit scripts
# if this is a non-cat circulation, the copy permit script 
# is not run
sub _run_permit_scripts {

	my $ctx			= shift;
	my $runner		= $ctx->{runner};
	my $patronid	= $ctx->{patron}->id;
	my $barcode		= ($ctx->{copy}) ? $ctx->{copy}->barcode : undef;

	$runner->load($scripts{circ_permit_patron});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Permit Patron Script Died: $@");
	my $evtname = $runner->retrieve('result.event');
	$logger->activity("circ_permit_patron for user $patronid returned event: $evtname");

	return OpenILS::Event->new($evtname) 
		if ( $ctx->{noncat} or $evtname ne 'SUCCESS' );

	$runner->load($scripts{circ_permit_copy});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Permit Copy Script Died: $@");
	$evtname = $runner->retrieve('result.event');
	$logger->activity("circ_permit_patron for user $patronid ".
		"and copy $barcode returned event: $evtname");

	return OpenILS::Event->new($evtname);

}


# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "checkout",
	api_name	=> "open-ils.circ.checkout",
	notes => q/
		Checks out an item
		@param authtoken The login session key
		@param params A named list of params including:
			copy			The copy object
			barcode		If no copy is provided, the copy is retrieved via barcode
			copyid		If no copy or barcode is provide, the copy id will be use
			patron		The patron's id
			noncat		True if this is a circulation for a non-cataloted item
			noncat_type	The non-cataloged type id
			noncat_circ_lib The location for the noncat circ.  
				Default is the home org of the staff member
		@return The SUCCESS event on success, any other event depending on the error
	/);

sub checkout {
	my( $self, $client, $authtoken, %params ) = @_;

	my ( $requestor, $patron, $ctx, $evt );

	# check permisson of the requestor
	( $requestor, $patron, $evt ) = 
		$apputils->checkses_requestor( 
			$authtoken, $params{patron}, 'COPY_CHECKOUT' );
	return $evt if $evt;

	return _checkout_noncat( $requestor, $patron, %params ) if $params{noncat};

	# fetch and build the circulation environment
	( $ctx, $evt ) = create_circ_ctx( %params, 
		patron							=> $patron, 
		type								=> 'checkout',
		fetch_patron_circ_summary	=> 1,
		fetch_copy_statuses			=> 1, 
		fetch_copy_locations			=> 1, 
		);
	return $evt if $evt;

	return _run_checkout_scripts( $ctx );
}


sub _run_checkout_scripts {
	my $ctx = shift;

	my $runner = $ctx->{runner};

#	$runner->load($scripts{circ_duration});
#	$runner->run or throw OpenSRF::EX::ERROR ("Circ Duration Script Died: $@");

	return OpenILS::Event->new('SUCCESS', 
		payload => { copy => $ctx->{copy} } );
}



sub _checkout_noncat {
	my ( $requestor, $patron, %params ) = @_;
	my $circlib = $params{noncat_circ_lib} || $requestor->home_ou;
	my( $circ, $evt ) = 
		OpenILS::Application::Circ::NonCat::create_non_cat_circ(
			$requestor->id, $patron->id, $circlib, $params{noncat_type} );
	return $evt if $evt;
	return OpenILS::Event->new('SUCCESS');
}


# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "checkin",
	api_name	=> "open-ils.circ.checkin",
	notes		=> <<"	NOTES");
	PARAMS( authtoken, barcode => bc )
	Checks in based on barcode
	Returns an event object whose payload contains the record, circ, and copy
	If the item needs to be routed, the event is a ROUTE_COPY event
	with an additional 'route_to' variable set on the event
	NOTES

sub checkin {
	my( $self, $client, $authtoken, %params ) = @_;
	my $barcode		= $params{barcode};
}

# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "renew",
	api_name	=> "open-ils.circ.renew_",
	notes		=> <<"	NOTES");
	PARAMS( authtoken, circ => circ_id );
	open-ils.circ.renew(login_session, circ_object);
	Renews the provided circulation.  login_session is the requestor of the
	renewal and if the logged in user is not the same as circ->usr, then
	the logged in user must have RENEW_CIRC permissions.
	NOTES

sub renew {
	my( $self, $client, $authtoken, %params ) = @_;
	my $circ	= $params{circ};
}

	


1;
