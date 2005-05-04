package OpenILS::Application::Actor;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Search::Actor;

my $apputils = "OpenILS::Application::AppUtils";
sub _d { warn "Patron:\n" . Dumper(shift()); }
my $cache_client = OpenSRF::Utils::Cache->new( "global", 0 );


__PACKAGE__->register_method(
	method	=> "update_patron",
	api_name	=> "open-ils.actor.patron.update",
);


sub update_patron {
	my( $self, $client, $user_session, $patron ) = @_;

	my $session = $apputils->start_db_session();
	my $err = undef;

	warn $user_session . " " . $patron . "\n";
	_d($patron);

	my $user_obj = 
		OpenILS::Application::AppUtils->check_user_session( 
				$user_session ); #throws EX on error

	# XXX does this user have permission to add/create users.  Granularity?

	# $new_patron is the patron in progress.  $patron is the original patron
	# passed in with the method.  new_patron will change as the components
	# of patron are added/updated.

	my $new_patron;

	try {
		# create/update the patron first so we can use his id
		if( $patron->isnew() ) {
			$new_patron = _add_patron(
					$session, _clone_patron($patron));
		} else { 
			$new_patron = $patron; 
		}

		$new_patron = _add_update_addresses($session, $patron, $new_patron);
		$new_patron = _add_update_cards($session, $patron, $new_patron);

		# re-update the patron if anything has happened to him during this process
		if($new_patron->ischanged()) {
			$new_patron = _update_patron($session, $new_patron);
		}
		$apputils->commit_db_session($session);

	} catch Error with { 
		my $e = shift;
		$err =  "-*- Failure adding user: $e";
		$apputils->rollback_db_session($session);
		warn $err;
	};

	if($err) { throw OpenSRF::EX::ERROR ($err); }
	warn "Patron Update/Create complete\n";
	return flesh_user($new_patron->id());
}


sub flesh_user {
	my $id = shift;
	my $session = shift;
	my $kill = 0;

	if(!$session) {
		$session = OpenSRF::AppSession->create("open-ils.storage");
		$kill = 1;
	}

	# grab the user with the given card
	my $ureq = $session->request(
			"open-ils.storage.direct.actor.user.retrieve",
			$id);
	my $user = $ureq->gather(1);

	# grab the cards
	my $cards_req = $session->request(
			"open-ils.storage.direct.actor.card.search.usr",
			$user->id() );
	$user->cards( $cards_req->gather(1) );

	my $add_req = $session->request(
			"open-ils.storage.direct.actor.user_address.search.usr",
			$user->id() );
	$user->addresses( $add_req->gather(1) );

	if($kill) { $session->disconnect(); }
	$user->clear_passwd();
	warn Dumper $user;

	return $user;

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

	warn "Creating new patron\n";
	_d($patron);

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

	warn "updating patron " . $patron->usrname() . "\n";
	my $req = $session->request(
		"open-ils.storage.direct.actor.user.update",$patron );
	my $status = $req->gather(1);
	if(!defined($status)) { 
		throw OpenSRF::EX::ERROR 
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
			$address = _add_address($session,$address);

			if( $patron->billing_address() == $current_id ) {
				$new_patron->billing_address($address->id());
				$new_patron->ischanged(1);
			}

			if( $patron->mailing_address() == $current_id ) {
				$new_patron->mailing_address($address->id());
				$new_patron->ischanged(1);
			}

		} elsif( ref($address) and $address->ischanged() ) {
			warn "Updating address at street " . $address->street1();
			$address->usr($new_patron->id());
			_update_address($session,$address);

		} elsif( ref($address) and $address->isdeleted() ) {
			warn "Deleting address at street " . $address->street1();

			if( $address->id() == $new_patron->mailing_address() ) {
				$new_patron->clear_mailing_address();
				_update_patron($session, $new_patron);
			}

			if( $address->id() == $new_patron->billing_address() ) {
				$new_patron->clear_billing_address();
				_update_patron($session, $new_patron);
			}

			_delete_address($session,$address);
		}
	}

	return $new_patron;
}


# adds an address to the db and returns the address with new id
sub _add_address {
	my($session, $address) = @_;
	$address->clear_id();

	# put the address into the database
	my $req = $session->request(
		"open-ils.storage.direct.actor.user_address.create",
		$address );

	#update the id
	my $id = $req->gather(1);
	if(!$id) { 
		throw OpenSRF::EX::ERROR 
			("Unable to create new user address"); 
	}

	warn "Created address with id $id\n";

	# update all the necessary id's
	$address->id( $id );
	return $address;
}


sub _update_address {
	my( $session, $address ) = @_;
	my $req = $session->request(
		"open-ils.storage.direct.actor.user_address.update",
		$address );
	my $status = $req->gather(1);
	if(!defined($status)) { 
		throw OpenSRF::EX::ERROR 
			("Unknown error updating address"); 
	}
	return $address;
}



