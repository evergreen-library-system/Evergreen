package OpenILS::Application::Circ::Circulate;
use base 'OpenSRF::Application';
use strict; use warnings;
use OpenSRF::EX qw(:try);
use Data::Dumper;
use OpenSRF::Utils;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw(md5_hex);
use OpenILS::Utils::ScriptRunner;
use OpenILS::Application::AppUtils;
use OpenILS::Application::Circ::Holds;
use OpenSRF::Utils::Logger qw(:logger);

$Data::Dumper::Indent = 0;
my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;
my $holdcode = "OpenILS::Application::Circ::Holds";

my %scripts;			# - circulation script filenames
my $script_libs;		# - any additional script libraries
my %cache;				# - db objects cache
my %contexts;			# - Script runner contexts
my $cache_handle;		# - memcache handle

sub PRECAT_FINE_LEVEL { return 2; }
sub PRECAT_LOAN_DURATION { return 2; }

# for security, this is a process-defined and not
# a client-defined variable
my $__isrenewal	= 0;
my $__islost		= 0;

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
	my $ph	= $conf->config_value(	@pfx, 'circ_permit_hold' );
	my $lb	= $conf->config_value(	@pfx2, 'script_path' );

	$logger->error( "Missing circ script(s)" ) 
		unless( $p and $c and $d and $f and $m and $pr and $ph );

	$scripts{circ_permit_patron}	= $p;
	$scripts{circ_permit_copy}		= $c;
	$scripts{circ_duration}			= $d;
	$scripts{circ_recurring_fines}= $f;
	$scripts{circ_max_fines}		= $m;
	$scripts{circ_permit_renew}	= $pr;
	$scripts{hold_permit_permit}	= $ph;

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

	if(!defined($cache{patron_standings})) {
		$cache{patron_standings} = $U->fetch_patron_standings();
		$cache{group_tree} = $U->fetch_permission_group_tree();
	}

	$ctx->{patron_standings} = $cache{patron_standings};
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

	if( $copy ) {
		$logger->debug("Copy status: " . $copy->status);
		( $ctx->{title}, $evt ) = $U->fetch_record_by_copy( $copy->id );
		return $evt if $evt;
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
	if(ref($ctx->{patron_standings})) {
		for my $s (@{$ctx->{patron_standings}}) {
			if( $s->id eq $ctx->{patron}->standing ) {
				$patron->standing($s);
				$logger->debug("Set patron standing to ". $s->value);
			}
		}
	}

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

	$runner->insert('environment.isRenewal', 1) if $__isrenewal;
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

sub permit_circ {
	my( $self, $client, $authtoken, $params ) = @_;
	$U->logmark;

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
			fetch_patron_circ_summary	=> 1,
			fetch_copy_statuses			=> 1, 
			fetch_copy_locations			=> 1, 
			);
		return $evt if $evt;
	}

	($circ, $evt) = $U->fetch_open_circulation($ctx->{copy}->id) 
		if ( !$__isrenewal and $ctx->{copy});

	return OpenILS::Event->new('OPEN_CIRCULATION_EXISTS') if $circ;

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
	$U->logmark;

	$runner->load($scripts{circ_permit_patron});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Permit Patron Script Died: $@");
	my $evtname = $runner->retrieve('result.event');
	$logger->activity("circ_permit_patron for user $patronid returned event: $evtname");

	return OpenILS::Event->new($evtname) if $evtname ne 'SUCCESS';

	my $key = _cache_permit_key();

	if( $ctx->{noncat} ) {
		$logger->debug("Exiting circ permit early because item is a non-cataloged item");
		return OpenILS::Event->new('SUCCESS', payload => $key);
	}

	if($ctx->{precat}) {
		$logger->debug("Exiting circ permit early because copy is pre-cataloged");
		return OpenILS::Event->new('ITEM_NOT_CATALOGED', payload => $key);
	}

	$runner->load($scripts{circ_permit_copy});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Permit Copy Script Died: $@");
	$evtname = $runner->retrieve('result.event');
	$logger->activity("circ_permit_copy for user $patronid ".
		"and copy $barcode returned event: $evtname");

	return OpenILS::Event->new($evtname, payload => $key) if( $evtname eq 'SUCCESS' );
	return OpenILS::Event->new($evtname);
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

	$logger->debug("REQUESTOR event: " . ref($requestor));

	return $evt if $evt;
	( $patron, $evt ) = $U->fetch_user($params->{patron});
	return $evt if $evt;


	# set the circ lib to the home org of the requestor if not specified
	my $circlib = (defined($params->{circ_lib})) ? 
		$params->{circ_lib} : $requestor->home_ou;

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
			fetch_patron_circ_summary	=> 1,
			fetch_copy_statuses			=> 1, 
			fetch_copy_locations			=> 1, 
			);
		return $evt if $evt;
	}
	$ctx->{session} = $U->start_db_session() unless $ctx->{session};

	my $cid = ($params->{precat}) ? -1 : $ctx->{copy}->id;
	return OpenILS::Event->new('CIRC_PERMIT_BAD_KEY') 
		unless _check_permit_key($key);

	$ctx->{circ_lib} = $circlib;

	$evt = _run_checkout_scripts($ctx);
	return $evt if $evt;

	_build_checkout_circ_object($ctx);

	$evt = _commit_checkout_circ_object($ctx);
	return $evt if $evt;

	$evt = _update_checkout_copy($ctx);
	return $evt if $evt;

	$evt = _handle_related_holds($ctx);
	return $evt if $evt;


	$logger->debug("Checkin committing objects with session thread trace: ".$ctx->{session}->session_id);
	$U->commit_db_session($ctx->{session});
	my $record = $U->record_to_mvr($ctx->{title}) unless $ctx->{precat};

	return OpenILS::Event->new('SUCCESS', 
		payload		=> { 
			copy		=> $ctx->{copy},
			circ		=> $ctx->{circ},
			record	=> $record,
		} );
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
	$copy->loan_duration(&PRECAT_LOAN_DURATION);  # these two should come from constants
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

	# if a patron is renewing, 'requestor' will be the patron
	$circ->circ_staff( $ctx->{requestor}->id ); 
	_set_circ_due_date($circ);
	$ctx->{circ} = $circ;
}

