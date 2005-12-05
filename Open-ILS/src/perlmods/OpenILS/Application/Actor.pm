package OpenILS::Application::Actor;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use Data::Dumper;
use OpenILS::Event;

use Digest::MD5 qw(md5_hex);

use OpenSRF::EX qw(:try);
use OpenILS::EX;
use OpenILS::Perm;

use OpenILS::Application::AppUtils;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Search::Actor;
use OpenILS::Utils::ModsParser;

use OpenSRF::Utils::Cache;


use OpenILS::Application::Actor::Container;
sub initialize {
	OpenILS::Application::Actor::Container->initialize();
}

my $apputils = "OpenILS::Application::AppUtils";

sub _d { warn "Patron:\n" . Dumper(shift()); }

my $cache_client;


my $set_user_settings;
my $set_ou_settings;

__PACKAGE__->register_method(
	method	=> "set_user_settings",
	api_name	=> "open-ils.actor.patron.settings.update",
);
sub set_user_settings {
	my( $self, $client, $user_session, $uid, $settings ) = @_;
	
	my $user_obj = $apputils->check_user_session( $user_session ); #throws EX on error

	if (ref($uid) eq 'HASH') {
		$settings = $uid;
		$uid = undef;
	}
	$uid ||= $user_obj->id;

	if( $user_obj->id != $uid ) {
		if($apputils->check_user_perms($user_obj->id, $user_obj->home_ou, "UPDATE_USER")) {
			return OpenILS::Perm->new("UPDATE_USER");
		}
	}

#	$set_user_settings ||=
#		$self->method_lookup('open-ils.storage.direct.actor.user_setting.batch.merge');

#	return $set_user_settings->run(map { [{ usr => $uid, name => $_}, {value => $$settings{$_}}] } keys %$settings);

	return $apputils->simple_scalar_request(
		'open-ils.storage',
		'open-ils.storage.direct.actor.user_setting.batch.merge',
		map { [{ usr => $uid, name => $_}, {value => $$settings{$_}}] } keys %$settings );

	
}



__PACKAGE__->register_method(
	method	=> "set_ou_settings",
	api_name	=> "open-ils.actor.org_unit.settings.update",
);
sub set_ou_settings {
	my( $self, $client, $user_session, $ouid, $settings ) = @_;
	
	throw OpenSRF::EX::InvalidArg ("OrgUnit ID and Settings hash required for setting OrgUnit settings") unless ($ouid && $settings);

	my $user_obj = $apputils->check_user_session( $user_session ); #throws EX on error

	if($apputils->check_user_perms($user_obj->id, $ouid, "UPDATE_ORG_UNIT")) {
		return OpenILS::Perm->new("UPDATE_ORG_UNIT");
	}


	$set_ou_settings ||=
		$self->method_lookup('open-ils.storage.direct.actor.org_unit_setting.merge');

	return $set_ou_settings->run(map { [{ org_unit => $ouid, name => $_}, {value => $$settings{$_}}] } keys %$settings);
}




my $fetch_user_settings;
my $fetch_ou_settings;

__PACKAGE__->register_method(
	method	=> "user_settings",
	api_name	=> "open-ils.actor.patron.settings.retrieve",
);
sub user_settings {
	my( $self, $client, $user_session, $uid ) = @_;
	
	my $user_obj = $apputils->check_user_session( $user_session ); #throws EX on error

	$uid ||= $user_obj->id;

	if( $user_obj->id != $uid ) {
		if($apputils->check_user_perms($user_obj->id, $user_obj->home_ou, "VIEW_USER")) {
			return OpenILS::Perm->new("VIEW_USER");
		}
	}

	warn "fetching user settings for $uid...\n";
	my $s = $apputils->simple_scalar_request(
		'open-ils.storage',
		'open-ils.storage.direct.actor.user_setting.search.usr.atomic',$uid );

	return { map { ($_->name,$_->value) } @$s };
}