sub _add_update_cards {

	my $session = shift;
	my $patron = shift;
	my $new_patron = shift;

	my $virtual_id; #id of the card before creation
	for my $card (@{$patron->cards()}) {

		$card->usr($new_patron->id());

		if(ref($card) and $card->isnew()) {

			$virtual_id = $card->id();
			$card = _add_card($session,$card);

			if($patron->card() == $virtual_id) {
				$new_patron->card($card->id());
				$new_patron->ischanged(1);
			}

		} elsif( ref($card) and $card->ischanged() ) {
			$card->usr($new_patron->id());
			_update_card($session, $card);
		}
	}
	return $new_patron;
}


# adds an card to the db and returns the card with new id
sub _add_card {
	my( $session, $card ) = @_;
	$card->clear_id();

	warn "Adding card with barcode " . $card->barcode() . "\n";
	my $req = $session->request(
		"open-ils.storage.direct.actor.card.create",
		$card );

	my $id = $req->gather(1);
	if(!$id) { 
		throw OpenSRF::EX::ERROR 
			("Unknown error creating card"); 
	}

	$card->id($id);
	warn "Created patron card with id $id\n";
	return $card;
}


sub _update_card {
	my( $session, $card ) = @_;
	warn Dumper $card;

	my $req = $session->request(
		"open-ils.storage.direct.actor.card.update",
		$card );
	my $status = $req->gather(1);
	if(!defined($status)) { 
		throw OpenSRF::EX::ERROR 
			("Unknown error updating card"); 
	}
	return $card;
}




sub _delete_address {
	my( $session, $address ) = @_;

	warn "Deleting address " . $address->street1() . "\n";

	my $req = $session->request(
		"open-ils.storage.direct.actor.user_address.delete",
		$address );
	my $status = $req->gather(1);
	if(!defined($status)) { 
		throw OpenSRF::EX::ERROR 
			("Unknown error updating address"); 
	}
	warn "Delete address status is $status\n";
}




__PACKAGE__->register_method(
	method	=> "search_username",
	api_name	=> "open-ils.actor.user.search.username",
);

sub search_username {
	my($self, $client, $username) = @_;
	my $users = OpenILS::Application::AppUtils->simple_scalar_request(
			"open-ils.storage", 
			"open-ils.storage.direct.actor.user.search.usrname",
			$username );
	return $users;
}


__PACKAGE__->register_method(
	method	=> "user_retrieve_by_barcode",
	api_name	=> "open-ils.actor.user.fleshed.retrieve_by_barcode",
);

sub user_retrieve_by_barcode {
	my($self, $client, $barcode) = @_;
	warn "Searching for user with barcode $barcode\n";

	my $session = OpenSRF::AppSession->create("open-ils.storage");

	# find the card with the given barcode
	my $creq	= $session->request(
			"open-ils.storage.direct.actor.card.search.barcode",
			$barcode );
	my $card = $creq->gather(1);
	$card = $card->[0];
	my $user = flesh_user($card->usr(), $session);
	$session->disconnect();
	return $user;

}




__PACKAGE__->register_method(
	method	=> "get_org_types",
	api_name	=> "open-ils.actor.org_types.retrieve",
);
my $org_types;
sub get_org_types {
	my($self, $client) = @_;

	return $org_types if $org_types;
	 return $org_types = 
		 $apputils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.actor.org_unit_type.retrieve.all.atomic" );
}


__PACKAGE__->register_method(
	method	=> "get_user_profiles",
	api_name	=> "open-ils.actor.user.profiles.retrieve",
);

my $user_profiles;
sub get_user_profiles {
	return $user_profiles if $user_profiles;

	return $user_profiles = 
		$apputils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.actor.profile.retrieve.all.atomic");
}



__PACKAGE__->register_method(
	method	=> "get_user_ident_types",
	api_name	=> "open-ils.actor.user.ident_types.retrieve",
);
my $ident_types;
sub get_user_ident_types {
	return $ident_types if $ident_types;
	return $ident_types = 
		$apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.config.identification_type.retrieve.all.atomic" );
}




__PACKAGE__->register_method(
	method	=> "get_org_unit",
	api_name	=> "open-ils.actor.org_unit.retrieve",
);

sub get_org_unit {

	my( $self, $client, $user_session ) = @_;

	my $user_obj = 
		OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error

	my $home_ou = OpenILS::Application::AppUtils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.actor.org_unit.retrieve", 
		$user_obj->home_ou );

	return $home_ou;
}


# build the org tree

__PACKAGE__->register_method(
	method	=> "get_org_tree",
	api_name	=> "open-ils.actor.org_tree.retrieve",
	argc		=> 1, 
	note		=> "Returns the entire org tree structure",
);

