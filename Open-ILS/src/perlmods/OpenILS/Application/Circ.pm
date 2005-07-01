package OpenILS::Application::Circ;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenILS::Application::Circ::Rules;
use OpenILS::Application::Circ::Survey;
use OpenILS::Application::Circ::StatCat;
use OpenILS::Application::Circ::Holds;

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
);

sub checkouts_by_user {
	my( $self, $client, $user_session, $user_id ) = @_;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $user_obj = $apputils->check_user_session($user_session); 

	if(!$user_id) { $user_id = $user_obj->id(); }

	my $circs = $session->request(
		"open-ils.storage.direct.action.circulation.search.atomic",
      { usr => $user_id, xact_finish => undef } );
	$circs = $circs->gather(1);

	my @results;
	for my $circ (@$circs) {

		my $copy = $session->request(
			"open-ils.storage.direct.asset.copy.retrieve",
			$circ->target_copy );

		my $record = $session->request(
			"open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy",
			$circ->target_copy );

		$copy = $copy->gather(1);
		$record = $record->gather(1);

		my $due_date = 
			OpenSRF::Utils->interval_to_seconds( 
				$circ->duration ) + int(time());
		$circ->due_date($due_date);

		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch( $record->marc() );
		my $mods = $u->finish_mods_batch();
		warn "Doc id is " . $record->id() . "\n";
		$mods->doc_id($record->id());

		push( @results, { copy => $copy, circ => $circ, record => $mods } );
	}

	return \@results;

}







1;
