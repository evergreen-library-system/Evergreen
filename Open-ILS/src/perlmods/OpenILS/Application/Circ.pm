package OpenILS::Application::Circ;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenILS::Application::Circ::Circulate;
use OpenILS::Application::Circ::Survey;
use OpenILS::Application::Circ::StatCat;
use OpenILS::Application::Circ::Holds;
use OpenILS::Application::Circ::HoldNotify;
use OpenILS::Application::Circ::Money;
use OpenILS::Application::Circ::NonCat;
use OpenILS::Application::Circ::CopyLocations;

use DateTime;
use DateTime::Format::ISO8601;

use OpenILS::Application::AppUtils;

use OpenSRF::Utils qw/:datetime/;
use OpenILS::Utils::ModsParser;
use OpenILS::Event;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::Editor;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Const qw/:const/;
use OpenSRF::Utils::SettingsClient;

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;


# ------------------------------------------------------------------------
# Top level Circ package;
# ------------------------------------------------------------------------

sub initialize {
	my $self = shift;
	OpenILS::Application::Circ::Circulate->initialize();
}


__PACKAGE__->register_method(
	method => 'retrieve_circ',
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
    return $e->search_config_billing_type(
        {owner => $U->get_org_full_path($org_id, $depth)});
}



# ------------------------------------------------------------------------
# Returns an array of {circ, record} hashes checked out by the user.
# ------------------------------------------------------------------------
__PACKAGE__->register_method(
	method	=> "checkouts_by_user",
	api_name	=> "open-ils.circ.actor.user.checked_out",
	NOTES		=> <<"	NOTES");
	Returns a list of open circulations as a pile of objects.  each object
	contains the relevant copy, circ, and record
	NOTES

sub checkouts_by_user {
	my( $self, $client, $user_session, $user_id ) = @_;

	my( $requestor, $target, $copy, $record, $evt );

	( $requestor, $target, $evt ) = 
		$apputils->checkses_requestor( $user_session, $user_id, 'VIEW_CIRCULATIONS');
	return $evt if $evt;

	my $circs = $apputils->simplereq(
		'open-ils.cstore',
		"open-ils.cstore.direct.action.open_circulation.search.atomic", 
		{ usr => $target->id, checkin_time => undef } );
#		{ usr => $target->id } );

	my @results;
	for my $circ (@$circs) {

		( $copy, $evt )  = $apputils->fetch_copy($circ->target_copy);
		return $evt if $evt;

		$logger->debug("Retrieving record for copy " . $circ->target_copy);

		($record, $evt) = $apputils->fetch_record_by_copy( $circ->target_copy );
		return $evt if $evt;

		my $mods = $apputils->record_to_mvr($record);

		push( @results, { copy => $copy, circ => $circ, record => $mods } );
	}

	return \@results;

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

    my $barcode = $$args{barcode};
    $logger->info("marking item lost $barcode");

    # ---------------------------------------------------------------------
    # gather the pieces
    my $copy = $e->search_asset_copy([
        {barcode=>$barcode, deleted=>'f'},
        {flesh => 1, flesh_fields => {'acp' => ['call_number']}}])->[0] 
            or return $e->die_event;

    my $owning_lib = 
        ($copy->call_number->id == OILS_PRECAT_CALL_NUMBER) ? 
            $copy->circ_lib : $copy->call_number->owning_lib;

    my $circ = $e->search_action_circulation(
        {checkin_time => undef, target_copy => $copy->id} )->[0]
            or return $e->die_event;

    $e->allowed('SET_CIRC_LOST', $circ->circ_lib) or return $e->die_event;

    return OpenILS::Event->new('COPY_MARKED_LOST')
	    if $copy->status == OILS_COPY_STATUS_LOST;

    # ---------------------------------------------------------------------
    # fetch the related org settings
    my $proc_fee = $U->ou_ancestor_setting_value(
        $owning_lib, OILS_SETTING_LOST_PROCESSING_FEE, $e) || 0;
    my $void_overdue = $U->ou_ancestor_setting_value(
        $owning_lib, OILS_SETTING_VOID_OVERDUE_ON_LOST, $e) || 0;

    # ---------------------------------------------------------------------
    # move the copy into LOST status
    $copy->status(OILS_COPY_STATUS_LOST);
    $copy->editor($e->requestor->id);
    $copy->edit_date('now');
    $e->update_asset_copy($copy) or return $e->die_event;

    my $price = $U->get_copy_price($e, $copy, $copy->call_number);

    if( $price > 0 ) {
        my $evt = create_bill($e, $price, 'Lost Materials', $circ->id);
        return $evt if $evt;
    }

    # ---------------------------------------------------------------------
    # if there is a processing fee, charge that too
    if( $proc_fee > 0 ) {
        my $evt = create_bill($e, $proc_fee, 'Lost Materials Processing Fee', $circ->id);
        return $evt if $evt;
    }

    # ---------------------------------------------------------------------
    # mark the circ as lost and stop the fines
    $circ->stop_fines(OILS_STOP_FINES_LOST);
    $circ->stop_fines_time('now') unless $circ->stop_fines_time;
    $e->update_action_circulation($circ) or return $e->die_event;

    # ---------------------------------------------------------------------
    # void all overdue fines on this circ if configured
    if( $void_overdue ) {
        my $evt = void_overdues($e, $circ);
        return $evt if $evt;
    }

    my $evt = reopen_xact($e, $circ->id);
    return $evt if $evt;

    $e->commit;
    return 1;
}