__PACKAGE__->register_method(
	method	=> "ou_settings",
	api_name	=> "open-ils.actor.org_unit.settings.retrieve",
);
sub ou_settings {
	my( $self, $client, $ouid ) = @_;
	
	throw OpenSRF::EX::InvalidArg ("OrgUnit ID required for lookup of OrgUnit settings") unless ($ouid);

	$fetch_ou_settings ||=
		$self->method_lookup('open-ils.storage.direct.actor.org_unit_setting.search.org_unit.atomic');

	my ($s) = $fetch_ou_settings->run($ouid);

	return { map { ($_->name,$_->value) } @$s };
}



__PACKAGE__->register_method(
	method	=> "update_patron",
	api_name	=> "open-ils.actor.patron.update",);

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

	if(ref($patron->card)) { $patron->card( $patron->card->id ); }
	if(ref($patron->billing_address)) { $patron->billing_address( $patron->billing_address->id ); }
	if(ref($patron->mailing_address)) { $patron->mailing_address( $patron->mailing_address->id ); }

	# create/update the patron first so we can use his id
	if($patron->isnew()) {

		$new_patron = _add_patron($session, _clone_patron($patron), $user_obj);

		if(UNIVERSAL::isa($new_patron, "OpenILS::EX") || 
			UNIVERSAL::isa($new_patron, "OpenILS::Perm")) {
			$client->respond_complete($new_patron->ex);
			return undef;
		}

	} else { $new_patron = $patron; }

	$new_patron = _add_update_addresses($session, $patron, $new_patron, $user_obj);

	if(UNIVERSAL::isa($new_patron, "OpenILS::EX") || 
		UNIVERSAL::isa($new_patron, "OpenILS::Perm")) {
		$client->respond_complete($new_patron->ex);
		return undef;
	}

	$new_patron = _add_update_cards($session, $patron, $new_patron, $user_obj);

	if(UNIVERSAL::isa($new_patron, "OpenILS::EX") || 
		UNIVERSAL::isa($new_patron, "OpenILS::Perm")) {
		$client->respond_complete($new_patron->ex);
		return undef;
	}

	$new_patron = _add_survey_responses($session, $patron, $new_patron, $user_obj);
	if(UNIVERSAL::isa($new_patron, "OpenILS::EX") || 
		UNIVERSAL::isa($new_patron, "OpenILS::Perm")) {
		$client->respond_complete($new_patron->ex);
		return undef;
	}


	# re-update the patron if anything has happened to him during this process
	if($new_patron->ischanged()) {
		$new_patron = _update_patron($session, $new_patron, $user_obj);

		if(UNIVERSAL::isa($new_patron, "OpenILS::EX") || 
			UNIVERSAL::isa($new_patron, "OpenILS::Perm")) {
			$client->respond_complete($new_patron->ex);
			return undef;
		}
	}

	$apputils->commit_db_session($session);

	$session = OpenSRF::AppSession->create("open-ils.storage");
	$new_patron	= _create_stat_maps($session, $user_session, $patron, $new_patron, $user_obj);
	if(UNIVERSAL::isa($new_patron, "OpenILS::EX") || 
		UNIVERSAL::isa($new_patron, "OpenILS::Perm")) {
		$client->respond_complete($new_patron->ex);
		return undef;
	}


	warn "Patron Update/Create complete\n";
	return flesh_user($new_patron->id());
}




__PACKAGE__->register_method(
	method	=> "user_retrieve_fleshed_by_id",
	api_name	=> "open-ils.actor.user.fleshed.retrieve",);

sub user_retrieve_fleshed_by_id {
	my( $self, $client, $user_session, $user_id ) = @_;
	my $user_obj = $apputils->check_user_session( $user_session ); 

	if(!defined($user_id)) { $user_id = $user_obj->id; }

	if( $user_obj->id ne $user_id ) {
		if($apputils->check_user_perms($user_obj->id, $user_obj->home_ou, "VIEW_USER")) {
			return OpenILS::Perm->new("VIEW_USER");
		}
	}

	return flesh_user($user_id);
}


