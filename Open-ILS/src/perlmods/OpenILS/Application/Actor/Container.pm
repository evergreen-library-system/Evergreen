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
	api_name	=> "open-ils.actor.container.biblio_record_entry_bucket.retrieve_by_user",
	notes		=> <<"	NOTES");
		Returns all BRE Buckets that belong to the given user. 
		PARAMS( authtoken, bucketOwnerId )
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
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

	if( $self->api_name =~ /biblio.*retrieve_by_user/ ) {
		return $apputils->simplereq( $svc, 
			"$bibmeth.search.owner.atomic", $user ); }

	if( $self->api_name =~ /biblio.*retrieve_by_name/ ) {
		return $apputils->simplereq( $svc, 
			"$bibmeth.search_where", { name => $name, owner => $user } ); }


}



1;


