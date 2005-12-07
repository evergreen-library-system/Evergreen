package OpenILS::Application::Actor::Container;
use base 'OpenSRF::Application';
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Perm;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::EX;

my $apputils = "OpenILS::Application::AppUtils";
my $logger = "OpenSRF::Utils::Logger";

sub initialize { return 1; }

=head comment
__PACKAGE__->register_method(
	method	=> "bucket_retrieve",
	api_name	=> "open-ils.actor.container.biblio_record_entry_bucket.retrieve_by_name",
	notes		=> <<"	NOTES");
		Retrieves a BREB by name.  PARAMS(authtoken, bucketOwnerId, bucketName)
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
	NOTES

__PACKAGE__->register_method(
	method	=> "bucket_retrieve",
	api_name	=> "open-ils.actor.container.biblio_record_entry_bucket.fleshed.retrieve_by_name",
	notes		=> <<"	NOTES");
		see: open-ils.actor.container.biblio_record_entry_bucket.retrieve_by_name
		Returns an array of { bucket : <bucketObj>, items : [ <I1>, <I2>, ...] } objects
	NOTES

__PACKAGE__->register_method(
	method	=> "bucket_retrieve",
	api_name	=> "open-ils.actor.container.biblio_record_entry_bucket.retrieve_by_user",
	notes		=> <<"	NOTES");
		Returns all BRE Buckets that belong to the given user. 
		PARAMS( authtoken, bucketOwnerId )
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
	NOTES

__PACKAGE__->register_method(
	method	=> "bucket_retrieve",
	api_name	=> "open-ils.actor.container.biblio_record_entry_bucket.fleshed.retrieve_by_user",
	notes		=> <<"	NOTES");
		see: open-ils.actor.container.biblio_record_entry_bucket.retrieve_by_user
		Returns an array of { bucket : <bucketObj>, items : [ <I1>, <I2>, ...] } objects
	NOTES



sub bucket_retrieve {
	my($self, $client, $authtoken, $userid, $name) = @_;

	my ($staff, $user, $perm) = 
		$apputils->handle_requestor( $authtoken, $userid, 'VIEW_CONTAINER');
	return $perm if $perm;

	$logger->activity("User " . $staff->id . " retrieving buckets for user $user");

	my $svc = 'open-ils.storage';
	my $meth = 'open-ils.storage.direct.container';
	my $bibmeth = "$meth.biblio_record_entry_bucket";
	my $cnmeth = "$meth.biblio_record_entry_bucket";
	my $copymeth = "$meth.biblio_record_entry_bucket";
	my $usermeth = "$meth.biblio_record_entry_bucket";

	my $buckets;
	my $items;
	my $resp = [];

	if( $self->api_name =~ /biblio/ ) {

		if( $self->api_name =~ /retrieve_by_user/ ) {
			$buckets =  $apputils->simplereq( $svc, 
				"$bibmeth.search.owner.atomic", $user ); }
	
		if( $self->api_name =~ /retrieve_by_name/ ) {
			$buckets = $apputils->simplereq( $svc, 
				"$bibmeth.search_where.atomic", { name => $name, owner => $user } ); }

		if( $self->api_name =~ /fleshed/ ) {
			for my $b (@$buckets) {
				next unless $b;
				$items = $apputils->simplereq( $svc,
					"$bibmeth"."_item.search.bucket.atomic", $b->id );
				push( @$resp, { bucket => $b , items => $items });
			}
		}
	}

	return $resp if ($self->api_name =~ /fleshed/);
	return $buckets;
}
=cut


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

	my ($staff, $user, $perm) = 
		$apputils->handle_requestor( $authtoken, $userid, 'VIEW_CONTAINER');
	return $perm if $perm;

	$logger->activity("User " . $staff->id . " retrieving buckets for user $user");

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
		PARAMS(authtoken, bucketId, bucketype)
		Types include biblio, callnumber, copy, and user
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
	NOTES

sub bucket_flesh {

	my($self, $client, $authtoken, $bucket, $type) = @_;

	my( $staff, $evt ) = $apputils->check_ses($authtoken);
	return $evt if $evt;

	my $meth = $bibmeth;
	$meth = $cnmeth if $type eq "callnumber";
	$meth = $copymeth if $type eq "copy";
	$meth = $usermeth if $type eq "user";

	my $bkt = $apputils->simplereq( $svc, "$meth.retrieve", $bucket );
	if(!$bkt) {return undef};

	$logger->debug("Fetching fleshed bucket $bucket");

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


1;


