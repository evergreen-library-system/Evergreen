package OpenILS::Application::Actor::Container;
use base 'OpenSRF::Application';
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Perm;
use Data::Dumper;
use OpenSRF::EX qw(:try);

my $apputils = "OpenILS::Application::AppUtils";
my $logger = "OpenSRF::Utils::Logger";

sub initialize { return 1; }

my $svc = 'open-ils.storage';
my $meth = 'open-ils.storage.direct.container';
my $bibmeth = "$meth.biblio_record_entry_bucket";
my $cnmeth = "$meth.call_number_bucket";
my $copymeth = "$meth.copy_bucket";
my $usermeth = "$meth.user_bucket";

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

	my ($staff, $user, $evt) = 
		$apputils->handle_requestor( $authtoken, $userid, 'VIEW_CONTAINER');
	return $evt if $evt;

	$logger->debug("User " . $staff->id . 
		" retrieving all buckets for user $user");

	my %buckets;

	$buckets{biblio} = $apputils->simplereq( $svc, "$bibmeth.search.owner.atomic", $user ); 
	$buckets{callnumber} = $apputils->simplereq( $svc, "$cnmeth.search.owner.atomic", $user ); 
	$buckets{copy} = $apputils->simplereq( $svc, "$copymeth.search.owner.atomic", $user ); 
	$buckets{user} = $apputils->simplereq( $svc, "$usermeth.search.owner.atomic", $user ); 

	return \%buckets;
}

__PACKAGE__->register_method(
	method	=> "bucket_flesh",
	api_name	=> "open-ils.actor.container.bucket.flesh",
	notes		=> <<"	NOTES");
		Fleshes a bucket by id
		PARAMS(authtoken, bucketId, buckeclass)
		bucketclasss include biblio, callnumber, copy, and user.  
		bucketclass defaults to biblio.
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
	NOTES

sub bucket_flesh {

	my($self, $client, $authtoken, $bucket, $type) = @_;

	my( $staff, $evt ) = $apputils->check_ses($authtoken);
	return $evt if $evt;

	$logger->debug("User " . $staff->id . " retrieving bucket $bucket");

	my $meth = $bibmeth;
	$meth = $cnmeth if $type eq "callnumber";
	$meth = $copymeth if $type eq "copy";
	$meth = $usermeth if $type eq "user";

	my $bkt = $apputils->simplereq( $svc, "$meth.retrieve", $bucket );
	if(!$bkt) {return undef};

	if( $bkt->owner ne $staff->id ) {
		my $userobj = $apputils->fetch_user($bkt->owner);
		my $perm = $apputils->check_perms( 
			$staff->id, $userobj->home_ou, 'VIEW_CONTAINER' );
		return $perm if $perm;
	}

	$bkt->items( $apputils->simplereq( $svc,
		"$meth"."_item.search.bucket.atomic", $bucket ) );

	return $bkt;
}


__PACKAGE__->register_method(
	method	=> "bucket_retrieve_class",
	api_name	=> "open-ils.actor.container.bucket.retrieve_by_class",
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

	my ($staff, $user, $evt) = 
		$apputils->handle_requestor( $authtoken, $userid, 'VIEW_CONTAINER');
	return $evt if $evt;

	$logger->debug("User " . $staff->id . 
		" retrieving buckets for $user [class=$class, type=$type]");

	my $meth = $bibmeth;
	$meth = $cnmeth if $class eq "callnumber";
	$meth = $copymeth if $class eq "copy";
	$meth = $usermeth if $class eq "user";

	my $buckets;

	if( $type ) {
		$buckets = $apputils->simplereq( $svc,
			"$meth.search_where.atomic", { owner => $user, btype => $type } );
	} else {
		$buckets = $apputils->simplereq( $svc,
			"$meth.search_where.atomic", { owner => $user } );
	}

	return $buckets;
}


1;