sub flesh_user {
	my $id = shift;
	my $session = shift;

	my $kill = 0;

	if(!$session) {
		$session = OpenSRF::AppSession->create("open-ils.storage");
		$kill = 1;
	}

	# grab the user with the given id 
	my $ureq = $session->request(
			"open-ils.storage.direct.actor.user.retrieve", $id);
	my $user = $ureq->gather(1);

	if(!$user) { return undef; }

	# grab the cards
	my $cards_req = $session->request(
			"open-ils.storage.direct.actor.card.search.usr.atomic",
			$user->id() );
	$user->cards( $cards_req->gather(1) );

	for my $c(@{$user->cards}) {
		if($c->id == $user->card || $c->id eq $user->card ) {
			warn "Setting my card to " . $c->id . "\n";
			$user->card($c);
		}
	}

	my $add_req = $session->request(
			"open-ils.storage.direct.actor.user_address.search.usr.atomic",
			$user->id() );
	$user->addresses( $add_req->gather(1) );

	for my $c(@{$user->addresses}) {
		if($c->id == $user->billing_address || $c->id eq $user->billing_address ) {
			warn "Setting my address to " . $c->id . "\n";
			$user->billing_address($c);
		}
	}

	for my $c(@{$user->addresses}) {
		if($c->id == $user->mailing_address || $c->id eq $user->mailing_address ) {
			warn "Setting my address to " . $c->id . "\n";
			$user->mailing_address($c);
		}
	}

	my $stat_req = $session->request(
		"open-ils.storage.direct.actor.stat_cat_entry_user_map.search.target_usr.atomic",
		$user->id() );
	$user->stat_cat_entries($stat_req->gather(1));

	if($kill) { $session->disconnect(); }
	$user->clear_passwd();
	warn Dumper $user;

	return $user;

}


# clone and clear stuff that would break the database
sub _clone_patron {
	my $patron = shift;

	my $new_patron = $patron->clone;

	# Using the Fieldmapper clone method
	#my $new_patron = Fieldmapper::actor::user->new();

	#my $fmap = $Fieldmapper::fieldmap;
	#no strict; # shallow clone, may be useful in the fieldmapper
	#for my $field 
	#	(keys %{$fmap->{"Fieldmapper::actor::user"}->{'fields'}}) {
	#		$new_patron->$field( $patron->$field() );
	#}
	#use strict;

	# clear these
	$new_patron->clear_billing_address();
	$new_patron->clear_mailing_address();
	$new_patron->clear_addresses();
	$new_patron->clear_card();
	$new_patron->clear_cards();
	$new_patron->clear_id();
	$new_patron->clear_isnew();
	$new_patron->clear_ischanged();
	$new_patron->clear_isdeleted();
	$new_patron->clear_stat_cat_entries();

	return $new_patron;
}


sub _add_patron {
	my $session		= shift;
	my $patron		= shift;
	my $user_obj	= shift;


	if($apputils->check_user_perms(
				$user_obj->id, $user_obj->home_ou, "CREATE_USER")) {
		return OpenILS::Perm->new("CREATE_USER");
	}

	warn "Creating new patron\n";
	_d($patron);

	my $req = $session->request(
		"open-ils.storage.direct.actor.user.create",$patron);
	my $id = $req->gather(1);
	if(!$id) { 
		return OpenILS::EX->new("DUPLICATE_USER_USERNAME");
	}

	# retrieve the patron from the db to collect defaults
	my $ureq = $session->request(
			"open-ils.storage.direct.actor.user.retrieve",
			$id);

	warn "Created new patron with id $id\n";

	return $ureq->gather(1);
}


