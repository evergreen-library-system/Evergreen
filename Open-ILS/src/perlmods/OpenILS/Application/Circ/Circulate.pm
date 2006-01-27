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

	my $barcode			= $params{barcode};

	my $evt;
	my $ctx = {};

	$ctx->{type}		= $params{type};
	$ctx->{isrenew}	= $params{isrenew};
	$ctx->{noncat}		= $params{noncat};

	$evt = _ctx_add_patron_objects($ctx, %params);
	return $evt if $evt;
	$evt = _ctx_add_copy_objects($ctx, %params) unless $ctx->{noncat};
	return $evt if $evt;

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

	( $ctx->{copy}, $evt ) = $apputils->fetch_copy_by_barcode( $params{barcode} );
	return $evt if $evt;

	( $ctx->{title}, $evt ) = $apputils->fetch_record_by_copy( $ctx->{copy}->id );
	return $evt if $evt;

	return undef;
}



# ------------------------------------------------------------------------------
# Patches up circ objects to make them easier to use from within the script
# environment
# ------------------------------------------------------------------------------
sub _doctor_circ_objects {
	my $ctx = shift;

	my $patron = $ctx->{patron};
	my $copy = $ctx->{copy};
			
	for my $s (@{$ctx->{patron_standings}}) {
		$patron->standing($s) if ( $s->id eq $ctx->{patron}->standing );
	}

	# set the patron ptofile to the profile name
	$patron->profile( _get_patron_profile( $patron, $ctx->{group_tree} ) );

	# flesh the org unit
	$patron->home_ou( $apputils->fetch_org_unit( $patron->home_ou ) );

	# set the copy status to a status name
	$copy->status( _get_copy_status( $copy, $ctx->{copy_statuses} ) ) if $copy;

	# set the copy location to the location object
	$copy->location( _get_copy_location( $copy, $ctx->{copy_locations} ) ) if $copy;

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

	$runner->insert('environment.isRenewal', 1) if $ctx->{isrenew};

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

	# allows a script to fetch a hold that is currently targeting the
	# copy in question
	$runner->insert_method( 'environment.copy', '__OILS_FUNC_fetch_hold', sub {
			my $key = shift;
			my $hold = $holdcode->fetch_open_hold_by_current_copy($ctx->{copy}->id);
			$hold = undef unless $hold;
			$runner->insert( $key, $hold, 1 );
		}
	);
}

# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "permit_circ",
	api_name	=> "open-ils.circ.permit_checkout_",
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

	my $barcode		= $params{barcode};
	my $patronid	= $params{patron};

	my ( $requestor, $patron, $ctx, $evt );

	# check permisson of the requestor
	( $requestor, $patron, $evt ) = 
		$apputils->checkses_requestor( 
		$authtoken, $patronid, 'VIEW_PERMIT_CHECKOUT' );
	return $evt if $evt;

	$logger->info("Checking circulation permission for staff: " . 
		$requestor->id .  ", patron " . $patron->id . 
		", and barcode " . (($barcode) ? $barcode : "") );

	# fetch and build the circulation environment
	( $ctx, $evt ) = create_circ_ctx( 
		barcode							=> $barcode, 
		patron							=> $patron, 
		type								=> 'permit',
		fetch_patron_circ_summary	=> 1,
		fetch_copy_statuses			=> 1, 
		fetch_copy_locations			=> 1, 
		isrenew							=> ($params{renew}) ? 1 : 0,
		noncat							=> $params{noncat},
		);
	return $evt if $evt;

	$ctx->{noncat_type} = $params{noncat_type};
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
	method	=> "circulate",
	api_name	=> "open-ils.circ.checkout.barcode_",
	notes		=> <<"	NOTES");
		Checks out an item based on barcode
		PARAMS( authtoken, barcode => bc, patron => pid )
	NOTES

sub circulate {
	my( $self, $client, $authtoken, %params ) = @_;
	my $barcode		= $params{barcode};
	my $patronid	= $params{patron};
}


# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "checkin",
	api_name	=> "open-ils.circ.checkin.barcode_",
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
