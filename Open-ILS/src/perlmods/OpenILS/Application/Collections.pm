package OpenILS::Application::Collections;
use strict; use warnings;
use OpenSRF::EX qw(:try);
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Application;
use base 'OpenSRF::Application';
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Event;
my $U = "OpenILS::Application::AppUtils";


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

	# they need global perms to view users so no org is provided
	return $e->event unless $e->allowed('VIEW_USER'); 

	my $data = $U->storagereq(
		'open-ils.storage.money.collections.users_of_interest.atomic', 
		$age, $fine_level, $location);

	return [] unless $data and @$data;

	for (@$data) {
		my $u = $e->retrieve_actor_user(
			[
				$_->{usr},
				{
					flesh				=> 1,
					flesh_fields	=> {au => ["groups","profile"]},
					select			=> {au => ["profile","id","dob"]}
				}
			]
		);

		$_->{usr} = {
			id			=> $u->id,
			dob		=> $u->dob,
			profile	=> $u->profile->name,
			groups	=> [ map { $_->name } @{$u->groups} ],
		};
	}

	return $data;
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


__PACKAGE__->register_method(
	method		=> 'transaction_details',
	api_name		=> 'open-ils.collections.user_transaction_details.retrieve',
	signature	=> q/
	/
);

sub transaction_details {
	my( $self, $conn, $auth, $start_date, $end_date, $location, $user_list ) = @_;

	return OpenILS::Event->new('BAD_PARAMS') 
		unless ($auth and $start_date and $end_date and $location and $user_list);

	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;

	# they need global perms to view users so no org is provided
	return $e->event unless $e->allowed('VIEW_USER'); 

	my $org = $e->search_actor_org_unit({shortname => $location})
		or return $e->event; $org = $org->[0];

	# get a reference to the org inside of the tree
	$org = $U->find_org($U->fetch_org_tree(), $org->id);

	my @data;
	for my $uid (@$user_list) {
		my $blob = {};

		$blob->{usr} = $e->retrieve_actor_user(
			[
				$uid,
         	{
            	"flesh"        => 1,
            	"flesh_fields" =>  {
               	"au" => [
                  	"cards",
                  	"card",
                  	"standing_penalties",
                  	"addresses",
                  	"billing_address",
                  	"mailing_address",
                  	"stat_cat_entries"
               	]
            	}
         	}
			]
		);

		$blob->{transactions} = {
			circulations	=> 
				fetch_circ_xacts($e, $uid, $org, $start_date, $end_date),
			grocery			=> 
				fetch_grocery_xacts($e, $uid, $org, $start_date, $end_date)
		};

		push( @data, $blob );
	}

	return \@data;
}


# --------------------------------------------------------------
# Collect all open circs for the user 
# For each circ, see if any billings or payments were created
# during the given time period.  
# --------------------------------------------------------------
sub fetch_circ_xacts {
	my $e				= shift;
	my $uid			= shift;
	my $org			= shift;
	my $start_date = shift;
	my $end_date	= shift;

	my @circs;

	# at the specified org and each descendent org, 
	# fetch the open circs for this user
	$U->walk_org_tree( $org, 
		sub {
			my $n = shift;
			$logger->debug("collect: searching for open circs at " . $n->shortname);
			push( @circs, 
				@{
					$e->search_action_circulation(
						{
							usr			=> $uid, 
							circ_lib		=> $n->id,
							xact_finish	=> undef, 
						}, 
						{idlist => 1}
					)
				}
			);
		}
	);


	my @data;
	my $active_ids = fetch_active($e, \@circs, $start_date, $end_date);

	for my $cid (@$active_ids) {
		push( @data, 
			$e->retrieve_action_circulation(
				[
					$cid,
					{
						flesh => 1,
						flesh_fields => { 
							circ => [ "billings", "payments", "circ_lib" ]
						}
					}
				]
			)
		);
	}

	return \@data;
}


sub fetch_grocery_xacts {
	my $e				= shift;
	my $uid			= shift;
	my $org			= shift;
	my $start_date = shift;
	my $end_date	= shift;

	my @xacts;
	$U->walk_org_tree( $org, 
		sub {
			my $n = shift;
			$logger->debug("collect: searching for open grocery xacts at " . $n->shortname);
			push( @xacts, 
				@{
					$e->search_money_grocery(
						{
							usr					=> $uid, 
							billing_location	=> $n->id,
							xact_finish			=> undef, 
						}, 
						{idlist => 1}
					)
				}
			);
		}
	);

	my @data;
	my $active_ids = fetch_active($e, \@xacts, $start_date, $end_date);

	for my $id (@$active_ids) {
		push( @data, 
			$e->retrieve_money_grocery(
				[
					$id,
					{
						flesh => 1,
						flesh_fields => { 
							mg => [ "billings", "payments", "billing_location" ] }
					}
				]
			)
		);
	}

	return \@data;
}



# --------------------------------------------------------------
# Given a list of xact id's, this returns a list of id's that
# had any activity within the given time span
# --------------------------------------------------------------
sub fetch_active {
	my( $e, $ids, $start_date, $end_date ) = @_;

	# use this..
	# { payment_ts => { between => [ $start, $end ] } } ' ;) 

	my @active;
	for my $id (@$ids) {

		# see if any billings were created in the given time range
		my $bills = $e->search_money_billing (
			{
				xact			=> $id,
				billing_ts	=> { between => [ $start_date, $end_date ] },
			},
			{idlist =>1}
		);

		my $payments = [];

		if( !@$bills ) {

			# see if any payments were created in the given range
			$payments = $e->search_money_payment (
				{
					xact			=> $id,
					payment_ts	=> { between => [ $start_date, $end_date ] },
				},
				{idlist =>1}
			);
		}


		push( @active, $id ) if @$bills or @$payments;
	}

	return \@active;
}

1;
