package OpenILS::Application::Circ;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenILS::Application::Circ::Rules;
use OpenILS::Application::Circ::Survey;
use OpenILS::Application::Circ::StatCat;
use OpenILS::Application::Circ::Holds;
use OpenILS::Application::Circ::Money;

use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
use OpenSRF::Utils;
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
	OpenILS::Application::Circ::Rules->initialize();
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
		{ usr => $target->id } );

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
	Params are login, circid
	login must have SET_CIRC_LOST perms
	Sets a circulation to lost
	NOTES

__PACKAGE__->register_method(
	method	=> "set_circ_lost",
	api_name	=> "open-ils.circ.circulation.set_claims_returned",
	NOTES		=> <<"	NOTES");
	Params are login, circid
	login must have SET_CIRC_MISSING perms
	Sets a circulation to lost
	NOTES

sub set_circ_lost {
	my( $self, $client, $login, $circid ) = @_;
	my( $user, $circ, $evt );

	( $user, $evt ) = $apputils->checkses($login);
	return $evt if $evt;

	( $circ, $evt ) = $apputils->fetch_circulation( $circid );
	return $evt if $evt;

	if($self->api_name =~ /lost/) {
		if($evt = $apputils->checkperms(
			$user->id, $circ->circ_lib, "SET_CIRC_LOST")) {
			return $evt;
		}
		$circ->stop_fines("LOST");		
	}

	if($self->api_name =~ /claims_returned/) {
		if($evt = $apputils->checkperms(
			$user->id, $circ->circ_lib, "SET_CIRC_CLAIMS_RETURNED")) {
			return $evt;
		}
		$circ->stop_fines("CLAIMSRETURNED");
	}

	my $s = $apputils->simplereq(
		'open-ils.storage',
		"open-ils.storage.direct.action.circulation.update", $circ );

	if(!$s) { throw OpenSRF::EX::ERROR ("Error updating circulation with id $circid"); }
}






1;
