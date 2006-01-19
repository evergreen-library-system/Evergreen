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
my $standings;			# - cached patron standings
my $group_tree;		# - cached permission group tree
my $script_libs;		# - any additional script libraries
my $copy_statuses;	# - copy status objects
my $copy_locations;	# - shelving locations

my $cur_copy;
my $cur_patron;
my $cur_title;
my $cur_standings;

my %contexts;			# - Script runner contexts

# ------------------------------------------------------------------------------
# Load the circ script from the config
# ------------------------------------------------------------------------------
sub initialize {

	my $self = shift;
	my $conf = OpenSRF::Utils::SettingsClient->new;
	my @pfx = ( "apps", "open-ils.circ","app_settings", "scripts" );

	my $p		= $conf->config_value(	@pfx, 'permission' );
	my $d		= $conf->config_value(	@pfx, 'duration' );
	my $f		= $conf->config_value(	@pfx, 'recurring_fines' );
	my $m		= $conf->config_value(	@pfx, 'max_fines' );
	my $pr	= $conf->config_value(	@pfx, 'permit_renew' );
	my $ph	= $conf->config_value(	@pfx, 'permit_hold' );
	my $lb	= $conf->config_value(	'apps', 'open-ils.circ', 'app_settings', 'script_path' );

	$logger->error( "Missing circ script(s)" ) 
		unless( $p and $d and $f and $m and $pr and $ph );

	$scripts{circ_permit}			= $p;
	$scripts{circ_duration}			= $d;
	$scripts{circ_recurring_fines}= $f;
	$scripts{circ_max_fines}		= $m;
	$scripts{circ_renew_permit}	= $pr;
	$scripts{hold_permit}			= $ph;

	$lb = [ $lb ] unless ref($lb);
	$script_libs = $lb;

	$logger->debug("Loaded rules scripts for circ: " .
		"circ permit : $p, circ duration :$d , circ recurring fines : $f, " .
		"circ max fines : $m, circ renew permit : $pr, permit hold: $ph");
}


# ------------------------------------------------------------------------------
# Loads the necessary circ objects and pushes them into the script environment
# Returns ( $data, $evt ).  if $evt is defined, then an
# unexpedted event occurred and should be dealt with / returned to the caller
# ------------------------------------------------------------------------------
sub create_circ_env {
	my %params = @_;

	my $barcode			= $params{barcode};
	my $patron			= $params{patron};
	my $fetch_summary = $params{fetch_patron_circ_summary};
	my $fetch_cstatus	= $params{fetch_copy_statuses};
	my $fetch_clocs	= $params{fetch_copy_locations};

	my ( $copy, $title, $evt );

	if(!$cur_standings) {
		$cur_standings = $apputils->fetch_patron_standings();
		$group_tree = $apputils->fetch_permission_group_tree();
	}

	my $cstatus		= $apputils->fetch_copy_statuses if( $fetch_cstatus and !$copy_statuses );
	my $clocs		= $apputils->fetch_copy_locations if( $fetch_clocs and !$copy_locations);
	my $summary		= $apputils->fetch_patron_circ_summary($patron->id) if $fetch_summary;

	( $copy, $evt ) = $apputils->fetch_copy_by_barcode( $barcode );
	return ( undef, $evt ) if $evt;

	( $title, $evt ) = $apputils->fetch_record_by_copy( $copy->id );
	return ( undef, $evt ) if $evt;

	_doctor_circ_objects( $patron, $title, $copy, $summary, $cstatus, $clocs );

	my $runner = _build_circ_script_runner( $patron, $title, $copy, $summary, $params{type} );

	$cur_patron = $patron;
	$cur_copy	= $copy;
	$cur_title	= $title;

	return { 
		runner			=> $runner, 
		title				=> $title, 
		patron			=> $patron, 
		copy				=> $copy, 
		circ_summary	=> $summary, 
	};
}


# ------------------------------------------------------------------------------
# Patches up circ objects to make them easier to use from within the script
# environment
# ------------------------------------------------------------------------------
sub _doctor_circ_objects {
	my( $patron, $title, $copy, $summary, $cstatus, $clocs ) = @_;

	# set the patron standing to the standing name
	for my $s (@$cur_standings) {
		$patron->standing( $s->value ) if( $s->id eq $patron->standing);
	}

	# set the patron ptofile to the profile name
	$patron->profile( _patron_get_profile( $patron, $group_tree ) );

	# set the copy status to a status name
	$copy->status( _get_copy_status_name( $copy, $cstatus ) );

	# set the copy location to the location object
	$copy->location( _get_copy_location( $copy, $clocs ) );

}

# recurse and find the patron profile name from the tree
# another option would be to grab the groups for the patron
# and cycle through those until the "profile" group has been found
sub _patron_get_profile { 
	my( $patron, $group_tree ) = @_;
	return $group_tree->name if ($group_tree->id eq $patron->profile);
	for my $child (@{$group_tree->children}) {
		my $ret = _patron_get_profile( $patron, $child );
		return $ret if $ret;
	}
	return undef;
}

