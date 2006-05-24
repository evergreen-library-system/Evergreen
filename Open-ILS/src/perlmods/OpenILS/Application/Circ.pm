package OpenILS::Application::Circ;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenILS::Application::Circ::Circulate;
use OpenILS::Application::Circ::Survey;
use OpenILS::Application::Circ::StatCat;
use OpenILS::Application::Circ::Holds;
use OpenILS::Application::Circ::Money;
use OpenILS::Application::Circ::NonCat;
use OpenILS::Application::Circ::CopyLocations;

use DateTime;
use DateTime::Format::ISO8601;

use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;
use OpenSRF::Utils qw/:datetime/;
use OpenILS::Utils::ModsParser;
use OpenILS::Event;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::Editor;
#my $logger = "OpenSRF::Utils::Logger";


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
	my($reqr, $evt) = $U->checksesperm($a, 'VIEW_CIRCULATIONS');
	return $evt if $evt;
	my $circ;
	($circ, $evt) = $U->fetch_circulation($i);
	return $evt if $evt;
	return $circ;
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
		'open-ils.storage',
		"open-ils.storage.direct.action.open_circulation.search.atomic", 
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
		'open-ils.storage',
		"open-ils.storage.direct.action.open_circulation.search.atomic", 
		{ usr => $target->id, checkin_time => undef } );
#		{ usr => $target->id } );
}


__PACKAGE__->register_method(
	method	=> "checkouts_by_user_opac",
	api_name	=> "open-ils.circ.actor.user.checked_out.opac",);

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
	method	=> "set_circ_lost",
	api_name	=> "open-ils.circ.circulation.set_lost",
	NOTES		=> <<"	NOTES");
	Params are login, barcode
	login must have SET_CIRC_LOST perms
	Sets a circulation to lost
	NOTES

__PACKAGE__->register_method(
	method	=> "set_circ_lost",
	api_name	=> "open-ils.circ.circulation.set_claims_returned",
	NOTES		=> <<"	NOTES");
	Params are login, barcode
	login must have SET_CIRC_MISSING perms
	Sets a circulation to lost
	NOTES

sub set_circ_lost {
	my( $self, $client, $login, $args ) = @_;
	my( $user, $circ, $copy, $evt );

	my $barcode		= $$args{barcode};
	my $backdate	= $$args{backdate};

	( $user, $evt ) = $U->checkses($login);
	return $evt if $evt;

	# Grab the related copy
	($copy, $evt) = $U->fetch_copy_by_barcode($barcode);
	return $evt if $evt;

	my $isclaims	= $self->api_name =~ /claims_returned/;
	my $islost		= $self->api_name =~ /lost/;
	my $session		= $U->start_db_session(); 

	# grab the circulation
	( $circ ) = $U->fetch_open_circulation( $copy->id );
	return 1 unless $circ;

	if($islost) {
		$evt  = _set_circ_lost($copy, $circ, $user, $session) if $islost;
		return $evt if $evt;
	}

	if($isclaims) {
		$evt = _set_circ_claims_returned(
			$user, $circ, $session, $backdate );
		return $evt if $evt;

#		$evt = $U->check_perms($user->id, $circ->circ_lib, 'SET_CIRC_CLAIMS_RETURNED');
#		return $evt if $evt;
#		$circ->stop_fines("CLAIMSRETURNED");
#
#		$logger->activity("user ".$user->id." marking circ".  $circ->id. " as claims returned");
#
#		# allow the caller to backdate the circulation and void any fines
#		# that occurred after the backdate
#		if($backdate) {
#			OpenILS::Application::Circ::Circulate::_checkin_handle_backdate(
#				$backdate, $circ, $user, $session );
#		}
#
#		my $patron;
#		($patron, $evt) = $U->fetch_user($circ->usr);
#		return $evt if $evt;
#		$patron->claims_returned_count( 
#			$patron->claims_returned_count + 1 );
#
#		my $stat = $U->storagereq(
#			'open-ils.storage.direct.actor.user.update', $patron );
#		return $U->DB_UPDATE_FAILED($patron) unless $stat;

	}

	$circ->stop_fines_time('now') unless $circ->stop_fines_time('now');
	my $s = $session->request(
		"open-ils.storage.direct.action.circulation.update", $circ )->gather(1);

	return $U->DB_UPDATE_FAILED($circ) unless defined($s);
	$U->commit_db_session($session);

	return 1;
}

