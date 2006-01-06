package OpenILS::Application::Circ::Circulate;
use base 'OpenSRF::Application';
use strict; use warnings;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::ScriptRunner;
use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";

my %scripts;		# - circulation script filenames
my $standings;		# - cached patron standings
my $group_tree;	# - cached permission group tree

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

	$logger->error( "Missing circ script(s)" ) 
		unless( $p and $d and $f and $m and $pr and $ph );

	$scripts{circ_permit}			= $p;
	$scripts{circ_duration}			= $d;
	$scripts{circ_recurring_fines}= $f;
	$scripts{circ_max_fines}		= $m;
	$scripts{circ_renew_permit}	= $pr;
	$scripts{hold_permit}			= $ph;

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

	my $barcode = $params{barcode};
	my $patron	= $params{patron};
	my $summary = $params{fetch_patron_circ_summary};

	my ( $copy, $title, $evt );

	if(!$standings) {
		$standings = $apputils->fetch_patron_standings();
		$group_tree = $apputils->fetch_permission_group_tree();
	}

	( $copy, $evt ) = $apputils->fetch_copy_by_barcode( $barcode );
	return ( undef, $evt ) if $evt;

	( $title, $evt ) = $apputils->fetch_record_by_copy( $copy->id );
	return ( undef, $evt ) if $evt;

	$summary = $apputils->fetch_patron_circ_summary($patron->id) if $summary;

	_doctor_circ_objects( $patron, $title, $copy, $summary );

	my $runner = _build_circ_script_runner( $patron, $title, $copy, $summary );

	return { 
		runner			=> $runner, 
		title				=> $title, 
		patron			=> $patron, 
		copy				=> $copy, 
		standings		=> $standings, 
		group_tree		=> $group_tree,
		circ_summary	=> $summary, 
	};
}


# ------------------------------------------------------------------------------
# Patches up circ objects to make them easier to use from within the script
# environment
# ------------------------------------------------------------------------------
sub _doctor_circ_objects {
	my( $patron, $title, $copy, $summary ) = @_;
	for my $s (@$standings) {
		$patron->standing( $s->value) if( $s->id eq $patron->standing);
	}

	# XXX
	$copy->circulate(0);
}


# ------------------------------------------------------------------------------
# Constructs and shoves data into the script environment
# ------------------------------------------------------------------------------
sub _build_circ_script_runner {
	my( $patron, $title, $copy, $summary ) = @_;

	my $runner = OpenILS::Utils::ScriptRunner->new( type => 'js' );

	$runner->insert( 'patron',		$patron );
	$runner->insert( 'title',		$title );
	$runner->insert( 'copy',		$copy );
	$runner->insert( 'standings', $standings );
	$runner->insert( 'group_tree', $group_tree );

	# circ script result
	$runner->insert( 'result', {} );
	$runner->insert( 'result.event', 'SUCCESS' );

	if($summary) {
		$runner->insert( 'patron_info', {} );
		$runner->insert( 'patron_info.copy_count', $summary->[0] );
		$runner->insert( 'patron_info.fines', $summary->[1] );
	}

	return $runner;
}


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
	( $requestor, $patron, $evt ) = $apputils->checkses_requestor( 
		$authtoken, $patronid, 'VIEW_PERMIT_CHECKOUT' );
	return $evt if $evt;

	# fetch and build the circulation environment
	( $env, $evt ) = create_circ_env( barcode => $barcode, 
		patron => $patron, fetch_patron_circ_summary => 1 );
	return $evt if $evt;

	my $runner = $env->{runner};
	$runner->load($scripts{circ_permit});
	$runner->run or throw OpenSRF::EX::ERROR ("Circ Permit Script Died");

	return OpenILS::Event->new($runner->retrieve('result.event'));
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
