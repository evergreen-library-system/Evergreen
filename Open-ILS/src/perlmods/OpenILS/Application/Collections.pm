package OpenILS::Application::Collections;
use strict; use warnings;
use OpenSRF::EX qw(:try);
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Application;
use base 'OpenSRF::Application';
my $U = "OpenILS::Application::AppUtils";
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;


# --------------------------------------------------------------
# Loads the config info
# --------------------------------------------------------------
sub initialize { return 1; }


__PACKAGE__->register_method(
	method		=> 'users_of_interest',
	api_name		=> 'open-ils.collections.users_of_interest.retrieve',
	signature	=> q/
		@param age This is the age before which the fine_level was exceeded.
		@param fine_level The minimum fine to exceed.
		@param location The location at which the fines were created
	/
);

sub users_of_interest {
	my( $self, $conn, $auth, $age, $fine_level, $location ) = @_;

	return OpenILS::Event->new('BAD_PARAMS') 
		unless ($auth and $age and $fine_level and $location);

	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;

	my $org = $e->search_actor_org_unit({shortname => $location})
		or return $e->event; $org = $org->[0];
	return $e->event unless $e->allowed('VIEW_USER', $org->id);

	return $U->storagereq(
		'open-ils.storage.money.collections.users_of_interest.atomic', 
		$age, $fine_level, $location);
}


__PACKAGE__->register_method(
	method		=> 'users_with_activity',
	api_name		=> 'open-ils.collections.users_with_activity.retrieve',
	signature	=> q/
		Returns the users that are currently in collections and
		had activity during the provided interval.  Dates are inclusive.
		@param start_date The beginning of the activity interval
		@param end_date The end of the activity interval
		@param location The location at which the fines were created
	/
);

sub users_with_activity {
	my( $self, $conn, $auth, $start_date, $end_date, $location ) = @_;
	return OpenILS::Event->new('BAD_PARAMS') 
		unless ($auth and $start_date and $end_date and $location);

	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;

	my $org = $e->search_actor_org_unit({shortname => $location})
		or return $e->event; $org = $org->[0];
	return $e->event unless $e->allowed('VIEW_USER', $org->id);

	return $U->storagereq(
		'open-ils.storage.money.collections.users_with_activity.atomic', 
		$start_date, $end_date, $location);
}



__PACKAGE__->register_method(
	method		=> 'put_into_collections',
	api_name		=> 'open-ils.collections.put_into_collections',
	signature	=> q/
		Returns the users that are currently in collections and
		had activity during the provided interval.  Dates are inclusive.
		@param start_date The beginning of the activity interval
		@param end_date The end of the activity interval
		@param location The location at which the fines were created
	/
);

sub put_into_collections {
	my( $self, $conn, $auth, $user_id, $location ) = @_;

	return OpenILS::Event->new('BAD_PARAMS') 
		unless ($auth and $user_id and $location);

	my $e = new_editor(authtoken => $auth, xact =>1);
	return $e->event unless $e->checkauth;

	my $org = $e->search_actor_org_unit({shortname => $location})
		or return $e->event; $org = $org->[0];
	return $e->event unless $e->allowed('money.collections_tracker.create', $org->id);

	my $tracker = Fieldmapper::money::collections_tracker->new;

	$tracker->usr($user_id);
	$tracker->collector($e->requestor->id);
	$tracker->location($org->id);
	$tracker->enter_time('now');

	$e->create_money_collections_tracker($tracker) 
		or return $e->event;

	$e->commit;
	return OpenILS::Event->new('SUCCESS');
}




__PACKAGE__->register_method(
	method		=> 'remove_from_collections',
	api_name		=> 'open-ils.collections.remove_from_collections',
	signature	=> q/
		Returns the users that are currently in collections and
		had activity during the provided interval.  Dates are inclusive.
		@param start_date The beginning of the activity interval
		@param end_date The end of the activity interval
		@param location The location at which the fines were created
	/
);

sub remove_from_collections {
	my( $self, $conn, $auth, $user_id, $location ) = @_;

	return OpenILS::Event->new('BAD_PARAMS') 
		unless ($auth and $user_id and $location);

	my $e = new_editor(authtoken => $auth, xact=>1);
	return $e->event unless $e->checkauth;

	my $org = $e->search_actor_org_unit({shortname => $location})
		or return $e->event; $org = $org->[0];
	return $e->event unless $e->allowed('money.collections_tracker.delete', $org->id);

	my $tracker = $e->search_money_collections_tracker(
		{ usr => $user_id, location => $org->id })
		or return $e->event;

	$e->delete_money_collections_tracker($tracker->[0])
		or return $e->event;

	$e->commit;
	return OpenILS::Event->new('SUCCESS');
}

1;
