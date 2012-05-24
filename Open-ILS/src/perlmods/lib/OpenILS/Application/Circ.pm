package OpenILS::Application::Circ;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenILS::Application::Circ::Circulate;
use OpenILS::Application::Circ::Survey;
use OpenILS::Application::Circ::StatCat;
use OpenILS::Application::Circ::Holds;
use OpenILS::Application::Circ::HoldNotify;
use OpenILS::Application::Circ::CreditCard;
use OpenILS::Application::Circ::Money;
use OpenILS::Application::Circ::NonCat;
use OpenILS::Application::Circ::CopyLocations;
use OpenILS::Application::Circ::CircCommon;

use DateTime;
use DateTime::Format::ISO8601;

use OpenILS::Application::AppUtils;

use OpenSRF::Utils qw/:datetime/;
use OpenSRF::AppSession;
use OpenILS::Utils::ModsParser;
use OpenILS::Event;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::Editor;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;
use OpenILS::Application::Cat::AssetCommon;

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;

my $holdcode    = "OpenILS::Application::Circ::Holds";

# ------------------------------------------------------------------------
# Top level Circ package;
# ------------------------------------------------------------------------

sub initialize {
	my $self = shift;
	OpenILS::Application::Circ::Circulate->initialize();
}


__PACKAGE__->register_method(
	method => 'retrieve_circ',
	authoritative	=> 1,
	api_name	=> 'open-ils.circ.retrieve',
	signature => q/
		Retrieve a circ object by id
		@param authtoken Login session key
		@pararm circid The id of the circ object
	/
);
sub retrieve_circ {
	my( $s, $c, $a, $i ) = @_;
	my $e = new_editor(authtoken => $a);
	return $e->event unless $e->checkauth;
	my $circ = $e->retrieve_action_circulation($i) or return $e->event;
	if( $e->requestor->id ne $circ->usr ) {
		return $e->event unless $e->allowed('VIEW_CIRCULATIONS');
	}
	return $circ;
}


__PACKAGE__->register_method(
	method => 'fetch_circ_mods',
	api_name => 'open-ils.circ.circ_modifier.retrieve.all');
sub fetch_circ_mods {
    my($self, $conn, $args) = @_;
    my $mods = new_editor()->retrieve_all_config_circ_modifier;
    return [ map {$_->code} @$mods ] unless $$args{full};
    return $mods;
}

__PACKAGE__->register_method(
	method => 'fetch_bill_types',
	api_name => 'open-ils.circ.billing_type.retrieve.all');
sub fetch_bill_types {
	my $conf = OpenSRF::Utils::SettingsClient->new;
	return $conf->config_value(
		'apps', 'open-ils.circ', 'app_settings', 'billing_types', 'type' );
}


__PACKAGE__->register_method(
    method => 'ranged_billing_types',
    api_name => 'open-ils.circ.billing_type.ranged.retrieve.all');

sub ranged_billing_types {
    my($self, $conn, $auth, $org_id, $depth) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_BILLING_TYPE', $org_id);
    return $e->search_config_billing_type(
        {owner => $U->get_org_full_path($org_id, $depth)});
}



# ------------------------------------------------------------------------
# Returns an array of {circ, record} hashes checked out by the user.
# ------------------------------------------------------------------------
__PACKAGE__->register_method(
	method	=> "checkouts_by_user",
	api_name	=> "open-ils.circ.actor.user.checked_out",
    stream => 1,
	NOTES		=> <<"	NOTES");
	Returns a list of open circulations as a pile of objects.  Each object
	contains the relevant copy, circ, and record
	NOTES

sub checkouts_by_user {
	my($self, $client, $auth, $user_id) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;

	my $circ_ids = $e->search_action_circulation(
        {   usr => $user_id,
            checkin_time => undef,
            '-or' => [
                {stop_fines => undef},
                {stop_fines => ['MAXFINES','LONGOVERDUE']}
            ]
        },
        {idlist => 1}
    );

    for my $id (@$circ_ids) {
        my $circ = $e->retrieve_action_circulation([
            $id,
            {   flesh => 3,
                flesh_fields => {
                    circ => ['target_copy'],
                    acp => ['call_number'],
                    acn => ['record']
                }
            }
        ]);

        # un-flesh for consistency
        my $c = $circ->target_copy;
        $circ->target_copy($c->id);

        my $cn = $c->call_number;
        $c->call_number($cn->id);

        my $t = $cn->record;
        $cn->record($t->id);

        $client->respond(
            {   circ => $circ,
                copy => $c,
                record => $U->record_to_mvr($t)
            }
        );
    }

    return undef;
}



__PACKAGE__->register_method(
	method	=> "checkouts_by_user_slim",
	api_name	=> "open-ils.circ.actor.user.checked_out.slim",
	NOTES		=> <<"	NOTES");
	Returns a list of open circulation objects
	NOTES

# DEPRECAT ME?? XXX
sub checkouts_by_user_slim {
	my( $self, $client, $user_session, $user_id ) = @_;

	my( $requestor, $target, $copy, $record, $evt );

	( $requestor, $target, $evt ) = 
		$apputils->checkses_requestor( $user_session, $user_id, 'VIEW_CIRCULATIONS');
	return $evt if $evt;

	$logger->debug( 'User ' . $requestor->id . 
		" retrieving checked out items for user " . $target->id );

	# XXX Make the call correct..
	return $apputils->simplereq(
		'open-ils.cstore',
		"open-ils.cstore.direct.action.open_circulation.search.atomic", 
		{ usr => $target->id, checkin_time => undef } );
#		{ usr => $target->id } );
}


__PACKAGE__->register_method(
	method	=> "checkouts_by_user_opac",
	api_name	=> "open-ils.circ.actor.user.checked_out.opac",);

# XXX Deprecate Me
sub checkouts_by_user_opac {
	my( $self, $client, $auth, $user_id ) = @_;

	my $e = OpenILS::Utils::Editor->new( authtoken => $auth );
	return $e->event unless $e->checkauth;
	$user_id ||= $e->requestor->id;
	return $e->event unless 
		my $patron = $e->retrieve_actor_user($user_id);

	my $data;
	my $search = {usr => $user_id, stop_fines => undef};

	if( $user_id ne $e->requestor->id ) {
		$data = $e->search_action_circulation(
			$search, {checkperm=>1, permorg=>$patron->home_ou})
			or return $e->event;

	} else {
		$data = $e->search_action_circulation($search);
	}

	return $data;
}


__PACKAGE__->register_method(
	method	=> "title_from_transaction",
	api_name	=> "open-ils.circ.circ_transaction.find_title",
	NOTES		=> <<"	NOTES");
	Returns a mods object for the title that is linked to from the 
	copy from the hold that created the given transaction
	NOTES

sub title_from_transaction {
	my( $self, $client, $login_session, $transactionid ) = @_;

	my( $user, $circ, $title, $evt );

	( $user, $evt ) = $apputils->checkses( $login_session );
	return $evt if $evt;

	( $circ, $evt ) = $apputils->fetch_circulation($transactionid);
	return $evt if $evt;
	
	($title, $evt) = $apputils->fetch_record_by_copy($circ->target_copy);
	return $evt if $evt;

	return $apputils->record_to_mvr($title);
}

__PACKAGE__->register_method(
	method	=> "staff_age_to_lost",
	api_name	=> "open-ils.circ.circulation.age_to_lost",
    stream => 1,
	signature	=> q/
        This fires a circ.staff_age_to_lost Action-Trigger event against all
        overdue circulations in scope of the specified context library and
        user profile, which effectively marks the associated items as Lost.
        This is likely to be done at the end of a semester in an academic
        library, etc.
		@param auth
		@param args : circ_lib, user_profile
	/
);