sub _update_patron {
	my( $session, $patron, $user_obj) = @_;


	if($patron->id ne $user_obj->id) {
		if($apputils->check_user_perms(
					$user_obj->id, $user_obj->home_ou, "UPDATE_USER")) {
			return OpenILS::Perm->new("UPDATE_USER");
		}
	}

	warn "updating patron " . Dumper($patron) . "\n";

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

			if( $patron->billing_address() and 
					$patron->billing_address() == $current_id ) {
				$new_patron->billing_address($address->id());
				$new_patron->ischanged(1);
			}

			if( $patron->mailing_address() and
					$patron->mailing_address() == $current_id ) {
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

	use Data::Dumper;
	warn "Adding Address:\n";
	warn Dumper($address);

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
			if(UNIVERSAL::isa($card,"OpenILS::EX")) {
				return $card;
			}

			#if(ref($patron->card)) { $patron->card($patron->card->id); }
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
		return OpenILS::EX->new("DUPLICATE_INVALID_USER_BARCODE");
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



sub _add_survey_responses {
	my ($session, $patron, $new_patron) = @_;

	warn "updating responses for user " . $new_patron->id . "\n";

	my $responses = $patron->survey_responses;

	if($responses) {

		for my $resp( @$responses ) {
			$resp->usr($new_patron->id);
		}

		my $status = $apputils->simple_scalar_request(
			"open-ils.circ", 
			"open-ils.circ.survey.submit.user_id",
			$responses );

	}

	return $new_patron;
}


sub _create_stat_maps {

	my($session, $user_session, $patron, $new_patron) = @_;

	my $maps = $patron->stat_cat_entries();

	for my $map (@$maps) {

		next unless($map->isnew() || $map->ischanged());

		my $method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.update";
		if($map->isnew()) {
			$method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.create";
			$map->clear_id;
		}

		$map->target_usr($new_patron->id);

		warn "Updating stat entry with method $method and session $user_session and map $map\n";

		my $req = $session->request($method, $map);
		my $status = $req->gather(1);

		warn "Updated\n";

		if(!$status) {
			throw OpenSRF::EX::ERROR 
				("Error updating stat map with method $method");	
		}

	}

	return $new_patron;
}



__PACKAGE__->register_method(
	method	=> "search_username",
	api_name	=> "open-ils.actor.user.search.username",
);

sub search_username {
	my($self, $client, $username) = @_;
	my $users = OpenILS::Application::AppUtils->simple_scalar_request(
			"open-ils.storage", 
			"open-ils.storage.direct.actor.user.search.usrname.atomic",
			$username );
	return $users;
}




__PACKAGE__->register_method(
	method	=> "user_retrieve_by_barcode",
	api_name	=> "open-ils.actor.user.fleshed.retrieve_by_barcode",);

sub user_retrieve_by_barcode {
	my($self, $client, $user_session, $barcode) = @_;
	warn "Searching for user with barcode $barcode\n";
	my $user_obj = $apputils->check_user_session( $user_session ); 

	my $session = OpenSRF::AppSession->create("open-ils.storage");

	# find the card with the given barcode
	my $creq	= $session->request(
			"open-ils.storage.direct.actor.card.search.barcode.atomic",
			$barcode );
	my $card = $creq->gather(1);

	if(!$card || !$card->[0]) {
		$session->disconnect();
		return undef;
	}

	$card = $card->[0];
	my $user = flesh_user($card->usr(), $session);
	$session->disconnect();
	return $user;

}



__PACKAGE__->register_method(
	method	=> "get_user_by_id",
	api_name	=> "open-ils.actor.user.retrieve",);

sub get_user_by_id {
	my ($self, $client, $user_session, $id) = @_;

	my $user_obj = $apputils->check_user_session( $user_session ); 

	return $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.actor.user.retrieve",
		$id );
}



__PACKAGE__->register_method(
	method	=> "get_org_types",
	api_name	=> "open-ils.actor.org_types.retrieve",);

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

	my( $self, $client, $user_session, $org_id ) = @_;

	if(defined($user_session) && !defined($org_id)) {
		my $user_obj = 
			OpenILS::Application::AppUtils->check_user_session( $user_session ); #throws EX on error
		if(!defined($org_id)) {
			$org_id = $user_obj->home_ou;
		}
	}


	my $home_ou = OpenILS::Application::AppUtils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.actor.org_unit.retrieve", 
		$org_id );

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

	if(!$cache_client) {
		$cache_client = OpenSRF::Utils::Cache->new("global", 0);
	}
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

	if($orglist) {
		warn "found org list\n";
	}

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

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $req = $session->request(
		"open-ils.storage.actor.user.crazy_search", $search_hash);

	my $ans = $req->gather(1);

	my %hash = map { ($_ =>1) } @$ans;
	$ans = [ keys %hash ];

	warn "Returning @$ans\n";

	$session->disconnect();
	return $ans;

}