sub reopen_xact {
    my($e, $xactid) = @_;

    # -----------------------------------------------------------------
    # make sure the transaction is not closed
    my $xact = $e->retrieve_money_billable_transaction($xactid)
        or return $e->die_event;

    if( $xact->xact_finish ) {
        my ($mbts) = $U->fetch_mbts($xactid, $e);
        if( $mbts->balance_owed != 0 ) {
            $logger->info("* re-opening xact $xactid, orig xact_finish is ".$xact->xact_finish);
            $xact->clear_xact_finish;
            $e->update_money_billable_transaction($xact)
                or return $e->die_event;
        } 
    }

    return undef;
}


sub create_bill {
	my( $e, $amount, $type, $xactid ) = @_;

	$logger->info("The system is charging $amount [$type] on xact $xactid");

    # -----------------------------------------------------------------
    # now create the billing
	my $bill = Fieldmapper::money::billing->new;
	$bill->xact($xactid);
	$bill->amount($amount);
	$bill->billing_type($type); 
	$bill->note('SYSTEM GENERATED');
    $e->create_money_billing($bill) or return $e->die_event;

	return undef;
}



# -----------------------------------------------------------------
# Voids overdue fines on the given circ.  if a backdate is 
# provided, then we only void back to the backdate
# -----------------------------------------------------------------
sub void_overdues {
    my( $e, $circ, $backdate ) = @_;

    my $bill_search = { 
        xact => $circ->id, 
        billing_type => OILS_BILLING_TYPE_OVERDUE_MATERIALS 
    };

    if( $backdate ) {
        # ------------------------------------------------------------------
        # Fines for overdue materials are assessed up to, but not including,
        # one fine interval after the fines are applicable.  Here, we add
        # one fine interval to the backdate to ensure that we are not 
        # voiding fines that were applicable before the backdate.
        # ------------------------------------------------------------------

        # if there is a raw time component (e.g. from postgres), 
        # turn it into an interval that interval_to_seconds can parse
        my $duration = $circ->fine_interval;
        $duration =~ s/(\d{2}):(\d{2}):(\d{2})/$1 h $2 m $3 s/o;
        my $interval = OpenSRF::Utils->interval_to_seconds($duration);

        my $date = DateTime::Format::ISO8601->parse_datetime($backdate);
        $backdate = $U->epoch2ISO8601($date->epoch + $interval);
        $logger->info("applying backdate $backdate in overdue voiding");
        $$bill_search{billing_ts} = {'>=' => $backdate};
    }

    my $bills = $e->search_money_billing($bill_search);
    
    for my $bill (@$bills) {
        next if $U->is_true($bill->voided);
        $logger->info("voiding overdue bill ".$bill->id);
        $bill->voided('t');
        $bill->void_time('now');
        $bill->voider($e->requestor->id);
        my $n = $bill->note || "";
        $bill->note("$n\nSystem: VOIDED FOR BACKDATE");
        $e->update_money_billing($bill) or return $e->die_event;
    }

	return undef;
}