sub staff_age_to_lost {
    my( $self, $conn, $auth, $args ) = @_;

    my $orgs = $U->get_org_descendants($args->{'circ_lib'});
    my $profiles = $U->fetch_permission_group_descendants($args->{'user_profile'});

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');

    my $method = 'open-ils.trigger.passive.event.autocreate.batch';
    my $hook = 'circ.staff_age_to_lost';
    my $context_org = 'circ_lib';
    my $opt_granularity = undef;
    my $filter = { 
        "checkin_time" => undef,
        "due_date" => { "<" => "now" }, 
        "-or" => [ 
            { "stop_fines"  => ["MAXFINES", "LONGOVERDUE"] }, # FIXME: CLAIMSRETURNED also?
            { "stop_fines"  => undef }
        ],
        "-and" => [
            {"-exists" => {
                "select" => {"au" => ["id"]},
                "from"   => "au",
                "where"  => {
                    "profile" => $profiles,
                    "id" => { "=" => {"+circ" => "usr"} }
                }
            }},
            {"-exists" => {
                "select" => {"aou" => ["id"]},
                "from"   => "aou",
                "where"  => {
                    "-and" => [
                        {"id" => { "=" => {"+circ" => "circ_lib"} }},
                        {"id" => $orgs}
                    ]
                }
            }}
        ]
    };
    my $req_timeout = 10800;
    my $chunk_size = 100;
    my $progress = 1;

    my $req = $ses->request($method, $hook, $context_org, $filter, $opt_granularity);
    my @event_ids; my @chunked_ids;
    while (my $resp = $req->recv(timeout => $req_timeout)) {
        push(@event_ids, $resp->content);
        push(@chunked_ids, $resp->content);
        if (scalar(@chunked_ids) > $chunk_size) {
            $conn->respond({'progress'=>$progress++}); # 'event_ids'=>@chunked_ids
            @chunked_ids = ();
        }
    }
    if (scalar(@chunked_ids) > 0) {
        $conn->respond({'progress'=>$progress++}); # 'event_ids'=>@chunked_ids
    }

    if(@event_ids) {
        $logger->info("staff_age_to_lost: created ".scalar(@event_ids)." events for circ.staff_age_to_lost");
        $conn->respond_complete({'total_progress'=>$progress-1,'created'=>scalar(@event_ids)});
    } elsif($req->complete) {
        $logger->info("staff_age_to_lost: no events to create for circ.staff_age_to_lost");
        $conn->respond_complete({'total_progress'=>$progress-1,'created'=>0});
    } else {
        $logger->warn("staff_age_to_lost: timeout occurred during event creation for circ.staff_age_to_lost");
        $conn->respond_complete({'total_progress'=>$progress-1,'error'=>'timeout'});
    }

    return undef;
}


__PACKAGE__->register_method(
	method	=> "new_set_circ_lost",
	api_name	=> "open-ils.circ.circulation.set_lost",
	signature	=> q/
        Sets the copy and related open circulation to lost
		@param auth
		@param args : barcode
	/
);


# ---------------------------------------------------------------------
# Sets a circulation to lost.  updates copy status to lost
# applies copy and/or prcoessing fees depending on org settings
# ---------------------------------------------------------------------
sub new_set_circ_lost {
    my( $self, $conn, $auth, $args ) = @_;

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    my $copy = $e->search_asset_copy({barcode=>$$args{barcode}, deleted=>'f'})->[0]
        or return $e->die_event;

    my $evt = OpenILS::Application::Cat::AssetCommon->set_item_lost($e, $copy->id);
    return $evt if $evt;

    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
	method	=> "set_circ_claims_returned",
	api_name	=> "open-ils.circ.circulation.set_claims_returned",
	signature => {
        desc => q/Sets the circ for a given item as claims returned
                If a backdate is provided, overdue fines will be voided
                back to the backdate/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Arguments, including "barcode" and optional "backdate"', type => 'object'}
        ],
        return => {desc => q/1 on success, failure event on error, and 
            PATRON_EXCEEDS_CLAIMS_RETURN_COUNT if the patron exceeds the 
            configured claims return maximum/}
    }
);

__PACKAGE__->register_method(
	method	=> "set_circ_claims_returned",
	api_name	=> "open-ils.circ.circulation.set_claims_returned.override",
	signature => {
        desc => q/This adds support for overrideing the configured max 
                claims returned amount. 
                @see open-ils.circ.circulation.set_claims_returned./,
    }
);

sub set_circ_claims_returned {
    my( $self, $conn, $auth, $args, $oargs ) = @_;

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    $oargs = { all => 1 } unless defined $oargs;

    my $barcode = $$args{barcode};
    my $backdate = $$args{backdate};

    my $copy = $e->search_asset_copy({barcode=>$barcode, deleted=>'f'})->[0] 
        or return $e->die_event;

    my $circ = $e->search_action_circulation(
        {checkin_time => undef, target_copy => $copy->id})->[0]
            or return $e->die_event;

    $backdate = $circ->due_date if $$args{use_due_date};

    $logger->info("marking circ for item $barcode as claims returned".
        (($backdate) ? " with backdate $backdate" : ''));

    my $patron = $e->retrieve_actor_user($circ->usr);
    my $max_count = $U->ou_ancestor_setting_value(
        $circ->circ_lib, 'circ.max_patron_claim_return_count', $e);

    # If the patron has too instances of many claims returned, 
    # require an override to continue.  A configured max of 
    # 0 means all attempts require an override
    if(defined $max_count and $patron->claims_returned_count >= $max_count) {

        if($self->api_name =~ /override/ && ($oargs->{all} || grep { $_ eq 'PATRON_EXCEEDS_CLAIMS_RETURN_COUNT' } @{$oargs->{events}})) {

            # see if we're allowed to override
            return $e->die_event unless 
                $e->allowed('SET_CIRC_CLAIMS_RETURNED.override', $circ->circ_lib);

        } else {

            # exit early and return the max claims return event
            $e->rollback;
            return OpenILS::Event->new(
                'PATRON_EXCEEDS_CLAIMS_RETURN_COUNT', 
                payload => {
                    patron_count => $patron->claims_returned_count,
                    max_count => $max_count
                }
            );
        }
    }

    $e->allowed('SET_CIRC_CLAIMS_RETURNED', $circ->circ_lib) 
        or return $e->die_event;

    $circ->stop_fines(OILS_STOP_FINES_CLAIMSRETURNED);
	$circ->stop_fines_time('now') unless $circ->stop_fines_time;

    if( $backdate ) {
        $backdate = cleanse_ISO8601($backdate);

        my $original_date = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($circ->due_date));
        my $new_date = DateTime::Format::ISO8601->new->parse_datetime($backdate);
        $backdate = $new_date->ymd . 'T' . $original_date->strftime('%T%z');

        # clean it up once again; need a : in the timezone offset. E.g. -06:00 not -0600
        $backdate = cleanse_ISO8601($backdate);

        # make it look like the circ stopped at the cliams returned time
        $circ->stop_fines_time($backdate);
        my $evt = OpenILS::Application::Circ::CircCommon->void_overdues($e, $circ, $backdate);
        return $evt if $evt;
    }

    $e->update_action_circulation($circ) or return $e->die_event;

    # see if there is a configured post-claims-return copy status
    if(my $stat = $U->ou_ancestor_setting_value($circ->circ_lib, 'circ.claim_return.copy_status')) {
	    $copy->status($stat);
	    $copy->edit_date('now');
	    $copy->editor($e->requestor->id);
	    $e->update_asset_copy($copy) or return $e->die_event;
    }

    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
	method	=> "post_checkin_backdate_circ",
	api_name	=> "open-ils.circ.post_checkin_backdate",
	signature => {
        desc => q/Back-date an already checked in circulation/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Circ ID', type => 'number'},
            {desc => 'ISO8601 backdate', type => 'string'},
        ],
        return => {desc => q/1 on success, failure event on error/}
    }
);

