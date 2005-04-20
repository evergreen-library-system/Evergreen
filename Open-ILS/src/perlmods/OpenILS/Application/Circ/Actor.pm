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
	my $new_patron = _clone_patron($patron);

	_d($new_patron);

	try {

		# create/update the patron first so we can use his id
		$new_patron = _add_update_patron($patron, $new_patron, $session);
		$new_patron = _add_update_addresses($patron, $new_patron, $session);
		_d($new_patron);
		$new_patron = _add_update_cards($patron, $new_patron, $session);
		_d($new_patron);
		$apputils->commit_db_session($session);

	} catch Error with { 
		my $e = shift;
		warn " -*- Failure adding user: \n$e\n";
		$apputils->rollback_db_session($session);
	};

	warn "Patron Update/Create complete\n";

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

	return $new_patron;
}


sub _add_update_patron {
	my $patron		= shift;
	my $new_patron	= shift;
	my $session		= shift;

	if($patron->isnew()) {
		warn Dumper $new_patron;
		my $req = $session->request(
			"open-ils.storage.direct.actor.user.create",$new_patron);
		my $id = $req->gather(1);
		if(!$id) { throw OpenSRF::EX::ERROR ("Unable to create new user"); }
		warn "Created new patron with id $id\n";
		$new_patron->id($id);

	} elsif( $patron->ischanged() ) {

	}
	return $new_patron;
}


sub _add_update_addresses {
	my $patron = shift;
	my $new_patron = shift;
	my $session = shift;
	my @complete = ();

	#my @addresses = @{$patron->addresses()};
	#$patron->addresses([]);

	my $current_id;

	for my $address (@{$patron->addresses()}) {
		next if ( grep { $_->street1() eq 
				$address->street1() } @complete );

		$address->usr($new_patron->id());

		if(ref($address) and $address->isnew()) {
			warn "Adding new address at street " . $address->street1();

			$current_id = $address->id();
			$address->clear_id();

			warn "Adding new address: " . Dumper($address);
			warn "User id: " . $address->usr() . "\n";

			# put the address into the database
			my $req = $session->request(
				"open-ils.storage.direct.actor.org_address.create",
				$address );

			#update the id
			my $id = $req->gather(1);
			if(!$id) { throw OpenSRF::EX::ERROR ("Unable to create new user address"); }

			warn "Created address with id $id\n";

			# update all the necessary id's
			$address->id( $id );
			if( $patron->billing_address() ) {
				if( $patron->billing_address->id() == $current_id ) {
					$new_patron->billing_address($id);
				}
			} else {
				#patron has not billing address
			}

			if( ref($patron->mailing_address()) ) {
				if( $patron->mailing_address()->id() == $current_id ) {
					$new_patron->mailing_address($id);
				}
			} else {
				# patron does not have a billing address
			}

		} elsif( ref($address) and $address->ischanged() ) {
			warn "Updating address at street " . $address->street1();
		}
	}

	return $new_patron;
}



sub _add_update_cards {
	my $patron = shift;
	my $session = shift;

	for my $card (@{$patron->cards()}) {

		if(ref($card) and $card->isnew()) {
			# create the card
		} elsif( ref($card) and $card->ischanged() ) {
			#update the card
		}
	}
	return $patron;
}


1;
