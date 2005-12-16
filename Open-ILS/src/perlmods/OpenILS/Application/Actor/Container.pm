package OpenILS::Application::Actor::Container;
use base 'OpenSRF::Application';
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Perm;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;

my $apputils = "OpenILS::Application::AppUtils";
my $logger = "OpenSRF::Utils::Logger";

sub initialize { return 1; }

my $svc = 'open-ils.storage';
my $meth = 'open-ils.storage.direct.container';
my %types;
$types{'biblio'} = "$meth.biblio_record_entry_bucket";
$types{'callnumber'} = "$meth.call_number_bucket";
$types{'copy'} = "$meth.copy_bucket";
$types{'user'} = "$meth.user_bucket";
my $event;

__PACKAGE__->register_method(
	method	=> "bucket_retrieve_all",
	api_name	=> "open-ils.actor.container.bucket.all.retrieve_by_user",
	notes		=> <<"	NOTES");
		Retrieves all un-fleshed buckets assigned to given user 
		PARAMS(authtoken, bucketOwnerId)
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
	NOTES

sub bucket_retrieve_all {
	my($self, $client, $authtoken, $userid) = @_;

	my( $staff, $evt ) = $apputils->checkses($authtoken);
	return $evt if $evt;

	my( $user, $e ) = $apputils->checkrequestor( $staff, $userid, 'VIEW_CONTAINER');
	return $e if $e;

	$logger->debug("User " . $staff->id . 
		" retrieving all buckets for user $userid");

	my %buckets;

	$buckets{$_} = $apputils->simplereq( 
		$svc, $types{$_} . ".search.owner.atomic", $userid ) for keys %types;

	return \%buckets;
}

__PACKAGE__->register_method(
	method	=> "bucket_flesh",
	api_name	=> "open-ils.actor.container.bucket.flesh",
	argc		=> 3, 
	notes		=> <<"	NOTES");
		Fleshes a bucket by id
		PARAMS(authtoken, bucketClass, bucketId)
		bucketclasss include biblio, callnumber, copy, and user.  
		bucketclass defaults to biblio.
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
	NOTES

sub bucket_flesh {

	my($self, $client, $authtoken, $class, $bucket) = @_;

	my( $staff, $evt ) = $apputils->checkses($authtoken);
	return $evt if $evt;

	$logger->debug("User " . $staff->id . " retrieving bucket $bucket");

	my $meth = $types{$class};

	my $bkt = $apputils->simplereq( $svc, "$meth.retrieve", $bucket );
	if(!$bkt) {return undef};

	my( $user, $e ) = $apputils->checkrequestor( $staff, $bkt->owner, 'VIEW_CONTAINER' );
	return $e if $e;

	$bkt->items( $apputils->simplereq( $svc,
		"$meth"."_item.search.bucket.atomic", $bucket ) );

	return $bkt;
}


__PACKAGE__->register_method(
	method	=> "bucket_retrieve_class",
	api_name	=> "open-ils.actor.container.bucket.retrieve_by_class",
	argc		=> 3, 
	notes		=> <<"	NOTES");
		Retrieves all un-fleshed buckets by class assigned to given user 
		PARAMS(authtoken, bucketOwnerId, class [, type])
		class can be one of "biblio", "callnumber", "copy", "user"
		The optional "type" parameter allows you to limit the search by 
		bucket type.  
		If bucketOwnerId is not defined, the authtoken is used as the
		bucket owner.
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
	NOTES

sub bucket_retrieve_class {
	my( $self, $client, $authtoken, $userid, $class, $type ) = @_;

	my( $staff, $user, $evt );
	($staff, $evt) = $apputils->checkses($authtoken);
	return $evt if $evt;

	($user, $evt) = $apputils->checkrequestor($staff, $userid, 'VIEW_CONTAINER');
	return $evt if $evt;

	$logger->debug("User " . $staff->id . 
		" retrieving buckets for user $userid [class=$class, type=$type]");

	my $meth = $types{$class} . ".search_where.atomic";
	my $buckets;

	if( $type ) {
		$buckets = $apputils->simplereq( $svc, 
			$meth, { owner => $userid, btype => $type } );
	} else {
		$logger->debug("Grabbing buckets by class $class: $svc : $meth :  {owner => $userid}");
		$buckets = $apputils->simplereq( $svc, $meth, { owner => $userid } );
	}

	return $buckets;
}

__PACKAGE__->register_method(
	method	=> "bucket_create",
	api_name	=> "open-ils.actor.container.bucket.create",
	notes		=> <<"	NOTES");
		Creates a new bucket object.  If requestor is different from
		bucketOwner, requestor needs CREATE_CONTAINER permissions
		PARAMS(authtoken, bucketObject);
		Returns the new bucket object
	NOTES

sub bucket_create {
	my( $self, $client, $authtoken, $class, $bucket ) = @_;

	my( $staff, $target, $evt ) = 
		$apputils->checkses_requestor( 
			$authtoken, $bucket->owner, 'CREATE_CONTAINER' );
	return $evt if $evt;

	$logger->activity( "User " . $staff->id . 
		" creating a new continer for user " . $bucket->owner );

	$logger->debug("Creating new container object: " . Dumper($bucket));

	my $method = $types{$class} . ".create";
	my $id = $apputils->simplreq( $svc, $method, $bucket );

	$logger->debug("Creatined new container with id $id");

	if(!$id) { throw OpenSRF::EX 
		("Unable to create new bucket object"); }

	return $id;
}


__PACKAGE__->register_method(
	method	=> "bucket_delete",
	api_name	=> "open-ils.actor.container.bucket.delete",
	notes		=> <<"	NOTES");
		Deletes a bucket object.  If requestor is different from
		bucketOwner, requestor needs DELETE_CONTAINER permissions
		PARAMS(authtoken, class, bucketId);
		Returns the new bucket object
	NOTES

sub bucket_delete {
	my( $self, $client, $authtoken, $class, $bucketid ) = @_;

	my $bucket = $apputils->simplereq( 
		$svc, $types{$class} . ".retrieve", $bucketid );

	if(!$bucket) {
		return OpenILS::Event->new('CONTAINER_NOT_FOUND');
	}

	my( $staff, $target, $evt ) = $apputils->checkses_requestor( 
		$authtoken, $bucket->owner, 'DELETE_CONTAINER' );
	return $evt if $evt;

	$logger->activity( "User " . $staff->id . 
		" deleting continer $bucketid for user " . $bucket->owner );

	my $method = $types{$class} . ".delete";
	my $resp = $apputils->simplreq( $svc, $method, $bucketid );

	if(!$resp) { throw OpenSRF::EX 
		("Unable to create new bucket object"); }
	return $resp;

}



1;