__PACKAGE__->register_method(
	method	=> "post_checkin_backdate_circ",
	api_name	=> "open-ils.circ.post_checkin_backdate.batch",
    stream => 1,
	signature => {
        desc => q/@see open-ils.circ.post_checkin_backdate.  Batch mode/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'List of Circ ID', type => 'array'},
            {desc => 'ISO8601 backdate', type => 'string'},
        ],
        return => {desc => q/Set of: 1 on success, failure event on error/}
    }
);


sub post_checkin_backdate_circ {
    my( $self, $conn, $auth, $circ_id, $backdate ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    if($self->api_name =~ /batch/) {
        foreach my $c (@$circ_id) {
            $conn->respond(post_checkin_backdate_circ_impl($e, $c, $backdate));
        }
    } else {
        $conn->respond_complete(post_checkin_backdate_circ_impl($e, $circ_id, $backdate));
    }

    $e->disconnect;
    return undef;
}


sub post_checkin_backdate_circ_impl {
    my($e, $circ_id, $backdate) = @_;

    $e->xact_begin;

    my $circ = $e->retrieve_action_circulation($circ_id)
        or return $e->die_event;

    # anyone with checkin perms can backdate (more restrictive?)
    return $e->die_event unless $e->allowed('COPY_CHECKIN', $circ->circ_lib);

    # don't allow back-dating an open circulation
    return OpenILS::Event->new('BAD_PARAMS') unless 
        $backdate and $circ->checkin_time;

    # update the checkin and stop_fines times to reflect the new backdate
    $circ->stop_fines_time(cleanse_ISO8601($backdate));
    $circ->checkin_time(cleanse_ISO8601($backdate));
    $e->update_action_circulation($circ) or return $e->die_event;

    # now void the overdues "erased" by the back-dating
    my $evt = OpenILS::Application::Circ::CircCommon->void_overdues($e, $circ, $backdate);
    return $evt if $evt;

    # If the circ was closed before and the balance owned !=0, re-open the transaction
    $evt = OpenILS::Application::Circ::CircCommon->reopen_xact($e, $circ->id);
    return $evt if $evt;

    $e->xact_commit;
    return 1;
}



__PACKAGE__->register_method (
	method		=> 'set_circ_due_date',
	api_name		=> 'open-ils.circ.circulation.due_date.update',
	signature	=> q/
		Updates the due_date on the given circ
		@param authtoken
		@param circid The id of the circ to update
		@param date The timestamp of the new due date
	/
);

sub set_circ_due_date {
	my( $self, $conn, $auth, $circ_id, $date ) = @_;

    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;
    my $circ = $e->retrieve_action_circulation($circ_id)
        or return $e->die_event;

    return $e->die_event unless $e->allowed('CIRC_OVERRIDE_DUE_DATE', $circ->circ_lib);
	$date = cleanse_ISO8601($date);

    if (!(interval_to_seconds($circ->duration) % 86400)) { # duration is divisible by days
        my $original_date = DateTime::Format::ISO8601->new->parse_datetime(cleanse_ISO8601($circ->due_date));
        my $new_date = DateTime::Format::ISO8601->new->parse_datetime($date);
        $date = cleanse_ISO8601( $new_date->ymd . 'T' . $original_date->strftime('%T%z') );
    }

	$circ->due_date($date);
    $e->update_action_circulation($circ) or return $e->die_event;
    $e->commit;

    return $circ;
}


__PACKAGE__->register_method(
	method		=> "create_in_house_use",
	api_name		=> 'open-ils.circ.in_house_use.create',
	signature	=>	q/
		Creates an in-house use action.
		@param $authtoken The login session key
		@param params A hash of params including
			'location' The org unit id where the in-house use occurs
			'copyid' The copy in question
			'count' The number of in-house uses to apply to this copy
		@return An array of id's representing the id's of the newly created
		in-house use objects or an event on an error
	/);

__PACKAGE__->register_method(
	method		=> "create_in_house_use",
	api_name		=> 'open-ils.circ.non_cat_in_house_use.create',
);


sub create_in_house_use {
	my( $self, $client, $auth, $params ) = @_;

	my( $evt, $copy );
	my $org			= $params->{location};
	my $copyid		= $params->{copyid};
	my $count		= $params->{count} || 1;
	my $nc_type		= $params->{non_cat_type};
	my $use_time	= $params->{use_time} || 'now';

	my $e = new_editor(xact=>1,authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('CREATE_IN_HOUSE_USE');

	my $non_cat = 1 if $self->api_name =~ /non_cat/;

	unless( $non_cat ) {
		if( $copyid ) {
			$copy = $e->retrieve_asset_copy($copyid) or return $e->event;
		} else {
			$copy = $e->search_asset_copy({barcode=>$params->{barcode}, deleted => 'f'})->[0]
				or return $e->event;
			$copyid = $copy->id;
		}
	}

	if( $use_time ne 'now' ) {
		$use_time = cleanse_ISO8601($use_time);
		$logger->debug("in_house_use setting use time to $use_time");
	}

	my @ids;
	for(1..$count) {

		my $ihu;
		my $method;
		my $cmeth;

		if($non_cat) {
			$ihu = Fieldmapper::action::non_cat_in_house_use->new;
			$ihu->item_type($nc_type);
			$method = 'open-ils.storage.direct.action.non_cat_in_house_use.create';
			$cmeth = "create_action_non_cat_in_house_use";

		} else {
			$ihu = Fieldmapper::action::in_house_use->new;
			$ihu->item($copyid);
			$method = 'open-ils.storage.direct.action.in_house_use.create';
			$cmeth = "create_action_in_house_use";
		}

		$ihu->staff($e->requestor->id);
		$ihu->org_unit($org);
		$ihu->use_time($use_time);

		$ihu = $e->$cmeth($ihu) or return $e->event;
		push( @ids, $ihu->id );
	}

	$e->commit;
	return \@ids;
}





__PACKAGE__->register_method(
	method	=> "view_circs",
	api_name	=> "open-ils.circ.copy_checkout_history.retrieve",
	notes		=> q/
		Retrieves the last X circs for a given copy
		@param authtoken The login session key
		@param copyid The copy to check
		@param count How far to go back in the item history
		@return An array of circ ids
	/);

# ----------------------------------------------------------------------
# Returns $count most recent circs.  If count exceeds the configured 
# max, use the configured max instead
# ----------------------------------------------------------------------
sub view_circs {
	my( $self, $client, $authtoken, $copyid, $count ) = @_; 

    my $e = new_editor(authtoken => $authtoken);
    return $e->event unless $e->checkauth;
    
    my $copy = $e->retrieve_asset_copy([
        $copyid,
        {   flesh => 1,
            flesh_fields => {acp => ['call_number']}
        }
    ]) or return $e->event;

    return $e->event unless $e->allowed(
        'VIEW_COPY_CHECKOUT_HISTORY', 
        ($copy->call_number == OILS_PRECAT_CALL_NUMBER) ? 
            $copy->circ_lib : $copy->call_number->owning_lib);
        
    my $max_history = $U->ou_ancestor_setting_value(
        $e->requestor->ws_ou, 'circ.item_checkout_history.max', $e);

    if(defined $max_history) {
        $count = $max_history unless defined $count and $count < $max_history;
    } else {
        $count = 4 unless defined $count;
    }

    return $e->search_action_circulation([
        {target_copy => $copyid}, 
        {limit => $count, order_by => { circ => "xact_start DESC" }} 
    ]);
}


__PACKAGE__->register_method(
	method	=> "circ_count",
	api_name	=> "open-ils.circ.circulation.count",
	notes		=> q/
		Returns the number of times the item has circulated
		@param copyid The copy to check
	/);

sub circ_count {
	my( $self, $client, $copyid, $range ) = @_; 
	my $e = OpenILS::Utils::Editor->new;
	return $e->request('open-ils.storage.asset.copy.circ_count', $copyid, $range);
}



__PACKAGE__->register_method(
	method		=> 'fetch_notes',
	authoritative	=> 1,
	api_name		=> 'open-ils.circ.copy_note.retrieve.all',
	signature	=> q/
		Returns an array of copy note objects.  
		@param args A named hash of parameters including:
			authtoken	: Required if viewing non-public notes
			itemid		: The id of the item whose notes we want to retrieve
			pub			: True if all the caller wants are public notes
		@return An array of note objects
	/);

__PACKAGE__->register_method(
	method		=> 'fetch_notes',
	api_name		=> 'open-ils.circ.call_number_note.retrieve.all',
	signature	=> q/@see open-ils.circ.copy_note.retrieve.all/);

__PACKAGE__->register_method(
	method		=> 'fetch_notes',
	api_name		=> 'open-ils.circ.title_note.retrieve.all',
	signature	=> q/@see open-ils.circ.copy_note.retrieve.all/);


# NOTE: VIEW_COPY/VOLUME/TITLE_NOTES perms should always be global
sub fetch_notes {
	my( $self, $connection, $args ) = @_;

	my $id = $$args{itemid};
	my $authtoken = $$args{authtoken};
	my( $r, $evt);

	if( $self->api_name =~ /copy/ ) {
		if( $$args{pub} ) {
			return $U->cstorereq(
				'open-ils.cstore.direct.asset.copy_note.search.atomic',
				{ owning_copy => $id, pub => 't' } );
		} else {
			( $r, $evt ) = $U->checksesperm($authtoken, 'VIEW_COPY_NOTES');
			return $evt if $evt;
			return $U->cstorereq(
				'open-ils.cstore.direct.asset.copy_note.search.atomic', {owning_copy => $id} );
		}

	} elsif( $self->api_name =~ /call_number/ ) {
		if( $$args{pub} ) {
			return $U->cstorereq(
				'open-ils.cstore.direct.asset.call_number_note.search.atomic',
				{ call_number => $id, pub => 't' } );
		} else {
			( $r, $evt ) = $U->checksesperm($authtoken, 'VIEW_VOLUME_NOTES');
			return $evt if $evt;
			return $U->cstorereq(
				'open-ils.cstore.direct.asset.call_number_note.search.atomic', { call_number => $id } );
		}

	} elsif( $self->api_name =~ /title/ ) {
		if( $$args{pub} ) {
			return $U->cstorereq(
				'open-ils.cstore.direct.bilbio.record_note.search.atomic',
				{ record => $id, pub => 't' } );
		} else {
			( $r, $evt ) = $U->checksesperm($authtoken, 'VIEW_TITLE_NOTES');
			return $evt if $evt;
			return $U->cstorereq(
				'open-ils.cstore.direct.biblio.record_note.search.atomic', { record => $id } );
		}
	}

	return undef;
}

__PACKAGE__->register_method(
	method	=> 'has_notes',
	api_name	=> 'open-ils.circ.copy.has_notes');
__PACKAGE__->register_method(
	method	=> 'has_notes',
	api_name	=> 'open-ils.circ.call_number.has_notes');
__PACKAGE__->register_method(
	method	=> 'has_notes',
	api_name	=> 'open-ils.circ.title.has_notes');


sub has_notes {
	my( $self, $conn, $authtoken, $id ) = @_;
	my $editor = OpenILS::Utils::Editor->new(authtoken => $authtoken);
	return $editor->event unless $editor->checkauth;

	my $n = $editor->search_asset_copy_note(
		{owning_copy=>$id}, {idlist=>1}) if $self->api_name =~ /copy/;

	$n = $editor->search_asset_call_number_note(
		{call_number=>$id}, {idlist=>1}) if $self->api_name =~ /call_number/;

	$n = $editor->search_biblio_record_note(
		{record=>$id}, {idlist=>1}) if $self->api_name =~ /title/;

	return scalar @$n;
}



__PACKAGE__->register_method(
	method		=> 'create_copy_note',
	api_name		=> 'open-ils.circ.copy_note.create',
	signature	=> q/
		Creates a new copy note
		@param authtoken The login session key
		@param note	The note object to create
		@return The id of the new note object
	/);

sub create_copy_note {
	my( $self, $connection, $authtoken, $note ) = @_;

	my $e = new_editor(xact=>1, authtoken=>$authtoken);
	return $e->event unless $e->checkauth;
	my $copy = $e->retrieve_asset_copy(
		[
			$note->owning_copy,
			{	flesh => 1,
				flesh_fields => { 'acp' => ['call_number'] }
			}
		]
	);

	return $e->event unless 
		$e->allowed('CREATE_COPY_NOTE', $copy->call_number->owning_lib);

	$note->create_date('now');
	$note->creator($e->requestor->id);
	$note->pub( ($U->is_true($note->pub)) ? 't' : 'f' );
	$note->clear_id;

	$e->create_asset_copy_note($note) or return $e->event;
	$e->commit;
	return $note->id;
}


__PACKAGE__->register_method(
	method		=> 'delete_copy_note',
	api_name		=>	'open-ils.circ.copy_note.delete',
	signature	=> q/
		Deletes an existing copy note
		@param authtoken The login session key
		@param noteid The id of the note to delete
		@return 1 on success - Event otherwise.
		/);
sub delete_copy_note {
	my( $self, $conn, $authtoken, $noteid ) = @_;

	my $e = new_editor(xact=>1, authtoken=>$authtoken);
	return $e->die_event unless $e->checkauth;

	my $note = $e->retrieve_asset_copy_note([
		$noteid,
		{ flesh => 2,
			flesh_fields => {
				'acpn' => [ 'owning_copy' ],
				'acp' => [ 'call_number' ],
			}
		}
	]) or return $e->die_event;

	if( $note->creator ne $e->requestor->id ) {
		return $e->die_event unless 
			$e->allowed('DELETE_COPY_NOTE', $note->owning_copy->call_number->owning_lib);
	}

	$e->delete_asset_copy_note($note) or return $e->die_event;
	$e->commit;
	return 1;
}


__PACKAGE__->register_method(
	method => 'age_hold_rules',
	api_name	=>  'open-ils.circ.config.rules.age_hold_protect.retrieve.all',
);

sub age_hold_rules {
	my( $self, $conn ) = @_;
	return new_editor()->retrieve_all_config_rules_age_hold_protect();
}



__PACKAGE__->register_method(
	method => 'copy_details_barcode',
    authoritative => 1,
	api_name => 'open-ils.circ.copy_details.retrieve.barcode');
sub copy_details_barcode {
	my( $self, $conn, $auth, $barcode ) = @_;
    my $e = new_editor();
    my $cid = $e->search_asset_copy({barcode=>$barcode, deleted=>'f'}, {idlist=>1})->[0];
    return $e->event unless $cid;
	return copy_details( $self, $conn, $auth, $cid );
}


__PACKAGE__->register_method(
	method => 'copy_details',
	api_name => 'open-ils.circ.copy_details.retrieve');

sub copy_details {
	my( $self, $conn, $auth, $copy_id ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;

	my $flesh = { flesh => 1 };

	my $copy = $e->retrieve_asset_copy(
		[
			$copy_id,
			{
				flesh => 2,
				flesh_fields => {
					acp => ['call_number','parts','peer_record_maps'],
					acn => ['record','prefix','suffix','label_class']
				}
			}
		]) or return $e->event;


	# De-flesh the copy for backwards compatibility
	my $mvr;
	my $vol = $copy->call_number;
	if( ref $vol ) {
		$copy->call_number($vol->id);
		my $record = $vol->record;
		if( ref $record ) {
			$vol->record($record->id);
			$mvr = $U->record_to_mvr($record);
		}
	}


	my $hold = $e->search_action_hold_request(
		{ 
			current_copy		=> $copy_id, 
			capture_time		=> { "!=" => undef },
			fulfillment_time	=> undef,
			cancel_time			=> undef,
		}
	)->[0];

	OpenILS::Application::Circ::Holds::flesh_hold_transits([$hold]) if $hold;

	my $transit = $e->search_action_transit_copy(
		{ target_copy => $copy_id, dest_recv_time => undef } )->[0];

	# find the latest circ, open or closed
	my $circ = $e->search_action_circulation(
		[
			{ target_copy => $copy_id },
			{ 
                flesh => 1,
                flesh_fields => {
                    circ => [
                        'workstation',
                        'checkin_workstation', 
                        'duration_rule', 
                        'max_fine_rule', 
                        'recurring_fine_rule'
                    ]
                },
                order_by => { circ => 'xact_start desc' }, 
                limit => 1 
            }
		]
	)->[0];


	return {
		copy		=> $copy,
		hold		=> $hold,
		transit	=> $transit,
		circ		=> $circ,
		volume	=> $vol,
		mvr		=> $mvr,
	};
}




__PACKAGE__->register_method(
	method => 'mark_item',
	api_name => 'open-ils.circ.mark_item_damaged',
	signature	=> q/
		Changes the status of a copy to "damaged". Requires MARK_ITEM_DAMAGED permission.
		@param authtoken The login session key
		@param copy_id The ID of the copy to mark as damaged
		@return 1 on success - Event otherwise.
		/
);
__PACKAGE__->register_method(
	method => 'mark_item',
	api_name => 'open-ils.circ.mark_item_missing',
	signature	=> q/
		Changes the status of a copy to "missing". Requires MARK_ITEM_MISSING permission.
		@param authtoken The login session key
		@param copy_id The ID of the copy to mark as missing 
		@return 1 on success - Event otherwise.
		/
);
__PACKAGE__->register_method(
	method => 'mark_item',
	api_name => 'open-ils.circ.mark_item_bindery',
	signature	=> q/
		Changes the status of a copy to "bindery". Requires MARK_ITEM_BINDERY permission.
		@param authtoken The login session key
		@param copy_id The ID of the copy to mark as bindery
		@return 1 on success - Event otherwise.
		/
);
__PACKAGE__->register_method(
	method => 'mark_item',
	api_name => 'open-ils.circ.mark_item_on_order',
	signature	=> q/
		Changes the status of a copy to "on order". Requires MARK_ITEM_ON_ORDER permission.
		@param authtoken The login session key
		@param copy_id The ID of the copy to mark as on order 
		@return 1 on success - Event otherwise.
		/
);
__PACKAGE__->register_method(
	method => 'mark_item',
	api_name => 'open-ils.circ.mark_item_ill',
	signature	=> q/
		Changes the status of a copy to "inter-library loan". Requires MARK_ITEM_ILL permission.
		@param authtoken The login session key
		@param copy_id The ID of the copy to mark as inter-library loan
		@return 1 on success - Event otherwise.
		/
);
__PACKAGE__->register_method(
	method => 'mark_item',
	api_name => 'open-ils.circ.mark_item_cataloging',
	signature	=> q/
		Changes the status of a copy to "cataloging". Requires MARK_ITEM_CATALOGING permission.
		@param authtoken The login session key
		@param copy_id The ID of the copy to mark as cataloging 
		@return 1 on success - Event otherwise.
		/
);
__PACKAGE__->register_method(
	method => 'mark_item',
	api_name => 'open-ils.circ.mark_item_reserves',
	signature	=> q/
		Changes the status of a copy to "reserves". Requires MARK_ITEM_RESERVES permission.
		@param authtoken The login session key
		@param copy_id The ID of the copy to mark as reserves
		@return 1 on success - Event otherwise.
		/
);
__PACKAGE__->register_method(
	method => 'mark_item',
	api_name => 'open-ils.circ.mark_item_discard',
	signature	=> q/
		Changes the status of a copy to "discard". Requires MARK_ITEM_DISCARD permission.
		@param authtoken The login session key
		@param copy_id The ID of the copy to mark as discard
		@return 1 on success - Event otherwise.
		/
);

sub mark_item {
	my( $self, $conn, $auth, $copy_id, $args ) = @_;
	my $e = new_editor(authtoken=>$auth, xact =>1);
	return $e->die_event unless $e->checkauth;
    $args ||= {};

    my $copy = $e->retrieve_asset_copy([
        $copy_id,
        {flesh => 1, flesh_fields => {'acp' => ['call_number']}}])
            or return $e->die_event;

    my $owning_lib = 
        ($copy->call_number->id == OILS_PRECAT_CALL_NUMBER) ? 
            $copy->circ_lib : $copy->call_number->owning_lib;

	my $perm = 'MARK_ITEM_MISSING';
	my $stat = OILS_COPY_STATUS_MISSING;

	if( $self->api_name =~ /damaged/ ) {
		$perm = 'MARK_ITEM_DAMAGED';
		$stat = OILS_COPY_STATUS_DAMAGED;
        my $evt = handle_mark_damaged($e, $copy, $owning_lib, $args);
        return $evt if $evt;

	} elsif ( $self->api_name =~ /bindery/ ) {
		$perm = 'MARK_ITEM_BINDERY';
		$stat = OILS_COPY_STATUS_BINDERY;
	} elsif ( $self->api_name =~ /on_order/ ) {
		$perm = 'MARK_ITEM_ON_ORDER';
		$stat = OILS_COPY_STATUS_ON_ORDER;
	} elsif ( $self->api_name =~ /ill/ ) {
		$perm = 'MARK_ITEM_ILL';
		$stat = OILS_COPY_STATUS_ILL;
	} elsif ( $self->api_name =~ /cataloging/ ) {
		$perm = 'MARK_ITEM_CATALOGING';
		$stat = OILS_COPY_STATUS_CATALOGING;
	} elsif ( $self->api_name =~ /reserves/ ) {
		$perm = 'MARK_ITEM_RESERVES';
		$stat = OILS_COPY_STATUS_RESERVES;
	} elsif ( $self->api_name =~ /discard/ ) {
		$perm = 'MARK_ITEM_DISCARD';
		$stat = OILS_COPY_STATUS_DISCARD;
	}

    # caller may proceed if either perm is allowed
    return $e->die_event unless $e->allowed([$perm, 'UPDATE_COPY'], $owning_lib);

	$copy->status($stat);
	$copy->edit_date('now');
	$copy->editor($e->requestor->id);

	$e->update_asset_copy($copy) or return $e->die_event;

	my $holds = $e->search_action_hold_request(
		{ 
			current_copy => $copy->id,
			fulfillment_time => undef,
			cancel_time => undef,
		}
	);

	$e->commit;

	if( $self->api_name =~ /damaged/ ) {
        # now that we've committed the changes, create related A/T events
        my $ses = OpenSRF::AppSession->create('open-ils.trigger');
        $ses->request('open-ils.trigger.event.autocreate', 'damaged', $copy, $owning_lib);
    }

	$logger->debug("resetting holds that target the marked copy");
	OpenILS::Application::Circ::Holds->_reset_hold($e->requestor, $_) for @$holds;

	return 1;
}

sub handle_mark_damaged {
    my($e, $copy, $owning_lib, $args) = @_;

    my $apply = $args->{apply_fines} || '';
    return undef if $apply eq 'noapply';

    my $new_amount = $args->{override_amount};
    my $new_btype = $args->{override_btype};
    my $new_note = $args->{override_note};

    # grab the last circulation
    my $circ = $e->search_action_circulation([
        {   target_copy => $copy->id}, 
        {   limit => 1, 
            order_by => {circ => "xact_start DESC"},
            flesh => 2,
            flesh_fields => {circ => ['target_copy', 'usr'], au => ['card']}
        }
    ])->[0];

    return undef unless $circ;

    my $charge_price = $U->ou_ancestor_setting_value(
        $owning_lib, 'circ.charge_on_damaged', $e);

    my $proc_fee = $U->ou_ancestor_setting_value(
        $owning_lib, 'circ.damaged_item_processing_fee', $e) || 0;

    my $void_overdue = $U->ou_ancestor_setting_value(
        $owning_lib, 'circ.damaged.void_ovedue', $e) || 0;

    return undef unless $charge_price or $proc_fee;

    my $copy_price = ($charge_price) ? $U->get_copy_price($e, $copy) : 0;
    my $total = $copy_price + $proc_fee;

    if($apply) {
        
        if($new_amount and $new_btype) {

            # Allow staff to override the amount to charge for a damaged item
            # Consider the case where the item is only partially damaged
            # This value is meant to take the place of the item price and
            # optional processing fee.

            my $evt = OpenILS::Application::Circ::CircCommon->create_bill(
                $e, $new_amount, $new_btype, 'Damaged Item Override', $circ->id, $new_note);
            return $evt if $evt;

        } else {

            if($charge_price and $copy_price) {
                my $evt = OpenILS::Application::Circ::CircCommon->create_bill(
                    $e, $copy_price, 7, 'Damaged Item', $circ->id);
                return $evt if $evt;
            }

            if($proc_fee) {
                my $evt = OpenILS::Application::Circ::CircCommon->create_bill(
                    $e, $proc_fee, 8, 'Damaged Item Processing Fee', $circ->id);
                return $evt if $evt;
            }
        }

        # the assumption is that you would not void the overdues unless you 
        # were also charging for the item and/or applying a processing fee
        if($void_overdue) {
            my $evt = OpenILS::Application::Circ::CircCommon->void_overdues($e, $circ);
            return $evt if $evt;
        }

        my $evt = OpenILS::Application::Circ::CircCommon->reopen_xact($e, $circ->id);
        return $evt if $evt;

        my $ses = OpenSRF::AppSession->create('open-ils.trigger');
        $ses->request('open-ils.trigger.event.autocreate', 'checkout.damaged', $circ, $circ->circ_lib);

        my $evt2 = OpenILS::Utils::Penalty->calculate_penalties($e, $circ->usr->id, $e->requestor->ws_ou);
        return $evt2 if $evt2;

        return undef;

    } else {
        return OpenILS::Event->new('DAMAGE_CHARGE', 
            payload => {
                circ => $circ,
                charge => $total
            }
        );
    }
}



# ----------------------------------------------------------------------
__PACKAGE__->register_method(
    method => 'mark_item_missing_pieces',
    api_name => 'open-ils.circ.mark_item_missing_pieces',
    signature	=> q/
        Changes the status of a copy to "damaged" or to a custom status based on the 
        circ.missing_pieces.copy_status org unit setting. Requires MARK_ITEM_MISSING_PIECES
        permission.
        @param authtoken The login session key
        @param copy_id The ID of the copy to mark as damaged
        @return Success event with circ and copy objects in the payload, or error Event otherwise.
        /
);

sub mark_item_missing_pieces {
	my( $self, $conn, $auth, $copy_id, $args ) = @_;
    ### FIXME: We're starting a transaction here, but we're doing a lot of things outside of the transaction
    ### FIXME: Even better, we're going to use two transactions, the first to affect pertinent holds before checkout can

	my $e2 = new_editor(authtoken=>$auth, xact =>1);
	return $e2->die_event unless $e2->checkauth;
    $args ||= {};

    my $copy = $e2->retrieve_asset_copy([
        $copy_id,
        {flesh => 1, flesh_fields => {'acp' => ['call_number']}}])
            or return $e2->die_event;

    my $owning_lib = 
        ($copy->call_number->id == OILS_PRECAT_CALL_NUMBER) ? 
            $copy->circ_lib : $copy->call_number->owning_lib;

    return $e2->die_event unless $e2->allowed('MARK_ITEM_MISSING_PIECES', $owning_lib);

    #### grab the last circulation
    my $circ = $e2->search_action_circulation([
        {   target_copy => $copy->id}, 
        {   limit => 1, 
            order_by => {circ => "xact_start DESC"}
        }
    ])->[0];

    if (!$circ) {
        $logger->info('open-ils.circ.mark_item_missing_pieces: no previous checkout');
        $e2->rollback;
        return OpenILS::Event->new('ACTION_CIRCULATION_NOT_FOUND',{'copy'=>$copy});
    }

	my $holds = $e2->search_action_hold_request(
		{ 
			current_copy => $copy->id,
			fulfillment_time => undef,
			cancel_time => undef,
		}
	);

    $logger->debug("resetting holds that target the marked copy");
    OpenILS::Application::Circ::Holds->_reset_hold($e2->requestor, $_) for @$holds;

    
	if (! $e2->commit) {
        return $e2->die_event;
    }

	my $e = new_editor(authtoken=>$auth, xact =>1);
	return $e->die_event unless $e->checkauth;

    if (! $circ->checkin_time) { # if circ active, attempt renew
        my ($res) = $self->method_lookup('open-ils.circ.renew')->run($e->authtoken,{'copy_id'=>$circ->target_copy});
        if (ref $res ne 'ARRAY') { $res = [ $res ]; }
        if ( $res->[0]->{textcode} eq 'SUCCESS' ) {
            $circ = $res->[0]->{payload}{'circ'};
            $circ->target_copy( $copy->id );
            $logger->info('open-ils.circ.mark_item_missing_pieces: successful renewal');
        } else {
            $logger->info('open-ils.circ.mark_item_missing_pieces: non-successful renewal');
        }
    } else {

        my $co_params = {
            'copy_id'=>$circ->target_copy,
            'patron_id'=>$circ->usr,
            'skip_deposit_fee'=>1,
            'skip_rental_fee'=>1
        };

        if ($U->ou_ancestor_setting_value($e->requestor->ws_ou, 'circ.block_renews_for_holds')) {

            my ($hold, undef, $retarget) = $holdcode->find_nearest_permitted_hold(
                $e, $copy, $e->requestor, 1 );

            if ($hold) { # needed for hold? then due now

                $logger->info('open-ils.circ.mark_item_missing_pieces: item needed for hold, shortening due date');
                my $due_date = DateTime->now(time_zone => 'local');
                $co_params->{'due_date'} = cleanse_ISO8601( $due_date->strftime('%FT%T%z') );
            } else {
                $logger->info('open-ils.circ.mark_item_missing_pieces: item not needed for hold');
            }
        }

        my ($res) = $self->method_lookup('open-ils.circ.checkout.full.override')->run($e->authtoken,$co_params,{ all => 1 });
        if (ref $res ne 'ARRAY') { $res = [ $res ]; }
        if ( $res->[0]->{textcode} eq 'SUCCESS' ) {
            $logger->info('open-ils.circ.mark_item_missing_pieces: successful checkout');
            $circ = $res->[0]->{payload}{'circ'};
        } else {
            $logger->info('open-ils.circ.mark_item_missing_pieces: non-successful checkout');
            $e->rollback;
            return $res;
        }
    }

    ### Update the item status

    my $custom_stat = $U->ou_ancestor_setting_value(
        $owning_lib, 'circ.missing_pieces.copy_status', $e);
    my $stat = $custom_stat || OILS_COPY_STATUS_DAMAGED;

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    $ses->request('open-ils.trigger.event.autocreate', 'missing_pieces', $copy, $owning_lib);

	$copy->status($stat);
	$copy->edit_date('now');
	$copy->editor($e->requestor->id);

	$e->update_asset_copy($copy) or return $e->die_event;

	if ($e->commit) {

        my $ses = OpenSRF::AppSession->create('open-ils.trigger');
        $ses->request('open-ils.trigger.event.autocreate', 'circ.missing_pieces', $circ, $circ->circ_lib);

        return OpenILS::Event->new('SUCCESS',
            payload => {
                circ => $circ,
                copy => $copy,
                slip => $U->fire_object_event(undef, 'circ.format.missing_pieces.slip.print', $circ, $circ->circ_lib),
                letter => $U->fire_object_event(undef, 'circ.format.missing_pieces.letter.print', $circ, $circ->circ_lib)
            }
        ); 

    } else {
        return $e->die_event;
    }
}





# ----------------------------------------------------------------------
__PACKAGE__->register_method(
	method => 'magic_fetch',
	api_name => 'open-ils.agent.fetch'
);

my @FETCH_ALLOWED = qw/ aou aout acp acn bre /;

sub magic_fetch {
	my( $self, $conn, $auth, $args ) = @_;
	my $e = new_editor( authtoken => $auth );
	return $e->event unless $e->checkauth;

	my $hint = $$args{hint};
	my $id	= $$args{id};

	# Is the call allowed to fetch this type of object?
	return undef unless grep { $_ eq $hint } @FETCH_ALLOWED;

	# Find the class the implements the given hint
	my ($class) = grep { 
		$Fieldmapper::fieldmap->{$_}{hint} eq $hint } Fieldmapper->classes;

	$class =~ s/Fieldmapper:://og;
	$class =~ s/::/_/og;
	my $method = "retrieve_$class";

	my $obj = $e->$method($id) or return $e->event;
	return $obj;
}
# ----------------------------------------------------------------------


__PACKAGE__->register_method(
	method	=> "fleshed_circ_retrieve",
    authoritative => 1,
	api_name	=> "open-ils.circ.fleshed.retrieve",);

sub fleshed_circ_retrieve {
	my( $self, $client, $id ) = @_;
	my $e = new_editor();
	my $circ = $e->retrieve_action_circulation(
		[
			$id,
			{ 
				flesh				=> 4,
				flesh_fields	=> { 
					circ => [ qw/ target_copy / ],
					acp => [ qw/ location status stat_cat_entry_copy_maps notes age_protect call_number parts / ],
					ascecm => [ qw/ stat_cat stat_cat_entry / ],
					acn => [ qw/ record / ],
				}
			}
		]
	) or return $e->event;
	
	my $copy = $circ->target_copy;
	my $vol = $copy->call_number;
	my $rec = $circ->target_copy->call_number->record;

	$vol->record($rec->id);
	$copy->call_number($vol->id);
	$circ->target_copy($copy->id);

	my $mvr;

	if( $rec->id == OILS_PRECAT_RECORD ) {
		$rec = undef;
		$vol = undef;
	} else { 
		$mvr = $U->record_to_mvr($rec);
		$rec->marc(''); # drop the bulky marc data
	}

	return {
		circ => $circ,
		copy => $copy,
		volume => $vol,
		record => $rec,
		mvr => $mvr,
	};
}



__PACKAGE__->register_method(
	method	=> "test_batch_circ_events",
	api_name	=> "open-ils.circ.trigger_event_by_def_and_barcode.fire"
);

#  method for testing the behavior of a given event definition
sub test_batch_circ_events {
    my($self, $conn, $auth, $event_def, $barcode) = @_;

    my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_CIRCULATIONS');

    my $copy = $e->search_asset_copy({barcode => $barcode, deleted => 'f'})->[0]
        or return $e->event;

    my $circ = $e->search_action_circulation(
        {target_copy => $copy->id, checkin_time => undef})->[0]
        or return $e->event;
        
    return undef unless $circ;

    return $U->fire_object_event($event_def, undef, $circ, $e->requestor->ws_ou)
}


__PACKAGE__->register_method(
	method	=> "fire_circ_events", 
	api_name	=> "open-ils.circ.fire_circ_trigger_events",
    signature => q/
        General event def runner for circ objects.  If no event def ID
        is provided, the hook will be used to find the best event_def
        match based on the context org unit
    /
);

__PACKAGE__->register_method(
	method	=> "fire_circ_events", 
	api_name	=> "open-ils.circ.fire_hold_trigger_events",
    signature => q/
        General event def runner for hold objects.  If no event def ID
        is provided, the hook will be used to find the best event_def
        match based on the context org unit
    /
);

__PACKAGE__->register_method(
	method	=> "fire_circ_events", 
	api_name	=> "open-ils.circ.fire_user_trigger_events",
    signature => q/
        General event def runner for user objects.  If no event def ID
        is provided, the hook will be used to find the best event_def
        match based on the context org unit
    /
);


sub fire_circ_events {
    my($self, $conn, $auth, $org_id, $event_def, $hook, $granularity, $target_ids, $user_data) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
	return $e->event unless $e->checkauth;

    my $targets;

    if($self->api_name =~ /hold/) {
        return $e->event unless $e->allowed('VIEW_HOLD', $org_id);
        $targets = $e->batch_retrieve_action_hold_request($target_ids);
    } elsif($self->api_name =~ /user/) {
        return $e->event unless $e->allowed('VIEW_USER', $org_id);
        $targets = $e->batch_retrieve_actor_user($target_ids);
    } else {
        return $e->event unless $e->allowed('VIEW_CIRCULATIONS', $org_id);
        $targets = $e->batch_retrieve_action_circulation($target_ids);
    }
    $e->rollback; # FIXME using transaction because of pgpool/slony setups, but not
                  # simply making this method authoritative because of weirdness
                  # with transaction handling in A/T code that causes rollback
                  # failure down the line if handling many targets

    return undef unless @$targets;
    return $U->fire_object_event($event_def, $hook, $targets, $org_id, $granularity, $user_data);
}

__PACKAGE__->register_method(
	method	=> "user_payments_list",
	api_name	=> "open-ils.circ.user_payments.filtered.batch",
    stream => 1,
	signature => {
        desc => q/Returns a fleshed, date-limited set of all payments a user
                has made.  By default, ordered by payment date.  Optionally
                ordered by other columns in the top-level "mp" object/,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'User ID', type => 'number'},
            {desc => 'Order by column(s), optional.  Array of "mp" class columns', type => 'array'}
        ],
        return => {desc => q/List of "mp" objects, fleshed with the billable transaction 
            and the related fully-realized payment object (e.g money.cash_payment)/}
    }
);

sub user_payments_list {
    my($self, $conn, $auth, $user_id, $start_date, $end_date, $order_by) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    my $user = $e->retrieve_actor_user($user_id) or return $e->event;
    return $e->event unless $e->allowed('VIEW_CIRCULATIONS', $user->home_ou);

    $order_by ||= ['payment_ts'];

    # all payments by user, between start_date and end_date
    my $payments = $e->json_query({
        select => {mp => ['id']}, 
        from => {
            mp => {
                mbt => {
                    fkey => 'xact', field => 'id'}
            }
        }, 
        where => {
            '+mbt' => {usr => $user_id}, 
            '+mp' => {payment_ts => {between => [$start_date, $end_date]}}
        },
        order_by => {mp => $order_by}
    });

    for my $payment_id (@$payments) {
        my $payment = $e->retrieve_money_payment([
            $payment_id->{id}, 
            {   
                flesh => 2,
                flesh_fields => {
                    mp => [
                        'xact',
                        'cash_payment',
                        'credit_card_payment',
                        'credit_payment',
                        'check_payment',
                        'work_payment',
                        'forgive_payment',
                        'goods_payment'
                    ],
                    mbt => [
                        'circulation', 
                        'grocery',
                        'reservation'
                    ]
                }
            }
        ]);
        $conn->respond($payment);
    }

    return undef;
}


__PACKAGE__->register_method(
	method	=> "retrieve_circ_chain",
	api_name	=> "open-ils.circ.renewal_chain.retrieve_by_circ",
    stream => 1,
	signature => {
        desc => q/Given a circulation, this returns all circulation objects
                that are part of the same chain of renewals./,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Circ ID', type => 'number'},
        ],
        return => {desc => q/List of circ objects, orderd by oldest circ first/}
    }
);

