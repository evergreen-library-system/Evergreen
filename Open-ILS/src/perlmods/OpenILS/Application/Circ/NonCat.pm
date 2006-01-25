package OpenILS::Application::Circ::NonCat;
use base 'OpenSRF::Application';
use strict; use warnings;
use OpenSRF::EX qw(:try);
use Data::Dumper;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
$Data::Dumper::Indent = 0;

my $U = "OpenILS::Application::AppUtils";


__PACKAGE__->register_method(
	method	=> "create_noncat_type",
	api_name	=> "open-ils.circ.non_cat_type.create",
	notes		=> q/
		Creates a new non cataloged item type
		@param authtoken The login session key
		@param name The name of the new type
		@param orgId The location where the type will live
		@return The type object on success and the corresponding
		event on failure
	/);

sub create_noncat_type {
	my( $self, $client, $authtoken, $name, $orgId ) = @_;
	my( $staff, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;

	my $type;

	# first, see if the exact type already exists  XXX this needs to be ranged
	($type, $evt) = $U->fetch_non_cat_type_by_name_and_org($name, $orgId);
	return OpenILS::Event->new('NON_CAT_TYPE_EXISTS') if $type;

	$evt = $U->check_perms( $staff->id, $orgId, 'CREATE_NON_CAT_TYPE' );
	return $evt if $evt;

	$type = Fieldmapper::config::non_cataloged_type->new;
	$type->name($name);
	$type->owning_lib($orgId);

	my $id = $U->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.config.non_cataloged_type.create', $type );

	return $U->DB_UPDATE_FAILED($type) unless $id;
	$type->id($id);
	return $type;
}

__PACKAGE__->register_method(
	method	=> "update_noncat_type",
	api_name	=> "open-ils.circ.non_cat_type.update",
	notes		=> q/
		Updates a non-cataloged type object
		@param authtoken The login session key
		@param type The updated type object
		@return The result of the DB update call unless a preceeding event occurs, 
			in which case the event will be returned
	/);

sub update_noncat_type {
	my( $self, $client, $authtoken, $type ) = @_;
	my( $staff, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;

	my $otype;
	($otype, $evt) = $U->fetch_non_cat_type($type->id);
	return $evt if $evt;

	$type->owning_lib($otype->owning_lib); # do not allow them to "move" the object

	$evt = $U->check_perms( $staff->id, $type->owning_lib, 'UPDATE_NON_CAT_TYPE' );
	return $evt if $evt;

	return $U->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.config.non_cataloged_type.update', $type );
}

__PACKAGE__->register_method(
	method	=> "retrieve_noncat_types_all",
	api_name	=> "open-ils.circ.non_cat_types.retrieve.all",
	notes		=> q/
		Retrieves the non-cat types at the requested location as well
		as those above and below the requested location in the org tree
		@param orgId The base location at which to retrieve the type objects
		@param depth Optional parameter to limit the depth of the tree
		@return An array of non cat type objects or an event if an error occurs
	/);

sub retrieve_noncat_types_all {
	my( $self, $client, $orgId, $depth ) = @_;
	my $meth = 'open-ils.storage.ranged.config.non_cataloged_type.retrieve.atomic';
	my $svc = 'open-ils.storage';
	return $U->simplereq($svc, $meth, $orgId, $depth) if defined($depth);
	return $U->simplereq($svc, $meth, $orgId);
}



1;