__PACKAGE__->register_method(
	method	=> "set_circ_claims_returned",
	api_name	=> "open-ils.circ.circulation.set_claims_returned",
	signature	=> q/
        Sets the circ for the given item as claims returned
        If a backdate is provided, overdue fines will be voided
        back to the backdate
		@param auth
		@param args : barcode, backdate
	/
);

sub set_circ_claims_returned {
    my( $self, $conn, $auth, $args ) = @_;

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;

    my $barcode = $$args{barcode};
    my $backdate = $$args{backdate};

    $logger->info("marking circ for item $barcode as claims returned".
        (($backdate) ? " with backdate $backdate" : ''));

    my $copy = $e->search_asset_copy({barcode=>$barcode, deleted=>'f'})->[0] 
        or return $e->die_event;

    my $circ = $e->search_action_circulation(
        {checkin_time => undef, target_copy => $copy->id})->[0]
            or return $e->die_event;

    $e->allowed('SET_CIRC_CLAIMS_RETURNED', $circ->circ_lib) 
        or return $e->die_event;

    $circ->stop_fines(OILS_STOP_FINES_CLAIMSRETURNED);
	$circ->stop_fines_time('now') unless $circ->stop_fines_time;

    if( $backdate ) {
        # make it look like the circ stopped at the cliams returned time
        $circ->stop_fines_time(clense_ISO8601($backdate));
        my $evt = void_overdues($e, $circ, $backdate);
        return $evt if $evt;
    }

    $e->update_action_circulation($circ) or return $e->die_event;
    $e->commit;
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
	$date = clense_ISO8601($date);
	$circ->due_date($date);
    $e->update_action_circulation($circ) or return $e->die_event;
    $e->commit;

    return $circ->id;
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
		$use_time = clense_ISO8601($use_time);
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
					acp => ['call_number'],
					acn => ['record']
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
			{ order_by => { circ => 'xact_start desc' }, limit => 1 }
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
);
__PACKAGE__->register_method(
	method => 'mark_item',
	api_name => 'open-ils.circ.mark_item_missing',
);

sub mark_item {
	my( $self, $conn, $auth, $copy_id ) = @_;
	my $e = new_editor(authtoken=>$auth, xact =>1);
	return $e->event unless $e->checkauth;

	my $perm = 'MARK_ITEM_MISSING';
	my $stat = OILS_COPY_STATUS_MISSING;

	if( $self->api_name =~ /damaged/ ) {
		$perm = 'MARK_ITEM_DAMAGED';
		$stat = OILS_COPY_STATUS_DAMAGED;
	}

	my $copy = $e->retrieve_asset_copy($copy_id)
		or return $e->event;
	$copy->status($stat);
	$copy->edit_date('now');
	$copy->editor($e->requestor->id);

	$e->update_asset_copy($copy) or return $e->event;


	my $holds = $e->search_action_hold_request(
		{ 
			current_copy => $copy->id,
			fulfillment_time => undef,
			cancel_time => undef,
		}
	);

	$e->commit;

	$logger->debug("reseting holds that target the marked copy");
	OpenILS::Application::Circ::Holds->_reset_hold($e->requestor, $_) for @$holds;

	return 1;
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

	# Find the class the iplements the given hint
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
					acp => [ qw/ location status stat_cat_entry_copy_maps notes age_protect call_number / ],
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

# {"select":{"acp":["id"],"circ":[{"aggregate":true,"transform":"count","alias":"count","column":"id"}]},"from":{"acp":{"circ":{"field":"target_copy","fkey":"id","type":"left"},"acn"{"field":"id","fkey":"call_number"}}},"where":{"+acn":{"record":200057}}


1;