sub get_org_tree {
	my( $self, $client) = @_;

	# see if it's in the cache
	warn "Getting ORG Tree\n";
	my $tree = $cache_client->get_cache('orgtree');
	if($tree) { 
		warn "Found orgtree in cache. returning...\n";
		return $tree; 
	}

	my $orglist = $apputils->simple_scalar_request( 
		"open-ils.storage", 
		"open-ils.storage.direct.actor.org_unit.retrieve.all.atomic" );

	$tree = $self->build_org_tree($orglist);
	$cache_client->put_cache('orgtree', $tree);

	return $tree;

}

# turns an org list into an org tree
sub build_org_tree {

	my( $self, $orglist) = @_;

	return $orglist unless ( 
			ref($orglist) and @$orglist > 1 );

	my @list = sort { 
		$a->ou_type <=> $b->ou_type ||
		$a->name cmp $b->name } @$orglist;

	for my $org (@list) {

		next unless ($org and defined($org->parent_ou));
		my ($parent) = grep { $_->id == $org->parent_ou } @list;
		next unless $parent;

		$parent->children([]) unless defined($parent->children); 
		push( @{$parent->children}, $org );
	}

	return $list[0];

}


__PACKAGE__->register_method(
	method	=> "get_org_descendants",
	api_name	=> "open-ils.actor.org_tree.descendants.retrieve"
);

# depth is optional.  org_unit is the id
sub get_org_descendants {
	my( $self, $client, $org_unit, $depth ) = @_;
	my $orglist = $apputils->simple_scalar_request(
			"open-ils.storage", 
			"open-ils.storage.actor.org_unit.descendants.atomic",
			$org_unit, $depth );
	return $self->build_org_tree($orglist);
}


__PACKAGE__->register_method(
	method	=> "get_org_ancestors",
	api_name	=> "open-ils.actor.org_tree.ancestors.retrieve"
);

# depth is optional.  org_unit is the id
sub get_org_ancestors {
	my( $self, $client, $org_unit, $depth ) = @_;
	my $orglist = $apputils->simple_scalar_request(
			"open-ils.storage", 
			"open-ils.storage.actor.org_unit.ancestors.atomic",
			$org_unit, $depth );
	return $self->build_org_tree($orglist);
}


__PACKAGE__->register_method(
	method	=> "get_standings",
	api_name	=> "open-ils.actor.standings.retrieve"
);

my $user_standings;
sub get_standings {
	return $user_standings if $user_standings;
	return $user_standings = 
		$apputils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.config.standing.retrieve.all.atomic" );
}



__PACKAGE__->register_method(
	method	=> "get_my_org_path",
	api_name	=> "open-ils.actor.org_unit.full_path.retrieve"
);

sub get_my_org_path {
	my( $self, $client, $user_session, $org_id ) = @_;
	my $user_obj = $apputils->check_user_session($user_session); 
	if(!defined($org_id)) { $org_id = $user_obj->home_ou; }

	return $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.actor.org_unit.full_path.atomic",
		$org_id );
}


__PACKAGE__->register_method(
	method	=> "patron_adv_search",
	api_name	=> "open-ils.actor.patron.search.advanced" );

sub patron_adv_search {
	my( $self, $client, $staff_login, $search_hash ) = @_;

	use Data::Dumper;
	warn "patron adv with $staff_login and search " . 
		Dumper($search_hash) . "\n";
}








1;




__END__


some old methods that may be good to keep around for now

sub _delete_card {
	my( $session, $card ) = @_;

	warn "Deleting card with barcode " . $card->barcode() . "\n";
	my $req = $session->request(
		"open-ils.storage.direct.actor.card.delete",
		$card );
	my $status = $req->gather(1);
	if(!defined($status)) { 
		throw OpenSRF::EX::ERROR 
			("Unknown error updating card"); 
	}
}



# deletes the patron and any attached addresses and cards
__PACKAGE__->register_method(
	method	=> "delete_patron",
	api_name	=> "open-ils.actor.patron.delete",
);

sub delete_patron {

	my( $self, $client, $patron ) = @_;
	my $session = $apputils->start_db_session();
	my $err = undef;

	try {

		$patron->clear_mailing_address();
		$patron->clear_billing_address();
		$patron->ischanged(1);

		_update_patron($session, $patron);
		_delete_address($session,$_) for (@{$patron->addresses()});
		_delete_card($session,$_) for (@{$patron->cards()});
		_delete_patron($session,$patron);
		$apputils->commit_db_session($session);

	} catch Error with {
		my $e = shift;
		$err =  "-*- Failure deleting user: $e";
		$apputils->rollback_db_session($session);
		warn $err;
	};

	if($err) { throw OpenSRF::EX::ERROR ($err); }
	warn "Patron Delete complete\n";
	return 1;
}

sub _delete_patron {
	my( $session, $patron ) = @_;

	warn "Deleting patron " . $patron->usrname() . "\n";

	my $req = $session->request(
		"open-ils.storage.direct.actor.user.delete",
		$patron );
	my $status = $req->gather(1);
	if(!defined($status)) { 
		throw OpenSRF::EX::ERROR 
			("Unknown error updating patron"); 
	}
}

