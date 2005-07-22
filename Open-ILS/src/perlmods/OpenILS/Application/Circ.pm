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

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $user_obj = $apputils->check_user_session($user_session); 

	if(!$user_id) { $user_id = $user_obj->id(); }

	my $circs = $session->request(
		"open-ils.storage.direct.action.open_circulation.search.usr.atomic", $user_id );
	$circs = $circs->gather(1);

	my @results;
	for my $circ (@$circs) {

		my $copy = $session->request(
			"open-ils.storage.direct.asset.copy.retrieve",
			$circ->target_copy );

		warn "Retrieving record for copy " . $circ->target_copy . "\n";

		my $record = $session->request(
			"open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy",
			$circ->target_copy );

		$copy = $copy->gather(1);
		$record = $record->gather(1);

		use Data::Dumper;
		warn Dumper $circ;
		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch( $record->marc() );
		my $mods = $u->finish_mods_batch();
		$mods->doc_id($record->id());

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
	my $user = $apputils->check_user_session($login_session); 
	my $session = OpenSRF::AppSession->create('open-ils.storage');

	my $circ = $session->request(
		"open-ils.storage.direct.action.circulation.retrieve", $transactionid )->gather(1);

	if($circ) {
		my $title = $session->request(
			"open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy",
			$circ->target_copy )->gather(1);

		if($title) {
			my $u = OpenILS::Utils::ModsParser->new();
			$u->start_mods_batch( $title->marc );
			return $u->finish_mods_batch();
		}
	}

	return undef;	
}





1;