sub _set_circ_lost {
	my( $copy, $circ, $reqr, $session ) = @_;

	my $evt = $U->check_perms($reqr->id, $circ->circ_lib, 'SET_CIRC_LOST');
	return $evt if $evt;

	$logger->activity("user ".$reqr->id." marking copy ".$copy->id.
		" lost  for circ ".  $circ->id. " and checking for necessary charges");

	my $newstat = $U->copy_status_from_name('lost');
	if( $copy->status ne $newstat->id ) {

		$copy->status($newstat);
		$U->update_copy(
			copy		=> $copy, 
			editor	=> $reqr->id, 
			session	=> $session);
	}

	# if the copy has a price defined and/or a processing fee, bill the patron

	my $copy_price = $copy->price || 0;

	# If the copy has a price configured, charge said price to the user
	if($copy_price) {
		$evt = _make_bill($session, $copy_price, 'Lost Materials', $circ->id);
		return $evt if $evt;
	}

	# if the location that owns the copy has a processing fee, charge the user
	my $owner = $U->fetch_copy_owner($copy->id);
	$logger->info("circ fetching org settings for $owner to determine processing fee");

	my $settings = $U->simplereq(
		'open-ils.actor', 'open-ils.actor.org_unit.settings.retrieve', $owner );
	my $fee = $settings->{'circ.lost_materials_processing_fee'} || 0;

	if( $fee ) {
		$evt = _make_bill($session, $fee, 'Lost Materials Processing Fee', $circ->id);
		return $evt if $evt;
	}
	
	$circ->stop_fines("LOST");		
	return undef;
}

sub _make_bill {
	my( $session, $amount, $type, $xactid ) = @_;

	$logger->activity("The system is charging $amount ".
		" [$type] for lost materials on circulation $xactid");

	my $bill = Fieldmapper::money::billing->new;

	$bill->xact($xactid);
	$bill->amount($amount);
	$bill->billing_type($type); # - XXX these strings should be configurable some day
	$bill->note('SYSTEM GENERATED');

	my $id = $session->request(
		'open-ils.storage.direct.money.billing.create', $bill )->gather(1);

	return $U->DB_UPDATE_FAILED($bill) unless defined $id;
	return undef;
}

