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
	method    => 'users_of_interest',
	api_name  => 'open-ils.collections.users_of_interest.retrieve',
	api_level => 1,
	argc      => 4,
	signature => { 
		desc     => q/
			Returns an array of user information objects that the system 
			based on the search criteria provided.  If the total fines
			a user owes reaches or exceeds "fine_level" on or befre "age"
			and the fines were created at "location", the user will be 
			included in the return set/,
		            
		params   => [
			{	name => 'auth',
				desc => 'The authentication token',
				type => 'string' },

			{	name => 'age',
				desc => q/The date before or at which the user's fine level exceeded the fine_level param/,
				type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
			},

			{	name => 'fine_level',
				desc => q/The fine threshold at which users will be included in the search results /,
				type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
			},
			{	name => 'location',
				desc => q/The short-name of the orginization unit (library) at which the fines were created.  
							If a selected location has 'child' locations (e.g. a library region), the
							child locations will be included in the search/,
				type => q/string/,
			},
		],

	  	'return' => { 
			desc		=> q/An array of user information objects.  
						usr : Array of user information objects containing id, dob, profile, and groups
						threshold_amount : The total amount the patron owes that is at least as old
							as the fine "age" and whose transaction was created at the searched location
						last_pertinent_billing : The time of the last billing that relates to this query
						/,
			type		=> 'array',
			example	=> {
				usr	=> {
					id			=> 'id',
					dob		=> '1970-01-01',
					profile	=> 'Patron',
					groups	=> [ 'Patron', 'Staff' ],
				},
				threshold_amount => 99,
			}
		}
	}
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
					flesh_fields	=> {au => ["groups","profile", "card"]},
					select			=> {au => ["profile","id","dob", "card"]}
				}
			]
		);

		$_->{usr} = {
			id			=> $u->id,
			dob		=> $u->dob,
			profile	=> $u->profile->name,
			barcode	=> $u->card->barcode,
			groups	=> [ map { $_->name } @{$u->groups} ],
		};
	}

	return $data;
}


__PACKAGE__->register_method(
	method    => 'users_with_activity',
	api_name  => 'open-ils.collections.users_with_activity.retrieve',
	api_level => 1,
	argc      => 4,
	signature => { 
		desc     => q/
			Returns an array of users that are already in collections 
			and had any type of billing or payment activity within
			the given time frame at the location (or child locations)
			provided/,
		            
		params   => [
			{	name => 'auth',
				desc => 'The authentication token',
				type => 'string' },

			{	name => 'start_date',
				desc => 'The start of the time interval to check',
				type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
			},

			{	name => 'end_date',
				desc => q/Then end date of the time interval to check/,
				type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
			},
			{	name => 'location',
				desc => q/The short-name of the orginization unit (library) at which the activity occurred.
							If a selected location has 'child' locations (e.g. a library region), the
							child locations will be included in the search/,
				type => q'string',
			},
		],

	  	'return' => { 
			desc		=> q/An array of user information objects/,
			type		=> 'array',
		}
	}
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
	method    => 'put_into_collections',
	api_name  => 'open-ils.collections.put_into_collections',
	api_level => 1,
	argc      => 3,
	signature => { 
		desc     => q/
			Marks a user as being "in collections" at a given location
			/,
		            
		params   => [
			{	name => 'auth',
				desc => 'The authentication token',
				type => 'string' },

			{	name => 'user_id',
				desc => 'The id of the user to plact into collections',
				type => 'number',
			},

			{	name => 'location',
				desc => q/The short-name of the orginization unit (library) 
					for which the user is being placed in collections/,
				type => q'string',
			},
		],

	  	'return' => { 
			desc		=> q/A SUCCESS event on success, error event on failure/,
			type		=> 'object',
		}
	}
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


	my $existing = $e->search_money_collections_tracker(
		{
			location		=> $org->id,
			usr			=> $user_id,
			collector	=> $e->requestor->id
		},
		{idlist => 1}
	);

	return OpenILS::Event->new('MONEY_COLLECTIONS_TRACKER_EXISTS') if @$existing;

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


__PACKAGE__->register_method(
	method    => 'remove_from_collections',
	api_name  => 'open-ils.collections.remove_from_collections',
	api_level => 1,
	argc      => 3,
	signature => { 
		desc     => q/
			Removes a user from the collections table for the given location
			/,
		            
		params   => [
			{	name => 'auth',
				desc => 'The authentication token',
				type => 'string' },

			{	name => 'user_id',
				desc => 'The id of the user to plact into collections',
				type => 'number',
			},

			{	name => 'location',
				desc => q/The short-name of the orginization unit (library) 
					for which the user is being removed from collections/,
				type => q'string',
			},
		],

	  	'return' => { 
			desc		=> q/A SUCCESS event on success, error event on failure/,
			type		=> 'object',
		}
	}
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


__PACKAGE__->register_method(
	method    => 'transaction_details',
	api_name  => 'open-ils.collections.user_transaction_details.retrieve',
	api_level => 1,
	argc      => 5,
	signature => { 
		desc     => q/
			Returns a list of fleshed user objects with transaction details
			/,
		            
		params   => [
			{	name => 'auth',
				desc => 'The authentication token',
				type => 'string' },

			{	name => 'start_date',
				desc => 'The start of the time interval to check',
				type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
			},

			{	name => 'end_date',
				desc => q/Then end date of the time interval to check/,
				type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
			},
			{	name => 'location',
				desc => q/The short-name of the orginization unit (library) at which the activity occurred.
							If a selected location has 'child' locations (e.g. a library region), the
							child locations will be included in the search/,
				type => q'string',
			},
			{
				name => 'user_list',
				desc => 'An array of user ids',
				type => 'array',
			},
		],

	  	'return' => { 
			desc		=> q/A list of objects.  Object keys include:
				usr :
				transactions : An object with keys :
					circulations : Fleshed circulation objects
					grocery : Fleshed 'grocery' transaction objects
				/,
			type		=> 'object'
		}
	}
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
							#xact_finish			=> undef, 
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
