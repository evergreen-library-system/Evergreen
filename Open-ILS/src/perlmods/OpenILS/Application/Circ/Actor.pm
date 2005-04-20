package OpenILS::Application::Circ::Actor;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;

my $apputils = "OpenILS::Application::AppUtils";
sub _d { warn "Patron:\n" . Dumper(shift()); }


__PACKAGE__->register_method(
	method	=> "update_patron",
	api_name	=> "open-ils.circ.patron.create",
);

__PACKAGE__->register_method(
	method	=> "update_patron",
	api_name	=> "open-ils.circ.patron.update",
);


sub update_patron {
	my( $self, $client, $patron ) = @_;

	my $session = $apputils->start_db_session();
	my $err = undef;


	# $new_patron is the patron in progress.  $patron is the original patron
	# passed in with the method.  new_patron will change as the components
	# of patron are added/updated.

	try {

		my $new_patron;

		# create/update the patron first so we can use his id
		if( $self->api_name =~ /create/ ) {
			$new_patron = _add_patron($session, _clone_patron($patron));
		} else { 
			$new_patron = $patron; 
		}

		$new_patron = _add_update_addresses($session, $patron, $new_patron);
		$new_patron = _add_update_cards($session, $patron, $new_patron);

		# re-update the patron if anything has happened to him during this process
		$new_patron = _update_patron($session, $new_patron);
		$apputils->commit_db_session($session);

	} catch Error with { 
		my $e = shift;
		$err =  "-*- Failure adding user: $e";
		$apputils->rollback_db_session($session);
		warn $e;
	};

	warn "Patron Update/Create complete\n";

	if($err) { throw OpenSRF::EX::ERROR ($err); }

	return 1;
}


# clone and clear stuff that would break the database
sub _clone_patron {
	my $patron = shift;

	my $new_patron = Fieldmapper::actor::user->new();

	my $fmap = $Fieldmapper::fieldmap;
	no strict; # shallow clone, may be useful in the fieldmapper
	for my $field 
		(keys %{$fmap->{"Fieldmapper::actor::user"}->{'fields'}}) {
			$new_patron->$field( $patron->$field() );
	}
	use strict;

	# clear these
	$new_patron->clear_billing_address();
	$new_patron->clear_mailing_address();
	$new_patron->clear_addresses();
	$new_patron->clear_card();
	$new_patron->clear_cards();
	$new_patron->clear_id();
	$new_patron->clear_isnew();
	$new_patron->clear_changed();
	$new_patron->clear_deleted();

	return $new_patron;
}


sub _add_patron {
	my $session		= shift;
	my $patron		= shift;

	my $req = $session->request(
		"open-ils.storage.direct.actor.user.create",$patron);
	my $id = $req->gather(1);
	if(!$id) { throw OpenSRF::EX::ERROR ("Unable to create new user"); }
	warn "Created new patron with id $id\n";
	$patron->id($id);

	return $patron;
}


sub _update_patron {
	my( $session, $patron) = @_;

	my $req = $session->request(
		"open-ils.storage.direct.actor.user.update",$patron );
	my $status = $req->gather(1);
	if(!$status) { 
		throw new OpenSRF::EX::ERROR 
			("Unknown error updating patron"); 
	}
	return $patron;
}


sub _add_update_addresses {
	my $session = shift;
	my $patron = shift;
	my $new_patron = shift;

	my $current_id; # id of the address before creation

	for my $address (@{$patron->addresses()}) {

		$address->usr($new_patron->id());

		if(ref($address) and $address->isnew()) {
			warn "Adding new address at street " . $address->street1() . "\n";

			$current_id = $address->id();
			$address->clear_id();

			# put the address into the database
			my $req = $session->request(
				"open-ils.storage.direct.actor.user_address.create",
				$address );

			#update the id
			my $id = $req->gather(1);
			if(!$id) { throw OpenSRF::EX::ERROR ("Unable to create new user address"); }

			warn "Created address with id $id\n";

			# update all the necessary id's
			$address->id( $id );
			if( $patron->billing_address() == $current_id ) {
				$new_patron->billing_address($id);
				$new_patron->ischanged(1);
			}

			if( $patron->mailing_address() == $current_id ) {
				$new_patron->mailing_address($id);
				$new_patron->ischanged(1);
			}

		} elsif( ref($address) and $address->ischanged() ) {
			warn "Updating address at street " . $address->street1();
		}
	}

	return $new_patron;
}



sub _add_update_cards {

	my $session = shift;
	my $patron = shift;
	my $new_patron = shift;

	my $virtual_id; #id of the card before creation
	for my $card (@{$patron->cards()}) {

		if(ref($card) and $card->isnew()) {

			$virtual_id = $card->id();
			warn "Adding card with barcode " . $card->barcode() . "\n";
			$card->usr($new_patron->id());
			$card->clear_id();

			my $req = $session->request(
				"open-ils.storage.direct.actor.card.create",
				$card );

			my $id = $req->gather(1);
			warn "Created patron card with id $id\n";

			if(!$id) { throw OpenSRF::EX::ERROR ("Unable to create new user card"); }
			if($patron->card() == $virtual_id) {
				$new_patron->card($id);
				$new_patron->ischanged(1);
			}

		} elsif( ref($card) and $card->ischanged() ) {



		}
	}
	return $new_patron;
}


1;