sub _create_due_date {
	my $duration = shift;
	$U->logmark;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = 
		gmtime(OpenSRF::Utils->interval_to_seconds($duration) + int(time()));

	$year += 1900; $mon += 1;
	my $due_date = sprintf(
   	'%s-%0.2d-%0.2dT%s:%0.2d:%0.s2-00',
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

	my $s = $U->copy_status_from_name($cache{copy_statuses}, 'checked out');
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

	if(ref($holds) && @$holds) {

		# for now, just sort by id to get what should be the oldest hold
		$holds = [ sort { $a->id <=> $b->id } @$holds ];
		$holds = [ grep { $_->usr eq $patron->id } @$holds ];

		if(@$holds) {
			my $hold = $holds->[0];

			$logger->debug("Related hold found in checkout: " . $hold->id );

			$hold->fulfillment_time('now');
			my $r = $ctx->{session}->request(
				"open-ils.storage.direct.action.hold_request.update", $hold )->gather(1);
			return $U->DB_UPDATE_FAILED( $hold ) unless $r;
		}
	}

	return undef;
}


sub _checkout_noncat {
	my ( $key, $requestor, $patron, %params ) = @_;
	my( $circ, $circlib, $evt );
	$U->logmark;

	$circlib = $params{noncat_circ_lib} || $requestor->home_ou;

	return OpenILS::Event->new('CIRC_PERMIT_BAD_KEY') 
		unless _check_permit_key($key);

	( $circ, $evt ) = OpenILS::Application::Circ::NonCat::create_non_cat_circ(
			$requestor->id, $patron->id, $circlib, $params{noncat_type} );

	return $evt if $evt;
	return OpenILS::Event->new( 
		'SUCCESS', payload => { noncat_circ => $circ } );
}


# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "checkin",
	api_name	=> "open-ils.circ.checkin",
	notes		=> <<"	NOTES");
	PARAMS( authtoken, barcode => bc )
	Checks in based on barcode
	Returns an event object whose payload contains the record, circ, and copy
	If the item needs to be routed, the event is a ROUTE_ITEM event
	with an additional 'route_to' variable set on the event
	NOTES

