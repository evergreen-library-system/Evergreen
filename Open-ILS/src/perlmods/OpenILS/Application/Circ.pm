package OpenILS::Application::Circ;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenILS::Application::Circ::Circulate;
use OpenILS::Application::Circ::Rules;
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
#my $logger = "OpenSRF::Utils::Logger";


# ------------------------------------------------------------------------
# Top level Circ package;
# ------------------------------------------------------------------------

sub initialize {
	my $self = shift;
	OpenILS::Application::Circ::Circulate->initialize();
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


	# if setting to list, update the copy's statua
	if( $islost ) {
		my $newstat = $U->copy_status_from_name('lost') if $islost;
		if( $copy->status ne $newstat->id ) {
			$copy->status($newstat);
			$U->update_copy(copy => $copy, editor => $user->id, session => $session);
		}
	}

	# grab the circulation
	( $circ ) = $U->fetch_open_circulation( $copy->id );
	return 1 unless $circ;


	if($islost) {
		$evt = $U->check_perms($user->id, $circ->circ_lib, 'SET_CIRC_LOST');
		return $evt if $evt;
		$circ->stop_fines("LOST");		
	}

	if($isclaims) {

		$evt = $U->check_perms($user->id, $circ->circ_lib, 'SET_CIRC_CLAIMS_RETURNED');
		return $evt if $evt;
		$circ->stop_fines("CLAIMSRETURNED");

		# allow the caller to backdate the circulation and void any fines
		# that occurred after the backdate
		if($backdate) {
			OpenILS::Application::Circ::Circulate::_checkin_handle_backdate(
				$backdate, $circ, $user, $session );
		}
	}

	my $s = $session->request(
		"open-ils.storage.direct.action.circulation.update", $circ )->gather(1);

	return $U->DB_UPDATE_FAILED($circ) unless defined($s);
	$U->commit_db_session($session);

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
	my( $s, $c, $authtoken, $circid, $date ) = @_;
	my ($circ, $evt) = $U->fetch_circulation($circid);
	return $evt if $evt;

	my $reqr;
	($reqr, $evt) = $U->checkses_perms(
		$authtoken, $circ->circ_lib, 'CIRC_OVERRIDE_DUE_DATE');
	return $evt if $evt;

	$date = clense_ISO8601($date);
	$logger->activity("user ".$reqr->id." updating due_date on circ $circid: $date");

	$circ->due_date($date);
	my $stat = $U->storagereq(
		'open-ils.storage.action.circulation.update', $circ);
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
	method	=> "view_circ_patrons",
	api_name	=> "open-ils.circ.copy_checkout_history.retrieve",
	notes		=> q/
		Retrieves the last X users who checked out a given copy
		@param authtoken The login session key
		@param copyid The copy to check
		@param count How far to go back in the item history
		@return An array of patron ids
	/);

sub view_circ_patrons {
	my( $self, $client, $authtoken, $copyid, $count ) = @_; 

	my( $requestor, $evt ) = $U->checksesperm(
			$authtoken, 'VIEW_COPY_CHECKOUT_HISTORY' );
	return $evt if $evt;

	return [] unless $count;

	my $circs = $U->storagereq(
		'open-ils.storage.direct.action.circulation.search_where.atomic',
			{ 
				target_copy => $copyid, 
				opac_renewal => 'f',   
				desk_renewal => 'f',
				phone_renewal => 'f',
			}, 
			{ 
				limit => $count, 
				order_by => "xact_start DESC" 
			} );


	my @users;
	push(@users, $_->usr) for @$circs;
	return \@users;
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
			( $r, $evt ) = $U->checksesperms($authtoken, 'VIEW_COPY_NOTES');
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
			( $r, $evt ) = $U->checksesperms($authtoken, 'VIEW_VOLUME_NOTES');
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
			( $r, $evt ) = $U->checksesperms($authtoken, 'VIEW_TITLE_NOTES');
			return $evt if $evt;
			return $U->storagereq(
				'open-ils.storage.direct.asset.call_number_note.search.call_number.atomic', $id );
		}
	}

	return undef;
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

=head this method is really inefficient - get rid of me

__PACKAGE__->register_method(
	method		=> 'note_batch',
	api_name		=> 'open-ils.circ.biblio_notes.public.batch.retrieve',
	signature	=> q/
		Returns a set of notes for a given set of titles, volumes, and copies.
		@param titleid The id of the title who's notes are retrieving
		@return A list like so:
			{
				"titles"		: [ { id : $id, notes : [ n1, n2 ] },... ]
				"volumes"	: [ { id : $id, notes : [ n1, n2 ] },... ]
				"copies"		: [ { id : $id, notes : [ n1, n2 ] },... ]
			}
	/
);

sub note_batch {
	my( $self, $conn, $titleid ) = @_;

	my @copies;
	my $cns = $U->storagereq(
		'open-ils.storage.id_list.asset.call_number.search_where.atomic', 
		{ record => $titleid, deleted => 'f' } );
		#'open-ils.storage.id_list.asset.call_number.search.record.atomic', $titleid );

	for my $c (@$cns) {
		my $copyids = $U->storagereq(
			#'open-ils.storage.id_list.asset.copy.search.call_number.atomic', $c);
			'open-ils.storage.id_list.asset.copy.search_where.atomic', { call_number => $c, deleted => 'f' });
		push(@copies, @$copyids);
	}

	return _note_batch( { titles => [$titleid], volumes => $cns, copies => \@copies} );
}


sub _note_batch {
	my $args = shift;

	my %resp;
	$resp{titles}	= [];
	$resp{volumes} = [];
	$resp{copies}	= [];

	my $titles	= (ref($$args{titles})) ? $$args{titles} : [];
	my $volumes = (ref($$args{volumes})) ? $$args{volumes} : [];
	my $copies	= (ref($$args{copies})) ? $$args{copies} : [];

	for my $title (@$titles) {
		my $notes = $U->storagereq(
			'open-ils.storage.direct.biblio.record_note.search_where.atomic', 
			{ record => $title, pub => 't' });
		push(@{$resp{titles}}, {id => $title, notes => $notes}) if @$notes;
	}

	for my $volume (@$volumes) {
		my $notes = $U->storagereq(
			'open-ils.storage.direct.asset.call_number_note.search_where.atomic',
			{ call_number => $volume, pub => 't' });
		push( @{$resp{volumes}}, {id => $volume, notes => $notes} ) if @$notes;
	}


	for my $copy (@$copies) {
		$logger->debug("Fetching copy notes for copy $copy");
		my $notes = $U->storagereq(
			'open-ils.storage.direct.asset.copy_note.search_where.atomic',
			{ owning_copy => $copy, pub => 't' });
		push( @{$resp{copies}}, { id => $copy, notes => $notes }) if @$notes;
	}

	return \%resp;
}

=cut







1;
