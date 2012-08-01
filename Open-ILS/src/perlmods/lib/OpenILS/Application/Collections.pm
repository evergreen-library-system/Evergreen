package OpenILS::Application::Collections;
use strict; use warnings;
use OpenSRF::EX qw(:try);
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw(:logger);
use OpenSRF::Utils qw/:datetime/;
use OpenILS::Application;
use OpenILS::Utils::Fieldmapper;
use base 'OpenILS::Application';
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Event;
use OpenILS::Const qw/:const/;
my $U = "OpenILS::Application::AppUtils";
use XML::LibXML;
use Scalar::Util 'blessed';
use File::Spec;
use File::Copy;
use File::Path;


# --------------------------------------------------------------
# Loads the config info
# --------------------------------------------------------------
sub initialize { return 1; }

__PACKAGE__->register_method(
    method => 'user_from_bc',
    api_name => 'open-ils.collections.user_id_from_barcode',
);

sub user_from_bc {
    my( $self, $conn, $auth, $bc ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_USER');
    my $card = $e->search_actor_card({barcode=>$bc})->[0]
        or return $e->event;
    my $user = $e->retrieve_actor_user($card->usr)
        or return $e->event;
    return $user->id;
}


__PACKAGE__->register_method(
    method    => 'users_of_interest',
    api_name  => 'open-ils.collections.users_of_interest.retrieve',
    api_level => 1,
    argc      => 4,
    stream    => 1,
    signature => {
        desc     => q/
            Returns an array of user information objects that the system
            based on the search criteria provided.  If the total fines
            a user owes reaches or exceeds "fine_level" on or befre "age"
            and the fines were created at "location", the user will be
            included in the return set/,

        params   => [
            {    name => 'auth',
                desc => 'The authentication token',
                type => 'string' },

            {    name => 'age',
                desc => q/Number of days back to check/,
                type => q/number/,
            },

            {    name => 'fine_level',
                desc => q/The fine threshold at which users will be included in the search results /,
                type => q/number/,
            },
            {    name => 'location',
                desc => q/The short-name of the orginization unit (library) at which the fines were created.
                            If a selected location has 'child' locations (e.g. a library region), the
                            child locations will be included in the search/,
                type => q/string/,
            },
        ],

          'return' => {
            desc        => q/An array of user information objects.
                        usr : Array of user information objects containing id, dob, profile, and groups
                        threshold_amount : The total amount the patron owes that is at least as old
                            as the fine "age" and whose transaction was created at the searched location
                        last_pertinent_billing : The time of the last billing that relates to this query
                        /,
            type        => 'array',
            example    => {
                usr    => {
                    id            => 'id',
                    dob        => '1970-01-01',
                    profile    => 'Patron',
                    groups    => [ 'Patron', 'Staff' ],
                },
                threshold_amount => 99,
            }
        }
    }
);


sub users_of_interest {
    my( $self, $conn, $auth, $age, $fine_level, $location ) = @_;

    return OpenILS::Event->new('BAD_PARAMS')
        unless ($auth and $age and $location);

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $org = $e->search_actor_org_unit({shortname => $location})
        or return $e->event; $org = $org->[0];

    # they need global perms to view users so no org is provided
    return $e->event unless $e->allowed('VIEW_USER');

    my $data = [];

    my $ses = OpenSRF::AppSession->create('open-ils.storage');

    my $start = time;
    my $req = $ses->request(
        'open-ils.storage.money.collections.users_of_interest',
        $age, $fine_level, $location);

    # let the client know we're still here
    $conn->status( new OpenSRF::DomainObject::oilsContinueStatus );

    return process_users_of_interest_results(
        $self, $conn, $e, $req, $start, $age, $fine_level, $location);
}


__PACKAGE__->register_method(
    method    => 'users_of_interest_warning_penalty',
    api_name  => 'open-ils.collections.users_of_interest.warning_penalty.retrieve',
    api_level => 1,
    argc      => 4,
    stream    => 1,
    signature => {
        desc     => q/
            Returns an array of user information objects for users that have the
            PATRON_EXCEEDS_COLLECTIONS_WARNING penalty applied,
            based on the search criteria provided./,

        params   => [
            {    name => 'auth',
                desc => 'The authentication token',
                type => 'string'
            }, {
                name => 'location',
                desc => q/The short-name of the orginization unit (library) at which the penalty is applied.
                            If a selected location has 'child' locations (e.g. a library region), the
                            child locations will be included in the search/,
                type => q/string/,
            }, {
                name => 'min_age',
                desc => q/Optional.  Minimum age of the penalty application/,
                type => q/interval, e.g "30 days"/,
            }, {
                name => 'max_age',
                desc => q/Optional.  Maximum age of the penalty application/,
                type => q/interval, e.g "90 days"/,
            }
        ],

          'return' => {
            desc        => q/An array of user information objects.
                        usr : Array of user information objects containing id, dob, profile, and groups
                        threshold_amount : The total amount the patron owes that is at least as old
                            as the fine "age" and whose transaction was created at the searched location
                        last_pertinent_billing : The time of the last billing that relates to this query
                        /,
            type        => 'array',
            example    => {
                usr    => {
                    id            => 'id',
                    dob        => '1970-01-01',
                    profile    => 'Patron',
                    groups    => [ 'Patron', 'Staff' ],
                },
                threshold_amount => 99, # TODO: still needed?
            }
        }
    }
);



sub users_of_interest_warning_penalty {
    my( $self, $conn, $auth, $location, $min_age, $max_age ) = @_;

    return OpenILS::Event->new('BAD_PARAMS') unless ($auth and $location);

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $org = $e->search_actor_org_unit({shortname => $location})
        or return $e->event; $org = $org->[0];

    # they need global perms to view users so no org is provided
    return $e->event unless $e->allowed('VIEW_USER');

    my $org_ids = $e->json_query({from => ['actor.org_unit_full_path', $org->id]});

    my $ses = OpenSRF::AppSession->create('open-ils.cstore');

    # max age == oldest
    my $max_set_date = DateTime->now->subtract(seconds =>
        interval_to_seconds($max_age))->strftime( '%F %T%z' ) if $max_age;
    my $min_set_date = DateTime->now->subtract(seconds =>
        interval_to_seconds($min_age))->strftime( '%F %T%z' ) if $min_age;

    my $start = time;
    my $query = {
        select => {ausp => ['usr']},
        from => {
            ausp => {
                au => {
                    join => {
                        aus => {
                            type => 'left',
                            filter => {name => 'circ.collections.exempt'}
                        }
                    }
                }
            }
        },
        where => {
            '+ausp' => {
                standing_penalty => 4, # PATRON_EXCEEDS_COLLECTIONS_WARNING
                org_unit => [ map {$_->{id}} @$org_ids ],
                '-or' => [
                    {stop_date => undef},
                    {stop_date => {'>' => 'now'}}
                ]
            },
            # We are only interested in users that do not have the
            # circ.collections.exempt setting applied
            '+aus' => {value => undef}
        }
    };

    $query->{where}->{'-and'} = [] if $max_set_date or $min_set_date;
    push(@{$query->{where}->{'-and'}}, {set_date => {'>' => $max_set_date}}) if $max_set_date;
    push(@{$query->{where}->{'-and'}}, {set_date => {'<' => $min_set_date}}) if $min_set_date;

    my $req = $ses->request('open-ils.cstore.json_query', $query);

    # let the client know we're still here
    $conn->status( new OpenSRF::DomainObject::oilsContinueStatus );

    return process_users_of_interest_results(
        $self, $conn, $e, $req, $start, $min_age, '', $location, $max_age);
}




sub process_users_of_interest_results {
    my($self, $conn, $e, $req, $starttime, @params) = @_;

   my $total;
   while( my $resp = $req->recv(timeout => 7200) ) {

        return $req->failed if $req->failed;
        my $hash = $resp->content;
        next unless $hash;

        unless($total) {
            $total = time - $starttime;
            $logger->info("collections: request (@params) took $total seconds");
        }

        my $u = $e->retrieve_actor_user(
            [
                $hash->{usr},
                {
                    flesh                => 1,
                    flesh_fields    => {au => ["groups","profile", "card"]},
                }
            ]
        ) or return $e->event;

        $hash->{usr} = {
            id            => $u->id,
            dob        => $u->dob,
            profile    => $u->profile->name,
            barcode    => $u->card->barcode,
            groups    => [ map { $_->name } @{$u->groups} ],
        };

        $conn->respond($hash);
    }

    return undef;
}


__PACKAGE__->register_method(
    method    => 'users_owing_money',
    api_name  => 'open-ils.collections.users_owing_money.retrieve',
    api_level => 1,
    argc      => 5,
    stream    => 1,
    signature => {
        desc     => q/
            Returns an array of users that owe money during
            the given time frame at the location (or child locations)
            provided/,

        params   => [
            {    name => 'auth',
                desc => 'The authentication token',
                type => 'string' },

            {    name => 'start_date',
                desc => 'The start of the time interval to check',
                type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
            },

            {    name => 'end_date',
                desc => q/Then end date of the time interval to check/,
                type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
            },
            {    name => 'fine_level',
                desc => q/The fine threshold at which users will be included in the search results /,
                type => q/number/,
            },
            {    name => 'locations',
                desc => q/  A list of one or more org-unit short names.
                            If a selected location has 'child' locations (e.g. a library region), the
                            child locations will be included in the search/,
                type => q'string',
            },
        ],
          'return' => {
            desc        => q/An array of user information objects/,
            type        => 'array',
        }
    }
);


sub users_owing_money {
    my( $self, $conn, $auth, $start_date, $end_date, $fine_level, @locations ) = @_;

    return OpenILS::Event->new('BAD_PARAMS')
        unless ($auth and $start_date and $end_date and @locations);

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    # they need global perms to view users so no org is provided
    return $e->event unless $e->allowed('VIEW_USER');

    my $data = [];

    my $ses = OpenSRF::AppSession->create('open-ils.storage');

    my $start = time;
    my $req = $ses->request(
        'open-ils.storage.money.collections.users_owing_money',
        $start_date, $end_date, $fine_level, @locations);

    # let the client know we're still here
    $conn->status( new OpenSRF::DomainObject::oilsContinueStatus );

    return process_users_of_interest_results(
        $self, $conn, $e, $req, $start, $start_date, $end_date, $fine_level, @locations);
}



__PACKAGE__->register_method(
    method    => 'users_with_activity',
    api_name  => 'open-ils.collections.users_with_activity.retrieve',
    api_level => 1,
    argc      => 4,
    stream    => 1,
    signature => {
        desc     => q/
            Returns an array of users that are already in collections
            and had any type of billing or payment activity within
            the given time frame at the location (or child locations)
            provided/,

        params   => [
            {    name => 'auth',
                desc => 'The authentication token',
                type => 'string' },

            {    name => 'start_date',
                desc => 'The start of the time interval to check',
                type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
            },

            {    name => 'end_date',
                desc => q/Then end date of the time interval to check/,
                type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
            },
            {    name => 'location',
                desc => q/The short-name of the orginization unit (library) at which the activity occurred.
                            If a selected location has 'child' locations (e.g. a library region), the
                            child locations will be included in the search/,
                type => q'string',
            },
        ],

          'return' => {
            desc        => q/An array of user information objects/,
            type        => 'array',
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

    my $ses = OpenSRF::AppSession->create('open-ils.storage');

    my $start = time;
    my $req = $ses->request(
        'open-ils.storage.money.collections.users_with_activity.atomic',
        $start_date, $end_date, $location);

    $conn->status( new OpenSRF::DomainObject::oilsContinueStatus );

    my $total;
    while( my $resp = $req->recv(timeout => 7200) ) {

        unless($total) {
            $total = time - $start;
            $logger->info("collections: users_with_activity search ".
                "($start_date, $end_date, $location) took $total seconds");
        }

        return $req->failed if $req->failed;
        $conn->respond($resp->content);
   }

    return undef;
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
            {    name => 'auth',
                desc => 'The authentication token',
                type => 'string' },

            {    name => 'user_id',
                desc => 'The id of the user to plact into collections',
                type => 'number',
            },

            {    name => 'location',
                desc => q/The short-name of the orginization unit (library)
                    for which the user is being placed in collections/,
                type => q'string',
            },
            {    name => 'fee_amount',
                desc => q/
                    The amount of money that a patron should be fined.
                    If this field is empty, no fine is created.
                /,
                type => 'string',
            },
            {    name => 'fee_note',
                desc => q/
                    Custom note that is added to the the billing.
                    This field is not required.
                    Note: fee_note is not the billing_type.  Billing_type type is
                    decided by the system. (e.g. "fee for collections").
                    fee_note is purely used for any additional needed information
                    and is only visible to staff.
                /,
                type => 'string',
            },
        ],

          'return' => {
            desc        => q/A SUCCESS event on success, error event on failure/,
            type        => 'object',
        }
    }
);
sub put_into_collections {
    my( $self, $conn, $auth, $user_id, $location, $fee_amount, $fee_note ) = @_;

    return OpenILS::Event->new('BAD_PARAMS')
        unless ($auth and $user_id and $location);

    my $e = new_editor(authtoken => $auth, xact =>1);
    return $e->event unless $e->checkauth;

    my $org = $e->search_actor_org_unit({shortname => $location});
    return $e->event unless $org = $org->[0];
    return $e->event unless $e->allowed('money.collections_tracker.create', $org->id);

    my $existing = $e->search_money_collections_tracker(
        {
            location        => $org->id,
            usr            => $user_id,
            collector    => $e->requestor->id
        },
        {idlist => 1}
    );

    return OpenILS::Event->new('MONEY_COLLECTIONS_TRACKER_EXISTS') if @$existing;

    $logger->info("collect: user ".$e->requestor->id.
        " putting user $user_id into collections for $location");

    my $tracker = Fieldmapper::money::collections_tracker->new;

    $tracker->usr($user_id);
    $tracker->collector($e->requestor->id);
    $tracker->location($org->id);
    $tracker->enter_time('now');

    $e->create_money_collections_tracker($tracker)
        or return $e->event;

    if( $fee_amount ) {
        my $evt = add_collections_fee($e, $user_id, $org, $fee_amount, $fee_note );
        return $evt if $evt;
    }

    $e->commit;

    my $pen = Fieldmapper::actor::user_standing_penalty->new;
    $pen->org_unit($org->id);
    $pen->usr($user_id);
    $pen->standing_penalty(30); # PATRON_IN_COLLECTIONS
    $pen->staff($e->requestor->id);
    $pen->note($fee_note) if $fee_note;
    $U->simplereq('open-ils.actor', 'open-ils.actor.user.penalty.apply', $auth, $pen);

    return OpenILS::Event->new('SUCCESS');
}

sub add_collections_fee {
    my( $e, $patron_id, $org, $fee_amount, $fee_note ) = @_;

    $fee_note ||= "";

    $logger->info("collect: adding fee to user $patron_id : $fee_amount : $fee_note");

    my $xact = Fieldmapper::money::grocery->new;
    $xact->usr($patron_id);
    $xact->xact_start('now');
    $xact->billing_location($org->id);

    $xact = $e->create_money_grocery($xact) or return $e->event;

    my $bill = Fieldmapper::money::billing->new;
    $bill->note($fee_note);
    $bill->xact($xact->id);
    $bill->btype(2);
    $bill->billing_type(OILS_BILLING_TYPE_COLLECTION_FEE);
    $bill->amount($fee_amount);

    $e->create_money_billing($bill) or return $e->event;
    return undef;
}




__PACKAGE__->register_method(
    method        => 'remove_from_collections',
    api_name        => 'open-ils.collections.remove_from_collections',
    signature    => q/
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
            {    name => 'auth',
                desc => 'The authentication token',
                type => 'string' },

            {    name => 'user_id',
                desc => 'The id of the user to plact into collections',
                type => 'number',
            },

            {    name => 'location',
                desc => q/The short-name of the orginization unit (library)
                    for which the user is being removed from collections/,
                type => q'string',
            },
        ],

          'return' => {
            desc        => q/A SUCCESS event on success, error event on failure/,
            type        => 'object',
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


#__PACKAGE__->register_method(
#    method        => 'transaction_details',
#    api_name        => 'open-ils.collections.user_transaction_details.retrieve',
#    signature    => q/
#    /
#);


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
            {    name => 'auth',
                desc => 'The authentication token',
                type => 'string' },

            {    name => 'start_date',
                desc => 'The start of the time interval to check',
                type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
            },

            {    name => 'end_date',
                desc => q/Then end date of the time interval to check/,
                type => q/string (ISO 8601 timestamp.  E.g. 2006-06-24, 1994-11-05T08:15:30-05:00 /,
            },
            {    name => 'location',
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
            desc        => q/A list of objects.  Object keys include:
                usr :
                transactions : An object with keys :
                    circulations : Fleshed circulation objects
                    grocery : Fleshed 'grocery' transaction objects
                /,
            type        => 'object'
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
    $org = $U->find_org($U->get_org_tree(), $org->id);

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
            circulations    =>
                fetch_circ_xacts($e, $uid, $org, $start_date, $end_date),
            grocery            =>
                fetch_grocery_xacts($e, $uid, $org, $start_date, $end_date),
            reservations    =>
                fetch_reservation_xacts($e, $uid, $org, $start_date, $end_date)
        };

        # for each transaction, flesh the workstatoin on any attached payment
        # and make the payment object a real object (e.g. cash payment),
        # not just a generic payment object
        for my $xact (
            @{$blob->{transactions}->{circulations}},
            @{$blob->{transactions}->{reservations}},
            @{$blob->{transactions}->{grocery}} ) {

            my $ps;
            if( $ps = $xact->payments and @$ps ) {
                my @fleshed; my $evt;
                for my $p (@$ps) {
                    ($p, $evt) = flesh_payment($e,$p);
                    return $evt if $evt;
                    push(@fleshed, $p);
                }
                $xact->payments(\@fleshed);
            }
        }

        push( @data, $blob );
    }

    return \@data;
}

__PACKAGE__->register_method(
    method    => 'user_balance_summary',
    api_name  => 'open-ils.collections.user_balance_summary.generate',
    api_level => 1,
    stream    => 1,
    argc      => 2,
    signature => {
        desc     => q/Collect balance information for users in collections.  By default,
                        only the total balance owed is calculated.  Use the "include_xacts"
                        param to include per-transaction summaries as well./,
        params   => [
            {   name => 'auth',
                desc => 'The authentication token',
                type => 'string' },
            {   name => 'args',
                desc => q/
                    Hash of API arguments.  Options include:
                    location   -- org unit shortname
                    start_date -- ISO 8601 date. limit to patrons added to collections on or after this date (optional).
                    end_date   -- ISO 8601 date. limit to patrons added to collections on or before this date (optional).
                    user_id    -- retrieve information only for this user (takes preference over
                        start and end_date).  May be a single ID or list of IDs. (optional).
                    include_xacts -- If true, include a summary object per transaction in addition to the full balance owed
                /,
                type => q/hash/
            },
        ],
        'return' => {
            desc => q/
                The file name prefix of the file to be created.
                The file name format will be:
                user_balance_YYYY-MM-DD_${location}_${start_date}_${end_date}_${user_id}.[tmp|xml]
                Optional params not provided by the caller will not be part of the file name.
                Examples:
                    user_balance_BR1_2012-05-25_2012-01-01_2012-12-31 # start and end dates
                    user_balance_BR2_2012-05-25_153244 # user id only.
                In-process files will have a .tmp suffix
                Completed files will have a .xml suffix
            /,
            type => 'string'
        }
    }
);

sub user_balance_summary {
    my ($self, $client, $auth, $args) = @_;

    my $location = $$args{location};
    my $start_date = $$args{start_date};
    my $end_date = $$args{end_date};
    my $user_id = $$args{user_id};

    return OpenILS::Event->new('BAD_PARAMS')
        unless $auth and $location and
        ($start_date or $end_date or $user_id);

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $org = $e->search_actor_org_unit({shortname => $location})->[0]
        or return $e->event;

    # they need global perms to view users so no org is provided
    return $e->event unless $e->allowed('VIEW_USER', $org->id);

    my $org_list = $U->get_org_descendants($org->id);

    my ($evt, $file_prefix, $file_name, $FILE) = setup_batch_file('user_balance', $args);

    $client->respond_complete($evt || $file_prefix);

    my @user_list;

    if ($user_id) {
        @user_list = (ref $user_id eq 'ARRAY') ? @$user_id : ($user_id);

    } else {
        # collect the users from the tracker table based on the provided filters

        my $query = {
            select => {mct => ['usr']},
            from => 'mct',
            where => {location => $org_list}
        };

        $query->{where}->{enter_time} = {'>=' => $start_date};
        $query->{where}->{enter_time} = {'<=' => $end_date};
        my $users = $e->json_query($query);
        @user_list = map {$_->{usr}} @$users;
    }

    print $FILE "<Collections>\n"; # append to the document as we have data

    for my $user_id (@user_list) {
        my $user_doc = XML::LibXML::Document->new;
        my $root = $user_doc->createElement('User');
        $user_doc->setDocumentElement($root);

        my $user = $e->retrieve_actor_user([
            $user_id, {
            flesh        => 1,
            flesh_fields => {
                au => [
                    'card',
                    'cards',
                    'standing_penalties',
                    'addresses',
                    'billing_address',
                    'mailing_address',
                    'stat_cat_entries'
                ]
            }}
        ]);

        my $au_doc = $user->toXML({no_virt => 1, skip_fields => {au => ['passwd']}});
        my $au_node = $au_doc->documentElement;
        $user_doc->adoptNode($au_node);
        $root->appendChild($au_node);

        my $circ_ids = $e->search_action_circulation(
            {usr => $user_id, circ_lib => $org_list, xact_finish => undef},
            {idlist => 1}
        );

        my $groc_ids = $e->search_money_grocery(
            {usr => $user_id, billing_location => $org_list, xact_finish => undef},
            {idlist => 1}
        );

        my $res_ids = $e->search_booking_reservation(
            {usr => $user_id, pickup_lib => $org_list, xact_finish => undef},
            {idlist => 1}
        );

        # get the sum owed an all transactions
        my $balance = $e->json_query({
            select => {mbts => [
                {   column => 'balance_owed',
                    transform => 'sum',
                    aggregate => 1
                }
            ]},
            from => 'mbts',
            where => {id => [@$circ_ids, @$groc_ids, @$res_ids]}
        })->[0];

        $balance = $balance ? $balance->{balance_owed} : '0';

        my $xacts_node = $user_doc->createElement('Transactions');
        my $balance_node = $user_doc->createElement('BalanceOwed');
        $balance_node->appendChild($user_doc->createTextNode($balance));
        $xacts_node->appendChild($balance_node);
        $root->appendChild($xacts_node);

        if ($$args{include_xacts}) {
            my $xacts = $e->search_money_billable_transaction_summary(
                {id => [@$circ_ids, @$groc_ids, @$res_ids]},
                {substream => 1}
            );

            for my $xact (@$xacts) {
                my $xact_node = $xact->toXML({no_virt => 1})->documentElement;
                $user_doc->adoptNode($xact_node);
                $xacts_node->appendChild($xact_node);
            }
        }

        print $FILE $user_doc->documentElement->toString(1) . "\n";
    }

    print $FILE "\n</Collections>";
    close($FILE);

    (my $complete_file = $file_name) =~ s|.tmp$|.xml|og;

    unless (move($file_name, $complete_file)) {
        $logger->error("collections: unable to move ".
            "user_balance file $file_name => $complete_file : $@");
    }

    return undef;
}

sub setup_batch_file {
    my $prefix = shift;
    my $args = shift;
    my $location = $$args{location};
    my $start_date = $$args{start_date};
    my $end_date = $$args{end_date};
    my $user_id = $$args{user_id};

    my $conf = OpenSRF::Utils::SettingsClient->new;
    my $dir_name = $conf->config_value(apps =>
        'open-ils.collections' => app_settings => 'batch_file_dir');

    if (!$dir_name) {
        $logger->error("collections: no batch_file_dir directory configured");
        return OpenILS::Event->new('COLLECTIONS_FILE_ERROR');
    }

    unless (-e $dir_name) {
        eval { mkpath($dir_name); };
        if ($@) {
            $logger->error("collections: unable to create batch_file_dir directory $dir_name : $@");
            return OpenILS::Event->new('COLLECTIONS_FILE_ERROR');
        }
    }

    my $file_prefix = "${prefix}_" . DateTime->now->strftime('%F') . "_$location";
    $file_prefix .= "_$start_date" if $start_date;
    $file_prefix .= "_$end_date" if $end_date;
    $file_prefix .= "_$user_id" if $user_id;

    my $FILE;
    my $file_name = File::Spec->catfile($dir_name, "$file_prefix.tmp");

    unless (open($FILE, '>', $file_name)) {
        $logger->error("collections: unable to open user_balance_summary file $file_name : $@");
        return OpenILS::Event->new('COLLECTIONS_FILE_ERROR');
    }

    return (undef, $file_prefix, $file_name, $FILE);
}

sub flesh_payment {
    my $e = shift;
    my $p = shift;
    my $type = $p->payment_type;
    $logger->debug("collect: fleshing workstation on payment $type : ".$p->id);
    my $meth = "retrieve_money_$type";
    $p = $e->$meth($p->id) or return (undef, $e->event);
    try {
        $p->payment_type($type);
        $p->cash_drawer(
            $e->retrieve_actor_workstation(
                [
                    $p->cash_drawer,
                    {
                        flesh => 1,
                        flesh_fields => { aws => [ 'owning_lib' ] }
                    }
                ]
            )
        );
    } catch Error with {};
    return ($p);
}


# --------------------------------------------------------------
# Collect all open circs for the user
# For each circ, see if any billings or payments were created
# during the given time period.
# --------------------------------------------------------------
sub fetch_circ_xacts {
    my $e                = shift;
    my $uid            = shift;
    my $org            = shift;
    my $start_date = shift;
    my $end_date    = shift;

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
                            usr            => $uid,
                            circ_lib        => $n->id,
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
                            circ => [ "billings", "payments", "circ_lib", 'target_copy' ]
                        }
                    }
                ]
            )
        );
    }

    return \@data;
}