sub checkin {
	my( $self, $client, $authtoken, $params ) = @_;
	$U->logmark;

	my( $ctx, $requestor, $evt, $patron, $circ, $copy, $obt );

	( $requestor, $evt ) = $U->checkses($authtoken) if $__isrenewal;
	( $requestor, $evt ) = $U->checksesperm( 
		$authtoken, 'COPY_CHECKIN' ) unless $__isrenewal;
	return $evt if $evt;

	( $patron, $evt ) = $U->fetch_user($params->{patron});
	return $evt if $evt;

	if( !( $ctx = $params->{_ctx}) ) {
		( $ctx, $evt ) = create_circ_ctx( %$params, 
			patron							=> $patron, 
			requestor						=> $requestor, 
			session							=> $U->start_db_session(),
			type								=> 'circ',
			fetch_patron_circ_summary	=> 1,
			fetch_copy_statuses			=> 1, 
			fetch_copy_locations			=> 1, 
			no_runner						=> 1, 
			);
		return $evt if $evt;
	}
	$ctx->{session} = $U->start_db_session() unless $ctx->{session};

	$copy = $ctx->{copy};
	return OpenILS::Event->new('COPY_NOT_FOUND') unless $copy;

#	if( $copy->status == 
#		$U->copy_status_from_name($cache{copy_statuses}, 'lost')->id) {
#		$__islost = 1;
#	} else { $__islost = 0; }

	my $status = $U->copy_status_from_name($cache{copy_statuses}, 'in transit');
	if( $copy->status == $status->id ) {
		# if this copy is in transit, send it to transit_receive.  
		$evt = transit_receive( $copy->id, $requestor, $ctx->{session} );
		return $evt unless $U->event_equals($evt, 'SUCCESS');
		$copy = $evt->{payload};
		$evt = undef;
	} 

	$copy->status( $U->copy_status_from_name(
		$cache{copy_statuses}, 'available')->id );


	( $circ, $evt ) = $U->fetch_open_circulation($copy->id);
	return $evt if $evt;
	$ctx->{circ} = $circ;

	return $evt if($evt = _update_checkin_circ_and_copy($ctx));

	$logger->debug("Checkin committing objects with ".
		"session thread trace: ".$ctx->{session}->session_id);
	$U->commit_db_session($ctx->{session});

	return OpenILS::Event->new('ITEM_NOT_CATALOGED') if $copy->call_number == -1;
	return OpenILS::Event->new('SUCCESS');
}


sub _update_checkin_circ_and_copy {
	my $ctx = shift;
	$U->logmark;

	my $circ = $ctx->{circ};
	my $copy = $ctx->{copy};
	my $requestor = $ctx->{requestor};
	my $session = $ctx->{session};

	my ( $obt, $evt ) = $U->fetch_open_billable_transaction($circ->id);
	return $evt if $evt;

	$circ->stop_fines('CHECKIN');
	$circ->stop_fines('RENEW') if $__isrenewal;
	$circ->stop_fines('LOST') if($__islost);
	$circ->xact_finish('now') if($obt->balance_owed <= 0 and !$__islost);
	$circ->stop_fines_time('now');
	$circ->checkin_time('now');
	$circ->checkin_staff($requestor->id);

	# if the requestor set a backdate, void all the bills after 
	# the backdate time
	if(my $backdate = $ctx->{backdate}) {

		$logger->activity("User ".$requestor->id.
			" backdating checkin copy [".$ctx->{barcode}."] to date: $backdate");

		$circ->xact_finish($backdate); 

		my $bills = $session->request( # XXX what other search criteria??
			"open-ils.storage.direct.money.billing.search_where.atomic",
			billing_ts => { ">=" => $backdate })->gather(1);

		if($bills) {
			for my $bill (@$bills) {
				$bill->voided('t');
				my $s = $session->request(
					"open-ils.storage.direct.money.billing.update", $bill)->gather(1);
				return $U->DB_UPDATE_FAILED($bill) unless $s;
			}
		}
	}

	$logger->debug("Checkin committing copy and circ objects");
	$evt = $U->update_copy( session => $session, 
		copy => $copy, editor => $requestor->id );
	return $evt if $evt;

	$ctx->{session}->request(
		'open-ils.storage.direct.action.circulation.update', $circ )->gather(1);

	return undef;
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
	my( $self, $client, $authtoken, $params ) = @_;
	$U->logmark;

	my ( $requestor, $patron, $ctx, $evt, $circ, $copy );
	$__isrenewal = 1;

	# if requesting a renewal for someone else, you must have
	# renew privelages
	( $requestor, $patron, $evt ) = $U->checkses_requestor( 
		$authtoken, $params->{patron}, 'RENEW_CIRC' );
	return $evt if $evt;


	# fetch and build the circulation environment
	( $ctx, $evt ) = create_circ_ctx( %$params, 
		patron							=> $patron, 
		requestor						=> $requestor, 
		type								=> 'circ',
		fetch_patron_circ_summary	=> 1,
		fetch_copy_statuses			=> 1, 
		fetch_copy_locations			=> 1, 
		);
	return $evt if $evt;
	$params->{_ctx} = $ctx;

	# make sure they have some renewals left and make sure the circulation exists
	($circ, $evt) = _check_renewal_remaining($ctx);
	return $evt if $evt;
	$ctx->{old_circ} = $circ;
	my $renewals = $circ->renewal_remaining - 1;

	# run the renew permit script
	return $evt if( ($evt = _run_renew_scripts($ctx)) );

	# checkin the cop
	$ctx->{patron} = $ctx->{patron}->id;
	$evt = $self->checkin($client, $authtoken, $ctx );
		#{ barcode => $params->{barcode}, patron => $params->{patron}} );

	return $evt unless $U->event_equals($evt, 'SUCCESS');

	# re-fetch the context since objects have changed in the checkin
	( $ctx, $evt ) = create_circ_ctx( %$params, 
		patron							=> $patron, 
		requestor						=> $requestor, 
		type								=> 'circ',
		fetch_patron_circ_summary	=> 1,
		fetch_copy_statuses			=> 1, 
		fetch_copy_locations			=> 1, 
		);
	return $evt if $evt;
	$params->{_ctx} = $ctx;
	$ctx->{renewal_remaining} = $renewals;

	# run the circ permit scripts
	$evt = $self->permit_circ( $client, $authtoken, $params );
	if( $U->event_equals($evt, 'ITEM_NOT_CATALOGED')) {
		$ctx->{precat} = 1;
	} else {
		return $evt unless $U->event_equals($evt, 'SUCCESS');
	}
	$params->{permit_key} = $evt->{payload};


	# checkout the item again
	$evt = $self->checkout($client, $authtoken, $params );

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
	my $evtname = $runner->retrieve('result.event');
	$logger->activity("circ_permit_renew for user ".$ctx->{patron}." returned event: $evtname");

	return OpenILS::Event->new($evtname) if $evtname ne 'SUCCESS';
	return undef;
}