sub _set_circ_claims_returned {
	my( $reqr, $circ, $session, $backdate ) = @_;

	my $evt = $U->check_perms($reqr->id, $circ->circ_lib, 'SET_CIRC_CLAIMS_RETURNED');
	return $evt if $evt;
	$circ->stop_fines("CLAIMSRETURNED");

	$logger->activity("user ".$reqr->id.
		" marking circ".  $circ->id. " as claims returned");

	# allow the caller to backdate the circulation and void any fines
	# that occurred after the backdate
	if($backdate) {
		OpenILS::Application::Circ::Circulate::_checkin_handle_backdate(
			$backdate, $circ, $reqr, $session );
	}

	return undef;
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
	my( $s, $c, $authtoken, $circid, $date ) = @_;
	my ($circ, $evt) = $U->fetch_circulation($circid);
	return $evt if $evt;

	my $reqr;
	($reqr, $evt) = $U->checkses($authtoken);
	return $evt if $evt;

	$evt = $U->check_perms($reqr->id, $circ->circ_lib, 'CIRC_OVERRIDE_DUE_DATE');
	return $evt if $evt;

	$date = clense_ISO8601($date);
	$logger->activity("user ".$reqr->id.
		" updating due_date on circ $circid: $date");

	$circ->due_date($date);
	my $stat = $U->storagereq(
		'open-ils.storage.direct.action.circulation.update', $circ);
	return $U->DB_UPDATE_FAILED unless defined $stat;
	return $stat;
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

sub create_in_house_use {
	my( $self, $client, $authtoken, $params ) = @_;

	my( $staff, $evt, $copy );
	my $org			= $params->{location};
	my $copyid		= $params->{copyid};
	my $count		= $params->{count} || 1;
	my $use_time	= $params->{use_time} || 'now';

	if(!$copyid) {
		my $barcode = $params->{barcode};
		($copy, $evt) = $U->fetch_copy_by_barcode($barcode);
		return $evt if $evt;
		$copyid = $copy->id;
	}

	($staff, $evt) = $U->checkses($authtoken);
	return $evt if $evt;

	($copy, $evt) = $U->fetch_copy($copyid) unless $copy;
	return $evt if $evt;

	$evt = $U->check_perms($staff->id, $org, 'CREATE_IN_HOUSE_USE');
	return $evt if $evt;

	$logger->activity("User " . $staff->id .
		" creating $count in-house use(s) for copy $copyid at location $org");

	if( $use_time ne 'now' ) {
		$use_time = clense_ISO8601($use_time);
		$logger->debug("in_house_use setting use time to $use_time");
	}

	my @ids;
	for(1..$count) {
		my $ihu = Fieldmapper::action::in_house_use->new;

		$ihu->item($copyid);
		$ihu->staff($staff->id);
		$ihu->org_unit($org);
		$ihu->use_time($use_time);

		my $id = $U->simplereq(
			'open-ils.storage',
			'open-ils.storage.direct.action.in_house_use.create', $ihu );

		return $U->DB_UPDATE_FAILED($ihu) unless $id;
		push @ids, $id;
	}

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

sub view_circs {
	my( $self, $client, $authtoken, $copyid, $count ) = @_; 

	my( $requestor, $evt ) = $U->checksesperm(
			$authtoken, 'VIEW_COPY_CHECKOUT_HISTORY' );
	return $evt if $evt;

	return [] unless $count;

	my $circs = $U->storagereq(
		'open-ils.storage.direct.action.circulation.search_where.atomic',
			{ 
				target_copy => $copyid, 
#				opac_renewal => 'f',   
#				desk_renewal => 'f',
#				phone_renewal => 'f',
			}, 
			{ 
				limit => $count, 
				order_by => "xact_start DESC" 
			} );

#	my @users;
#	push(@users, $_->usr) for @$circs;
#	return \@users;

	return $circs;
}


__PACKAGE__->register_method(
	method	=> "circ_count",
	api_name	=> "open-ils.circ.circulation.count",
	notes		=> q/
		Returns the number of times the item has circulated
		@param copyid The copy to check
	/);

sub circ_count {
	my( $self, $client, $copyid ) = @_; 
	my $e = OpenILS::Utils::Editor->new;
	my $circs = $e->search_action_circulation({target_copy => $copyid}, {idlist=>1});
	return scalar @$circs;
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
			return $U->storagereq(
				'open-ils.storage.direct.asset.copy_note.search_where.atomic',
				{ owning_copy => $id, pub => 't' } );
		} else {
			( $r, $evt ) = $U->checksesperm($authtoken, 'VIEW_COPY_NOTES');
			return $evt if $evt;
			return $U->storagereq(
				'open-ils.storage.direct.asset.copy_note.search.owning_copy.atomic', $id );
		}

	} elsif( $self->api_name =~ /call_number/ ) {
		if( $$args{pub} ) {
			return $U->storagereq(
				'open-ils.storage.direct.asset.call_number_note.search_where.atomic',
				{ call_number => $id, pub => 't' } );
		} else {
			( $r, $evt ) = $U->checksesperm($authtoken, 'VIEW_VOLUME_NOTES');
			return $evt if $evt;
			return $U->storagereq(
				'open-ils.storage.direct.asset.call_number_note.search.call_number.atomic', $id );
		}

	} elsif( $self->api_name =~ /title/ ) {
		if( $$args{pub} ) {
			return $U->storagereq(
				'open-ils.storage.direct.bilbio.record_note.search_where.atomic',
				{ record => $id, pub => 't' } );
		} else {
			( $r, $evt ) = $U->checksesperm($authtoken, 'VIEW_TITLE_NOTES');
			return $evt if $evt;
			return $U->storagereq(
				'open-ils.storage.direct.biblio.record_note.search.record.atomic', $id );
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
	my( $cnowner, $requestor, $evt );

	($cnowner, $evt) = $U->fetch_copy_owner($note->owning_copy);
	return $evt if $evt;
	($requestor, $evt) = $U->checkses($authtoken);
	return $evt if $evt;
	$evt = $U->check_perms($requestor->id, $cnowner, 'CREATE_COPY_NOTE');
	return $evt if $evt;

	$note->create_date('now');
	$note->creator($requestor->id);
	$note->pub( ($note->pub) ? 't' : 'f' );

	my $id = $U->storagereq(
		'open-ils.storage.direct.asset.copy_note.create', $note );
	return $U->DB_UPDATE_FAILED($note) unless $id;

	$logger->activity("User ".$requestor->id." created a new copy ".
		"note [$id] for copy ".$note->owning_copy." with text ".$note->value);

	return $id;
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
	my( $requestor, $note, $owner, $evt );

	($requestor, $evt) = $U->checkses($authtoken);
	return $evt if $evt;

	($note, $evt) = $U->fetch_copy_note($noteid);
	return $evt if $evt;

	if( $note->creator ne $requestor->id ) {
		($owner, $evt) = $U->fetch_copy_onwer($note->owning_copy);
		return $evt if $evt;
		$evt = $U->check_perms($requestor->id, $owner, 'DELETE_COPY_NOTE');
		return $evt if $evt;
	}

	my $stat = $U->storagereq(
		'open-ils.storage.direct.asset.copy_note.delete', $noteid );
	return $U->DB_UPDATE_FAILED($noteid) unless $stat;

	$logger->activity("User ".$requestor->id." deleted copy note $noteid");
	return 1;
}


1;