sub _verify_password {
	my($user_session, $password) = @_;
	my $user_obj = $apputils->check_user_session($user_session); 

	#grab the user with password
	$user_obj = $apputils->simple_scalar_request(
		"open-ils.storage", 
		"open-ils.storage.direct.actor.user.retrieve",
		$user_obj->id );

	if($user_obj->passwd eq $password) {
		return 1;
	}

	return 0;
}


__PACKAGE__->register_method(
	method	=> "update_password",
	api_name	=> "open-ils.actor.user.password.update");

__PACKAGE__->register_method(
	method	=> "update_password",
	api_name	=> "open-ils.actor.user.username.update");

__PACKAGE__->register_method(
	method	=> "update_password",
	api_name	=> "open-ils.actor.user.email.update");

sub update_password {
	my( $self, $client, $user_session, $new_value, $current_password ) = @_;

	warn "Updating user with method " .$self->api_name . "\n";
	my $user_obj = $apputils->check_user_session($user_session); 

	if($self->api_name =~ /password/) {

		#make sure they know the current password
		if(!_verify_password($user_session, md5_hex($current_password))) {
			return OpenILS::EX->new("USER_WRONG_PASSWORD")->ex;
		}

		$user_obj->passwd($new_value);
	} 
	elsif($self->api_name =~ /username/) {
		$user_obj->usrname($new_value);
	}

	elsif($self->api_name =~ /email/) {
		warn "Updating email to $new_value\n";
		$user_obj->email($new_value);
	}

	my $session = $apputils->start_db_session();
	$user_obj = _update_patron($session, $user_obj, $user_obj);
	$apputils->commit_db_session($session);

	if($user_obj) { return 1; }
	return undef;
}


__PACKAGE__->register_method(
	method	=> "check_user_perms",
	api_name	=> "open-ils.actor.user.perm.check",
	notes		=> <<"	NOTES");
	Takes a login session, user id, an org id, and an array of perm type strings.  For each
	perm type, if the user does *not* have the given permission it is added
	to a list which is returned from the method.  If all permissions
	are allowed, an empty list is returned
	if the logged in user does not match 'user_id', then the logged in user must
	have VIEW_PERMISSION priveleges.
	NOTES

sub check_user_perms {
	my( $self, $client, $login_session, $user_id, $org_id, $perm_types ) = @_;
	my $user_obj = $apputils->check_user_session($login_session); 

	if($user_obj->id ne $user_id) {
		if($apputils->check_user_perms($user_obj->id, $org_id, "VIEW_PERMISSION")) {
			return OpenILS::Perm->new("VIEW_PERMISSION");
		}
	}

	my @not_allowed;
	for my $perm (@$perm_types) {
		if($apputils->check_user_perms($user_id, $org_id, $perm)) {
			push @not_allowed, $perm;
		}
	}

	return \@not_allowed
}



__PACKAGE__->register_method(
	method	=> "user_fines_summary",
	api_name	=> "open-ils.actor.user.fines.summary",
	notes		=> <<"	NOTES");
	Returns a short summary of the users total open fines, excluding voided fines
	Params are login_session, user_id
	Returns a 'mous' object.
	NOTES

sub user_fines_summary {
	my( $self, $client, $login_session, $user_id ) = @_;

	my $user_obj = $apputils->check_user_session($login_session); 
	if($user_obj->id ne $user_id) {
		if($apputils->check_user_perms($user_obj->id, $user_obj->home_ou, "VIEW_USER_FINES_SUMMARY")) {
			return OpenILS::Perm->new("VIEW_USER_FINES_SUMMARY"); 
		}
	}

	return $apputils->simple_scalar_request( 
		"open-ils.storage",
		"open-ils.storage.direct.money.open_user_summary.search.usr",
		$user_id );

}




__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions",
	notes		=> <<"	NOTES");
	Returns a list of open user transactions (mbts objects);
	Params are login_session, user_id
	Optional third parameter is the transactions type.  defaults to all
	NOTES