sub _get_copy_status_name {
	my( $copy, $cstatus ) = @_;
	for my $status (@$cstatus) {
		return $status->name if( $status->id eq $copy->status ) 
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
	my( $patron, $title, $copy, $summary, $type ) = @_;

	$logger->debug("Loading script environment for circulation");

	my $runner;
	if( $runner = $contexts{$type} ) {
		$runner->refresh_context;
	} else {
		$runner = OpenILS::Utils::ScriptRunner->new unless $runner;
		$contexts{$type} = $runner;
	}

	for(@$script_libs) {
		$logger->debug("Loading circ script lib path $_");
		$runner->add_path( $_ );
	}

	$runner->insert( 'patron',		$patron );
	$runner->insert( 'title',		$title );
	$runner->insert( 'copy',		$copy );

	# circ script result
	$runner->insert( 'result', {} );
	$runner->insert( 'result.event', 'SUCCESS' );

	if($summary) {
		$runner->insert( 'patron_info', {} );
		$runner->insert( 'patron_info.items_out', $summary->[0] );
		$runner->insert( 'patron_info.fines', $summary->[1] );
	}

	_add_script_runner_methods( $runner );
	return $runner;
}

sub _add_script_runner_methods {
	my $runner = shift;	

	$runner->insert_method( 'copy', '__OILS_FUNC_fetch_hold', sub {
			my $key = shift;
			my $hold = $holdcode->fetch_open_hold_by_current_copy($cur_copy->id);
			$hold = undef unless $hold;
			$runner->insert( $key, $hold );
		}
	);

#	$runner->insert_method( 'patron', '__OILS_FUNC_get_standing', sub {
#			my $key = shift;
#			my $standing = "";
#			for my $s (@$cur_standings) {
#				$standing = $s->value if ( $s->id eq $cur_patron->standing );
#			}
#			$runner->insert( $key, $standing );
#		}
#	);


}

=head blah
sub _insert_event {
	my $runner = shift;
	my $evt = shift;
	$runner->insert('result.event', $evt->{textcode} );
}

sub _add_script_methods {
	my $runner = shift;

	$runner->insert( 'fetch_patron', sub {
			my ( $key, $id ) = @_;	
			my ( $user, $evt ) = $apputils->fetch_user($id);
			_insert_event( $runner, $evt ) if $evt;
			$runner->insert( $key, $user );
		}
	);

	$runner->insert( 'fetch_copy_by_barcode', sub {
			my( $key, $barcode ) = @_;
			my( $copy, $evt ) = $apputils->fetch_copy_by_barcode( $barcode );
			_insert_event( $runner, $evt ) if $evt;
			$runner->insert( $key, $copy );
		}
	);

	$runner->insert( 'fetch_copy_statuses', sub {
		my $key = shift;
		$runner->insert( $key, $apputils->fetch_copy_statuses ); 
	});

	$runner->insert( 'fetch_copy_locations', sub {
		my $key = shift;
		$runner->insert( $key, $apputils->fetch_copy_locations ); });

	$runner->insert( 'fetch_patron_circ_summary', sub {
		my( $key, $patron_id ) = @_;
		$runner->insert( $key, $apputils->fetch_patron_circ_summary($patron_id)); });

	$runner->insert( 'fetch_group_tree', sub { 
		my $key = shift;
		$runner->insert( $key, $apputils->fetch_permission_group_tree ); });

	$runner->insert( 'fetch_patron_standings', sub { 
		my $key = shift;
		$runner->insert( $key, $apputils->fetch_patron_standings ); } );
}


sub _build_script_runner {
	my %params = @_;

	my $runner = OpenILS::Utils::ScriptRunner->new( 
		type => 'js', libs => $script_libs );
	
	# return status event
	$runner->insert( 'result', {} );
	$runner->insert( 'result.event', 'SUCCESS' );

	$runner->insert('env.patron_id', $params{patron_id} ) if defined $params{patron_id};
	$runner->insert('env.copy_barcode', $params{copy_barcode} ) if defined $params{copy_barcode};

	$runner->insert( 'arr', [ 1, 5, 10 ] );


	return $runner;
}

=cut


# ------------------------------------------------------------------------------

__PACKAGE__->register_method(
	method	=> "permit_circ",
	api_name	=> "open-ils.circ.permit_checkout_",
	notes		=> <<"	NOTES");
		Determines if the given checkout can occur
		PARAMS( authtoken, barcode => bc, patron => pid, renew => t/f )
		Returns an event
	NOTES

sub permit_circ {
	my( $self, $client, $authtoken, %params ) = @_;

	my $barcode		= $params{barcode};
	my $patronid	= $params{patron};
	my $isrenew		= $params{renew};
	my ( $requestor, $patron, $env, $evt );


	# check permisson of the requestor
	( $requestor, $patron, $evt ) = 
		$apputils->checkses_requestor( 
		$authtoken, $patronid, 'VIEW_PERMIT_CHECKOUT' );
	return $evt if $evt;

	$logger->info("Checking circulation permission for staff: " . $requestor->id .
		", patron " . $patron->id . ", and barcode $barcode" );

	# fetch and build the circulation environment
	( $env, $evt ) = create_circ_env( 
		barcode							=> $barcode, 
		patron							=> $patron, 
		type								=> 'permit',
		fetch_patron_circ_summary	=> 1,
		fetch_copy_statuses			=> 1, 
		fetch_copy_locations			=> 1, 
		);
	return $evt if $evt;

	# run the script
	my $runner = $env->{runner};

#	my $runner = _build_script_runner( patron_id => $patronid, copy_barcode => $barcode );
#	_add_script_methods( $runner );

	$runner->load($scripts{circ_permit});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Permit Script Died: $@");

	my $evtname = $runner->retrieve('result.event');
	$logger->activity("Permit Circ for user $patronid and barcode $barcode returned event: $evtname");
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
