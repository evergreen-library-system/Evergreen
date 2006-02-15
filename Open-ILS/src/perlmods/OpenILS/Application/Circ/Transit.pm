package OpenILS::Application::Circ::Transit;
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

my $U							= "OpenILS::Application::AppUtils";
my $holdcode				= "OpenILS::Application::Circ::Holds";
$Data::Dumper::Indent	= 0;



__PACKAGE__->register_method(
	method	=> "copy_transit_receive",
	api_name	=> "open-ils.circ.copy_transit.receive",
	notes		=> q/
		Closes out a copy transit
		Requestor needs the COPY_TRANSIT_RECEIVE permission
		@param authtoken The login session key
		@param params An object of named params including
			copyid - the id of the copy in quest
			barcode - the barcode of the copy in question 
				If copyid is not sent, this is used.
		@return A ROUTE_ITEM if the copy is destined for a different location.
			A SUCCESS event on success. Other events on error.
	/);

sub copy_transit_receive {
	my( $self, $client, $authtoken, $params ) = @_;
	my %params = %$params;
	my( $evt, $copy, $requestor );
	($requestor, $evt) = $U->checksesperm($authtoken, 'COPY_TRANSIT_RECEIVE');
	return $evt if $evt;
	($copy, $evt) = $U->fetch_copy($params{copyid});
	($copy, $evt) = $U->fetch_copy_by_barcode($params{barcode}) unless $copy;
	return $evt if $evt;
	my $session = $U->start_db_session();
	$evt = $self->transit_receive( $copy, $requestor, $session );
	$U->commit_db_session($session) if $U->event_equals($evt,'SUCCESS');
	return $evt;
}

# ------------------------------------------------------------------------------
# If the transit destination is different than the requestor's lib,
# a ROUTE_TO event is returned with the org set.
# If 
# ------------------------------------------------------------------------------
sub transit_receive {
	my ( $class, $copy, $requestor, $session ) = @_;
	$U->logmark;

	my( $transit, $hold_transit, $evt );
	my $copyid = $copy->id;

	my $status_name = $U->copy_status_to_name($copy->status);
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

	my $ishold = 0;
	my ($ht) = $U->fetch_hold_transit( $transit->id );

	if($ht) {

		$logger->info("Hold transit found: ".$hold_transit->id.". Setting copy status to 'on holds shelf'");
		$copy->status($U->copy_status_from_name('on holds shelf')->id);
		$ishold = 1;

	} else {

		$logger->info("Hold transit not found, recovering original copy status");
		$copy->status( $transit->copy_status );
	}

	
	return $evt if ( $evt = 
		$U->update_copy( copy => $copy, editor => $requestor->id, session => $session ));

	return OpenILS::Event->new('SUCCESS', ishold => $ishold, payload => $copy);
}




__PACKAGE__->register_method(
	method	=> "copy_transit_create",
	api_name	=> "open-ils.circ.copy_transit.create",
	notes		=> q/
		Creates a new copy transit.  Requestor must have the 
		CREATE_COPY_TRANSIT permission.
		@param authtoken The login session key
		@param params A param object containing the following keys:
			copyid		- the copy id
			destination	- the id of the org destination.  If not defined,
				defaults to the copy's circ_lib
		@return SUCCESS event on success, other event on error
	/);

sub copy_transit_create {

	my( $self, $client, $authtoken, $params ) = @_;
	my %params = %$params;

	my( $requestor, $evt ) = 
		$U->checksesperm( $authtoken, 'CREATE_COPY_TRANSIT' );
	return $evt if $evt;

	my $copy;
	($copy,$evt) = $U->fetch_copy($params{copyid});
	return $evt if $evt;

	my $session		= $params{session} || $U->start_db_session();
	my $source		= $requestor->home_ou;
	my $dest			= $params{destination} || $copy->circ_lib;
	my $transit		= Fieldmapper::action::transit_copy->new;

	$logger->activity("User ". $requestor->id ." creating a ".
		" new copy transit for copy ".$copy->id." to org $dest");

	$transit->source($source);
	$transit->dest($dest);
	$transit->target_copy($copy->id);
	$transit->source_send_time("now");
	$transit->copy_status($copy->status);
	
	$logger->debug("Creating new copy_transit in DB");

	my $s = $session->request(
		"open-ils.storage.direct.action.transit_copy.create", $transit )->gather(1);
	return $U->DB_UPDATE_FAILED($transit) unless $s;
	
	my $stat = $U->copy_status_from_name('in transit');

	$copy->status($stat->id); 
	return $evt if ($evt = $U->update_copy(
		copy => $copy, editor => $requestor->id, session => $session ));

	$U->commit_db_session($session) unless $params{session};

	return OpenILS::Event->new('SUCCESS', 
		payload => { copy => $copy, transit => $transit } );
}
	




666;
