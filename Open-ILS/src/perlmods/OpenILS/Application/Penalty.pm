package OpenILS::Application::Penalty;
use strict; use warnings;
use DateTime;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Cache;
use OpenSRF::Utils qw/:datetime/;
use OpenILS::Utils::ScriptRunner;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw(:logger);
use base 'OpenSRF::Application';

my $U = "OpenILS::Application::AppUtils";
my $script;
my $path;
my $libs;
my $runner;
my %groups; # - user groups

my $fatal_key = 'result.fatalEvents';
my $info_key = 'result.infoEvents';


# --------------------------------------------------------------
# Loads the config info
# --------------------------------------------------------------
sub initialize {

	my $conf = OpenSRF::Utils::SettingsClient->new;
	my @pfx  = ( "apps", "open-ils.penalty","app_settings" );
	$path		= $conf->config_value( @pfx, 'script_path');
	$script	= $conf->config_value( @pfx, 'patron_penalty' );

	if(!($path and $script)) {
		$logger->error("Penalty server config missing script and/or script path");
		return 0;
	}

	$logger->info("penalty: Loading patron penalty script $script with path $path");
}


# --------------------------------------------------------------
# Builds the script runner and shoves data into the script 
# context
# --------------------------------------------------------------
sub build_runner {

	my %args = @_;
	my $patron = $args{patron};
	my $patron_summary = $args{patron_summary};

	my $pgroup = find_profile($patron);
	$patron->profile( $pgroup );

	if($runner) {
		$runner->refresh_context if $runner;

	} else {
		$runner = OpenILS::Utils::ScriptRunner->new unless $runner;
		$runner->add_path( $_ );
	}

	$runner->insert( 'environment.patron',	$patron, 1);
	$runner->insert( $fatal_key, [] );
	$runner->insert( $info_key, [] );
	$runner->insert( 'environment.patronItemsOut', $patron_summary->[0] );
	$runner->insert( 'environment.patronFines', $patron_summary->[1] );

	return $runner;
}


sub find_profile {
	my $patron = shift;

	if(!%groups) {
		my $groups = $U->storagereq(
			'open-ils.storage.direct.permission.grp_tree.retrieve.all.atomic');
		%groups = map { $_->id => $_ } @$groups;
	}

	return $groups{$patron->profile};
}



__PACKAGE__->register_method (
	method	 => 'patron_penalty',
	api_name	 => 'open-ils.penalty.patron_penalty.calculate',
	signature => q/
		Calculates the patron's standing penalties
		@param authtoken The login session key
		@params args An object of named params including:
			patronid The id of the patron
			update True if this call should update the database
			background True if this call should return immediately,
				then go on to process the penalties.  This flag
				works only in conjunction with the 'update' flag.
		@return An object with keys 'fatal_penalties' and 
		'info_penalties' who are themeselves arrays of 0 or 
		more penalties.  Returns event on error.
	/
);

# --------------------------------------------------------------
# modes: 
#  - update 
#  - background : modifier to 'update' which says to return 
#		immediately then continue processing.  If this flag is set
#		then the caller will get no penalty info and will never 
#		know for sure if the call even succeeded. 
# --------------------------------------------------------------
sub patron_penalty {
	my( $self, $conn, $authtoken, $args ) = @_;
	
	my( $requestor, $patron, $evt );

	$conn->respond_complete(1) if $$args{background};

	$patron = $$args{patron};

	if(!$patron) {
		( $patron, $evt ) = $U->fetch_user($$args{patronid});
		return $evt if $evt;
	}

	( $requestor, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;

	$evt = $U->check_perms( $requestor->id,  $patron->home_ou, 'VIEW_USER');
	return $evt if $evt;

	# - fetch the circulation summary info for the user
	my $summary = $U->fetch_patron_circ_summary($patron->id);

	# - build the script runner
	my $runner = build_runner( 
		patron			=> $patron, 
		patron_summary => $summary 
		);

	# - Load up the script and run it
	$runner->add_path($path);
	$runner->load($script);
	$runner->run or throw OpenSRF::EX::ERROR ("Patron Penalty Script Died: $@");

	# array items are returned as a comma-separated list of strings
	my @fatals = split( /,/, $runner->retrieve($fatal_key) );
	my @infos = split( /,/, $runner->retrieve($info_key) );
	my $all = [ @fatals, @infos ];

	$logger->info("penalty: script returned fatal events [@fatals] and info events [@infos]");

	$conn->respond_complete(
		{ fatal_penalties => \@fatals, info_penalties => \@infos });

	# - update the penalty info in the db if necessary
	$evt = update_patron_penalties( 
		patron    => $patron, 
		penalties => $all, 
		requestor => $requestor ) if $$args{update};

	# - The caller won't know it failed, so log it
	$logger->error("penalty: Error updating the patron ".
		"penalties in the database: ".Dumper($evt)) if $evt;

	return undef;
}

# --------------------------------------------------------------
# Removes existing penalties for the patron that are not passed 
# into this function.  Creates new penalty entries for the 
# provided penalties that don't already exist;
# --------------------------------------------------------------
sub update_patron_penalties {

	my %args      = @_;
	my $patron    = $args{patron};
	my $penalties = $args{penalties};
	my $requestor = $args{requestor};

	my $session   = $U->start_db_session();

	# - fetch the current penalties
	my $existing = $session->request(
		'open-ils.storage.direct.actor.'.
		'user_standing_penalty.search.usr.atomic', $patron->id )->gather(1);

	my @deleted;
	my $reqid = $requestor->id;
	my $patronid = $patron->id;

	# If an existing penalty is not in the newly generated 
	# list of penalties, remove it from the DB
	for my $e (@$existing) {
		if( ! grep { $_ eq $e->penalty_type } @$penalties ) {

			$logger->activity("user $reqid removing user penalty ".
				$e->penalty_type . " from user $patronid");

			my $s = $session->request(
				'open-ils.storage.direct.actor.user_standing_penalty.delete', $e->id )->gather(1);
			return $U->DB_UPDATE_FAILED($e) unless defined($s);
		}
	}

	# Add penalties that previously didn't exist
	for my $p (@$penalties) {
		if( ! grep { $_->penalty_type eq $p } @$existing ) {

			$logger->activity("user $reqid adding user penalty $p to user $patronid");

			my $newp = Fieldmapper::actor::user_standing_penalty->new;
			$newp->penalty_type( $p );
			$newp->usr( $patronid );

			my $s = $session->request(
				'open-ils.storage.direct.actor.user_standing_penalty.create', $newp )->gather(1);
			return $U->DB_UPDATE_FAILED($p) unless $s;
		}
	}
	
	$U->commit_db_session($session);
	return undef;
}





1;