__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions.have_charge",
	notes		=> <<"	NOTES");
	Returns a list of all open user transactions (mbts objects) that have an initial charge
	Params are login_session, user_id
	Optional third parameter is the transactions type.  defaults to all
	NOTES

__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions.have_balance",
	notes		=> <<"	NOTES");
	Returns a list of all open user transactions (mbts objects) that have a balance
	Params are login_session, user_id
	Optional third parameter is the transactions type.  defaults to all
	NOTES

__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions.fleshed",
	notes		=> <<"	NOTES");
	Returns an object/hash of transaction, circ, title where transaction = an open 
	user transactions (mbts objects), circ is the attached circluation, and title
	is the title the circ points to
	Params are login_session, user_id
	Optional third parameter is the transactions type.  defaults to all
	NOTES

__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions.have_charge.fleshed",
	notes		=> <<"	NOTES");
	Returns an object/hash of transaction, circ, title where transaction = an open 
	user transactions that has an initial charge (mbts objects), circ is the 
	attached circluation, and title is the title the circ points to
	Params are login_session, user_id
	Optional third parameter is the transactions type.  defaults to all
	NOTES

__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions.have_balance.fleshed",
	notes		=> <<"	NOTES");
	Returns an object/hash of transaction, circ, title where transaction = an open 
	user transaction that has a balance (mbts objects), circ is the attached 
	circluation, and title is the title the circ points to
	Params are login_session, user_id
	Optional third parameter is the transaction type.  defaults to all
	NOTES



sub user_transactions {
	my( $self, $client, $login_session, $user_id, $type ) = @_;

	my $user_obj = $apputils->check_user_session($login_session); 
	if($user_obj->id ne $user_id) {
		if($apputils->check_user_perms($user_obj->id, $user_obj->home_ou, "VIEW_USER_TRANSACTIONS")) {
			return OpenILS::Perm->new("VIEW_USER_TRANSACTIONS"); 
		}
	}

	my $api = $self->api_name();
	my $trans;
	my @xact;
	if(defined($type)) { @xact = (xact_type =>  $type); 
	} else { @xact = (); }

	if($api =~ /have_charge/) {

		$trans = $apputils->simple_scalar_request( 
			"open-ils.storage",
			"open-ils.storage.direct.money.open_billable_transaction_summary.search_where.atomic",
			{ usr => $user_id, total_owed => { ">" => 0 }, @xact });

	} elsif($api =~ /have_balance/) {

		$trans =  $apputils->simple_scalar_request( 
			"open-ils.storage",
			"open-ils.storage.direct.money.open_billable_transaction_summary.search_where.atomic",
			{ usr => $user_id, balance_owed => { ">" => 0 }, @xact });

	} else {

		$trans =  $apputils->simple_scalar_request( 
			"open-ils.storage",
			"open-ils.storage.direct.money.open_billable_transaction_summary.search_where.atomic",
			{ usr => $user_id, @xact });
	}

	if($api !~ /fleshed/) { return $trans; }

	warn "API: $api\n";

	my @resp;
	for my $t (@$trans) {
			
		warn $t->id . "\n";

		my $circ = $apputils->simple_scalar_request(
				"open-ils.storage",
				"open-ils.storage.direct.action.circulation.retrieve",
				$t->id );

		next unless $circ;

		my $title = $apputils->simple_scalar_request(
			"open-ils.storage", 
			"open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy",
			$circ->target_copy );

		next unless $title;

		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch($title->marc());
		my $mods = $u->finish_mods_batch();

		push @resp, {transaction => $t, circ => $circ, record => $mods };

	}

	return \@resp; 
} 




__PACKAGE__->register_method(
	method	=> "retrieve_groups",
	api_name	=> "open-ils.actor.groups.retrieve",
	notes		=> <<"	NOTES");
	Returns a list of user groups
	NOTES
sub retrieve_groups {
	my( $self, $client ) = @_;
	return $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.permission.grp_tree.retrieve.all.atomic");
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