sub fetch_grocery_xacts {
    my $e                = shift;
    my $uid            = shift;
    my $org            = shift;
    my $start_date = shift;
    my $end_date    = shift;

    my @xacts;
    $U->walk_org_tree( $org,
        sub {
            my $n = shift;
            $logger->debug("collect: searching for open grocery xacts at " . $n->shortname);
            push( @xacts,
                @{
                    $e->search_money_grocery(
                        {
                            usr                    => $uid,
                            billing_location    => $n->id,
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

sub fetch_reservation_xacts {
    my $e                = shift;
    my $uid            = shift;
    my $org            = shift;
    my $start_date = shift;
    my $end_date    = shift;

    my @xacts;
    $U->walk_org_tree( $org,
        sub {
            my $n = shift;
            $logger->debug("collect: searching for open grocery xacts at " . $n->shortname);
            push( @xacts,
                @{
                    $e->search_booking_reservation(
                        {
                            usr                    => $uid,
                            pickup_lib          => $n->id,
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
            $e->retrieve_booking_reservation(
                [
                    $id,
                    {
                        flesh => 1,
                        flesh_fields => {
                            bresv => [ "billings", "payments", "pickup_lib" ] }
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
                xact            => $id,
                billing_ts    => { between => [ $start_date, $end_date ] },
            },
            {idlist =>1}
        );

        my $payments = [];

        if( !@$bills ) {

            # see if any payments were created in the given range
            $payments = $e->search_money_payment (
                {
                    xact            => $id,
                    payment_ts    => { between => [ $start_date, $end_date ] },
                },
                {idlist =>1}
            );
        }


        push( @active, $id ) if @$bills or @$payments;
    }

    return \@active;
}


__PACKAGE__->register_method(
    method    => 'create_user_note',
    api_name  => 'open-ils.collections.patron_note.create',
    api_level => 1,
    argc      => 4,
    signature => {
        desc     => q/ Adds a note to a patron's account /,
        params   => [
            {    name => 'auth',
                desc => 'The authentication token',
                type => 'string' },

            {    name => 'user_barcode',
                desc => q/The patron's barcode/,
                type => q/string/,
            },
            {    name => 'title',
                desc => q/The title of the note/,
                type => q/string/,
            },

            {    name => 'note',
                desc => q/The text of the note/,
                type => q/string/,
            },
        ],

          'return' => {
            desc        => q/
                Returns SUCCESS event on success, error event otherwise.
                /,
            type        => 'object'
        }
    }
);


sub create_user_note {
    my( $self, $conn, $auth, $user_barcode, $title, $note_txt ) = @_;

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('UPDATE_USER'); # XXX Makre more specific perm for this

    return $e->event unless
        my $card = $e->search_actor_card({barcode=>$user_barcode})->[0];

    my $note = Fieldmapper::actor::usr_note->new;
    $note->usr($card->usr);
    $note->title($title);
    $note->creator($e->requestor->id);
    $note->create_date('now');
    $note->pub('f');
    $note->value($note_txt);

    $e->create_actor_usr_note($note) or return $e->event;
    $e->commit;
    return OpenILS::Event->new('SUCCESS');
}



1;