__PACKAGE__->register_method(
	method	=> "retrieve_circ_chain",
	api_name	=> "open-ils.circ.renewal_chain.retrieve_by_circ.summary",
	signature => {
        desc => q/Given a circulation, this returns a summary of the circulation objects
                that are part of the same chain of renewals./,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Circ ID', type => 'number'},
        ],
        return => {desc => q/Circulation Chain Summary/}
    }
);

sub retrieve_circ_chain {
    my($self, $conn, $auth, $circ_id) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_CIRCULATIONS');

    if($self->api_name =~ /summary/) {
        return $U->create_circ_chain_summary($e, $circ_id);

    } else {

        my $chain = $e->json_query({from => ['action.circ_chain', $circ_id]});

        for my $circ_info (@$chain) {
            my $circ = Fieldmapper::action::circulation->new;
            $circ->$_($circ_info->{$_}) for keys %$circ_info;
            $conn->respond($circ);
        }
    }

    return undef;
}

__PACKAGE__->register_method(
	method	=> "retrieve_prev_circ_chain",
	api_name	=> "open-ils.circ.prev_renewal_chain.retrieve_by_circ",
    stream => 1,
	signature => {
        desc => q/Given a circulation, this returns all circulation objects
                that are part of the previous chain of renewals./,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Circ ID', type => 'number'},
        ],
        return => {desc => q/List of circ objects, orderd by oldest circ first/}
    }
);