sub transit_receive {
	my ( $copyid, $requestor, $session ) = @_;
	$U->logmark;

	my( $copy, $evt ) = $U->fetch_copy($copyid);
	my( $transit, $hold_transit );
	my $cstats = $cache{copy_statuses};

	my $status_name = $U->copy_status_to_name($cstats, $copy->status );
	$logger->debug("Attempting transit receive on copy $copyid. Copy status is $status_name");

	# fetch the transit
	($transit, $evt) = $U->fetch_open_transit_by_copy($copyid);
	return $evt if $evt;

	if( $transit->dest != $requestor->home_ou ) {
		$logger->activity("Fowarding transit on copy which is destined ".
			"for a different location. copy=$copyid,current ".
			"location=".$requestor->home_ou.",destination location=".$transit->dest);

		return OpenILS::Event->new('ROUTE_ITEM', org => $transit->dest );
	}

	# The transit is received, set the receive time
	$transit->dest_recv_time('now');
	my $r = $session->request(
		'open-ils.storage.direct.action.transit_copy.update', $transit )->gather(1);
	return $U->DB_UPDATE_FAILED($transit) unless $r;

	# if this is a hold transit, finalize the hold transit
	return $evt if( ($evt = _finish_hold_transit( 
		$session, $requestor, $copy, $transit->id )) ); 
	
	$U->logmark;

	#recover this copy's status from the transit
	$copy->status( $transit->copy_status );
	return OpenILS::Event->('SUCCESS', payload => $copy);

}

# ------------------------------------------------------------------------------
# If we have a hold transit, set the copy's status to 'on holds shelf',
# update the copy, and return the ROUTE_TO_COPY_LOATION event
# ------------------------------------------------------------------------------
sub _finish_hold_transit {
	my( $session, $requestor, $copy, $transid ) = @_;
	$U->logmark;
	my ($hold_transit, $evt) = $U->fetch_hold_transit( $transid );
	return undef unless $hold_transit;

	my $cstats = $cache{copy_statuses};
	my $s = $U->copy_status_from_name($cstats, 'on holds shelf');
	$logger->info("Hold transit found: ".$hold_transit->id.". Routing to holds shelf");

	$copy->status($s->id);
	$copy->editor($requestor->id);
	$copy->edit_date('now');

	my $r = $session->request( 
		'open-ils.storage.direct.asset.copy.update', $copy )->gather(1);
	return $U->DB_UPDATE_FAILED($copy) unless $r;

	return OpenILS::Event->new('ROUTE_TO_COPY_LOCATION', location => $s->id );
}
	







	


666;

