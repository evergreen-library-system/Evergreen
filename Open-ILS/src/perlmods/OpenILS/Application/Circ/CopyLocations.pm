package OpenILS::Application::Circ::CopyLocations;
use base 'OpenSRF::Application';
use strict; use warnings;
use Data::Dumper;
$Data::Dumper::Indent = 0;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
my $U = "OpenILS::Application::AppUtils";


__PACKAGE__->register_method(
	api_name		=> "open-ils.circ.copy_location.retrieve.all",
	method		=> 'cl_retrieve_all',
	argc			=>	1,
	signature	=> q/
		Retrieves the ranged set of copy locations for the requested org.
		If no org is provided, the home org of the requestor is used.
		@param authtoken The login session key
		@param orgId The org location id
		@return An array of copy location objects
		/);

sub cl_retrieve_all {
	my( $self, $client, $authtoken, $orgId ) = @_;
	my( $requestor, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;
	$orgId = defined($orgId) ? $orgId : $requestor->home_ou;
	$logger->debug("Fetching ranged copy location set for org $orgId");
	return $U->storagereq(
		'open-ils.storage.ranged.asset.copy_location.retrieve.atomic', $orgId);
}

__PACKAGE__->register_method(
	api_name		=> 'open-ils.circ.copy_location.create',
	method		=> 'cl_create',
	argc			=> 2,
	signature	=> q/
		Creates a new copy location.  Requestor must have the CREATE_COPY_LOCATION
		permission at the location specified on the new location object
		@param authtoken The login session key
		@param copyLoc The new copy location object
		@return The if of the new location object on success, event on error
	/);

sub cl_create {
	my( $self, $client, $authtoken, $copyLoc ) = @_;
	my( $requestor, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;
	$evt = $U->check_perms($requestor->id, 
		$copyLoc->owning_lib, 'CREATE_COPY_LOCATION');
	return $evt if $evt;

	my $cl;
	($cl, $evt) = $U->fetch_copy_location_by_name($copyLoc->name, $copyLoc->owning_lib);
	return OpenILS::Event->new('COPY_LOCATION_EXISTS') if $cl;

	my $id = $U->storagereq(
		'open-ils.storage.direct.asset.copy_location.create', $copyLoc );

	return $U->DB_UPDATE_FAILED($copyLoc) unless $id;
	return $id;
}

__PACKAGE__->register_method (
	api_name		=> 'open-ils.circ.copy_location.delete',
	method		=> 'cl_delete',
	argc			=> 2,
	signature	=> q/
		Deletes a copy location. Requestor must have the 
		DELETE_COPY_LOCATION permission.
		@param authtoken The login session key
		@param id The copy location object id
		@return 1 on success, event on error
	/);

sub cl_delete {
	my( $self, $client, $authtoken, $id ) = @_;
	my( $requestor, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;

	my $cl;
	($cl, $evt) = $U->fetch_copy_location($id);
	return $evt if $evt;

	$evt = $U->check_perms($requestor->id, 
		$cl->owning_lib, 'DELETE_COPY_LOCATION');
	return $evt if $evt;

	my $resp = $U->storagereq(
		'open-ils.storage.direct.asset.copy_location.delete', $id );
	
	return $U->DB_UPDATE_FAILED unless $resp;
	return 1;
}

__PACKAGE__->register_method (
	api_name		=> 'open-ils.circ.copy_location.update',
	method		=> 'cl_update',
	argc			=> 2,
	signature	=> q/
		Updates a copy location object.  Requestor must have 
		the UPDATE_COPY_LOCATION permission
		@param authtoken The login session key
		@param copyLoc	The copy location object
		@return 1 on success, event on error
	/);

sub cl_update {
	my( $self, $client, $authtoken, $copyLoc ) = @_;

	my( $requestor, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;

	my $cl; 
	($cl, $evt) = $U->fetch_copy_location($copyLoc->id);
	return $evt if $evt;

	$evt = $U->check_perms($requestor->id, 
		$cl->owning_lib, 'UPDATE_COPY_LOCATION');
	return $evt if $evt;

	$copyLoc->owning_lib($cl->owning_lib); #disallow changing of the lib

	my $resp = $U->storagereq(
		'open-ils.storage.direct.asset.copy_location.update', $copyLoc );
	
	return 1; # if there was no exception thrown, then the update was a success
}



666;