__PACKAGE__->register_method(
	method	=> "retrieve_prev_circ_chain",
	api_name	=> "open-ils.circ.prev_renewal_chain.retrieve_by_circ.summary",
	signature => {
        desc => q/Given a circulation, this returns a summary of the circulation objects
                that are part of the previous chain of renewals./,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Circ ID', type => 'number'},
        ],
        return => {desc => q/Object containing Circulation Chain Summary and User Id/}
    }
);

sub retrieve_prev_circ_chain {
    my($self, $conn, $auth, $circ_id) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_CIRCULATIONS');

    if($self->api_name =~ /summary/) {
        my $first_circ = $e->json_query({from => ['action.circ_chain', $circ_id]})->[0];
        my $target_copy = $$first_circ{'target_copy'};
        my $usr = $$first_circ{'usr'};
        my $last_circ_from_prev_chain = $e->json_query({
            'select' => { 'circ' => ['id','usr'] },
            'from' => 'circ', 
            'where' => {
                target_copy => $target_copy,
                xact_start => { '<' => $$first_circ{'xact_start'} }
            },
            'order_by' => [{ 'class'=>'circ', 'field'=>'xact_start', 'direction'=>'desc' }],
            'limit' => 1
        })->[0];
        return undef unless $last_circ_from_prev_chain;
        return undef unless $$last_circ_from_prev_chain{'id'};
        my $sum = $e->json_query({from => ['action.summarize_circ_chain', $$last_circ_from_prev_chain{'id'}]})->[0];
        return undef unless $sum;
        my $obj = Fieldmapper::action::circ_chain_summary->new;
        $obj->$_($sum->{$_}) for keys %$sum;
        return { 'summary' => $obj, 'usr' => $$last_circ_from_prev_chain{'usr'} };

    } else {

        my $first_circ = $e->json_query({from => ['action.circ_chain', $circ_id]})->[0];
        my $target_copy = $$first_circ{'target_copy'};
        my $last_circ_from_prev_chain = $e->json_query({
            'select' => { 'circ' => ['id'] },
            'from' => 'circ', 
            'where' => {
                target_copy => $target_copy,
                xact_start => { '<' => $$first_circ{'xact_start'} }
            },
            'order_by' => [{ 'class'=>'circ', 'field'=>'xact_start', 'direction'=>'desc' }],
            'limit' => 1
        })->[0];
        return undef unless $last_circ_from_prev_chain;
        return undef unless $$last_circ_from_prev_chain{'id'};
        my $chain = $e->json_query({from => ['action.circ_chain', $$last_circ_from_prev_chain{'id'}]});

        for my $circ_info (@$chain) {
            my $circ = Fieldmapper::action::circulation->new;
            $circ->$_($circ_info->{$_}) for keys %$circ_info;
            $conn->respond($circ);
        }
    }

    return undef;
}


__PACKAGE__->register_method(
	method	=> "get_copy_due_date",
	api_name	=> "open-ils.circ.copy.due_date.retrieve",
	signature => {
        desc => q/
            Given a copy ID, returns the due date for the copy if it's 
            currently circulating.  Otherwise, returns null.  Note, this is a public 
            method requiring no authentication.  Only the due date is exposed.
            /,
        params => [
            {desc => 'Copy ID', type => 'number'}
        ],
        return => {desc => q/
            Due date (ISO date stamp) if the copy is circulating, null otherwise.
        /}
    }
);

sub get_copy_due_date {
    my($self, $conn, $copy_id) = @_;
    my $e = new_editor();

    my $circ = $e->json_query({
        select => {circ => ['due_date']},
        from => 'circ',
        where => {
            target_copy => $copy_id,
            checkin_time => undef,
            '-or' => [
                {stop_fines => ["MAXFINES","LONGOVERDUE"]},
                {stop_fines => undef}
            ],
        },
        limit => 1
    })->[0] or return undef;

    return $circ->{due_date};
}





# {"select":{"acp":["id"],"circ":[{"aggregate":true,"transform":"count","alias":"count","column":"id"}]},"from":{"acp":{"circ":{"field":"target_copy","fkey":"id","type":"left"},"acn"{"field":"id","fkey":"call_number"}}},"where":{"+acn":{"record":200057}}


1;
