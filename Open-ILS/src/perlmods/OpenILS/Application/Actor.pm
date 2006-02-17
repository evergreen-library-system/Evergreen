package OpenILS::Application::Actor;
use base qw/OpenSRF::Application/;
use strict; use warnings;
use Data::Dumper;
$Data::Dumper::Indent = 0;
use OpenILS::Event;

use Digest::MD5 qw(md5_hex);

use OpenSRF::EX qw(:try);
use OpenILS::EX;
use OpenILS::Perm;

use OpenILS::Application::AppUtils;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Application::Search::Actor;
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils qw/:datetime/;

use OpenSRF::Utils::Cache;

use DateTime;
use DateTime::Format::ISO8601;

use OpenILS::Application::Actor::Container;

sub initialize {
	OpenILS::Application::Actor::Container->initialize();
}

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;

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
	
	$logger->debug("Setting user settings: $user_session, $uid, " . Dumper($settings));

	my( $staff, $user, $evt ) = 
		$apputils->checkses_requestor( $user_session, $uid, 'UPDATE_USER' );	
	return $evt if $evt;
	

	my ($params) = map { 
		[{ usr => $user->id, name => $_}, {value => $$settings{$_}}] } keys %$settings;

	$logger->activity("User " . $staff->id . " updating user $uid settings with: " . Dumper($params));

	return $apputils->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.actor.user_setting.batch.merge', $params );
		
}



__PACKAGE__->register_method(
	method	=> "set_ou_settings",
	api_name	=> "open-ils.actor.org_unit.settings.update",
);
sub set_ou_settings {
	my( $self, $client, $user_session, $ouid, $settings ) = @_;
	
	my( $staff, $evt ) = $apputils->checkses( $user_session );
	return $evt if $evt;
	$evt = $apputils->check_perms( $staff->id, $ouid, 'UPDATE_ORG_UNIT' );
	return $evt if $evt;


	my ($params) = 
		map { [{ org_unit => $ouid, name => $_}, {value => $$settings{$_}}] } keys %$settings;

	$logger->activity("Updating org unit [$ouid] settings with: " . Dumper($params));

	return $apputils->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.actor.org_unit_setting.merge', @$params );
}


my $fetch_user_settings;
my $fetch_ou_settings;

__PACKAGE__->register_method(
	method	=> "user_settings",
	api_name	=> "open-ils.actor.patron.settings.retrieve",
);
sub user_settings {
	my( $self, $client, $user_session, $uid ) = @_;
	
	my( $staff, $user, $evt ) = 
		$apputils->checkses_requestor( $user_session, $uid, 'VIEW_USER' );
	return $evt if $evt;

	$logger->debug("User " . $staff->id . " fetching user $uid\n");
	my $s = $apputils->simplereq(
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
	
	my $s = $apputils->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.actor.org_unit_setting.search.org_unit.atomic', $ouid);

	return { map { ($_->name,$_->value) } @$s };
}



__PACKAGE__->register_method(
	method	=> "update_patron",
	api_name	=> "open-ils.actor.patron.update",);

sub update_patron {
	my( $self, $client, $user_session, $patron ) = @_;

	my $session = $apputils->start_db_session();
	my $err = undef;

	$logger->info("Creating new patron...") if $patron->isnew; 
	$logger->info("Updating Patron: " . $patron->id) unless $patron->isnew;

	my( $user_obj, $evt ) = $U->checkses($user_session);
	return $evt if $evt;

	# XXX does this user have permission to add/create users.  Granularity?
	# $new_patron is the patron in progress.  $patron is the original patron
	# passed in with the method.  new_patron will change as the components
	# of patron are added/updated.

	my $new_patron;

	# unflesh the real items on the patron
	$patron->card( $patron->card->id ) if(ref($patron->card));
	$patron->billing_address( $patron->billing_address->id ) 
		if(ref($patron->billing_address));
	$patron->mailing_address( $patron->mailing_address->id ) 
		if(ref($patron->mailing_address));

	# create/update the patron first so we can use his id
	if($patron->isnew()) {
		( $new_patron, $evt ) = _add_patron($session, _clone_patron($patron), $user_obj);
		return $evt if $evt;
	} else { $new_patron = $patron; }

	( $new_patron, $evt ) = _add_update_addresses($session, $patron, $new_patron, $user_obj);
	return $evt if $evt;

	( $new_patron, $evt ) = _add_update_cards($session, $patron, $new_patron, $user_obj);
	return $evt if $evt;

	( $new_patron, $evt ) = _add_survey_responses($session, $patron, $new_patron, $user_obj);
	return $evt if $evt;

	# re-update the patron if anything has happened to him during this process
	if($new_patron->ischanged()) {
		( $new_patron, $evt ) = _update_patron($session, $new_patron, $user_obj);
		return $evt if $evt;
	}

	#$session = OpenSRF::AppSession->create("open-ils.storage");  # why did i put this here?

	($new_patron, $evt) = _create_stat_maps($session, $user_session, $patron, $new_patron, $user_obj);
	return $evt if $evt;

	($new_patron, $evt) = _create_perm_maps($session, $user_session, $patron, $new_patron, $user_obj);
	return $evt if $evt;

	($new_patron, $evt) = _create_standing_penalties($session, $user_session, $patron, $new_patron, $user_obj);
	return $evt if $evt;

	$apputils->commit_db_session($session);

	#warn "Patron Update/Create complete\n";
	return flesh_user($new_patron->id());
}




__PACKAGE__->register_method(
	method	=> "user_retrieve_fleshed_by_id",
	api_name	=> "open-ils.actor.user.fleshed.retrieve",);

sub user_retrieve_fleshed_by_id {
	my( $self, $client, $user_session, $user_id ) = @_;

	my( $requestor, $target, $evt ) = $apputils->
		checkses_requestor( $user_session, $user_id, 'VIEW_USER' );
	return $evt if $evt;

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
			#warn "Setting my card to " . $c->id . "\n";
			$user->card($c);
		}
	}

	my $add_req = $session->request(
			"open-ils.storage.direct.actor.user_address.search.usr.atomic",
			$user->id() );
	$user->addresses( $add_req->gather(1) );

	for my $c(@{$user->addresses}) {
		if($c->id eq $user->billing_address ) { $user->billing_address($c); }
		if($c->id eq $user->mailing_address ) { $user->mailing_address($c); }
	}

	my $stat_req = $session->request(
		"open-ils.storage.direct.actor.stat_cat_entry_user_map.search.target_usr.atomic",
		$user->id() );
	$user->stat_cat_entries($stat_req->gather(1));

	my $standing_penalties_req = $session->request(
		"open-ils.storage.direct.actor.user_standing_penalty.search.usr.atomic",
		$user->id() );
	$user->standing_penalties($standing_penalties_req->gather(1));

	if($kill) { $session->disconnect(); }
	$user->clear_passwd();

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
	$new_patron->clear_permissions();
	$new_patron->clear_standing_penalties();

	return $new_patron;
}


sub _add_patron {

	my $session		= shift;
	my $patron		= shift;
	my $user_obj	= shift;

	my $evt = $U->check_perms($user_obj->id, $patron->home_ou, 'CREATE_USER');
	return (undef, $evt) if $evt;

	$logger->info("Creating new user in the DB with username: ".$patron->usrname());

	my $id = $session->request(
		"open-ils.storage.direct.actor.user.create", $patron)->gather(1);
	return (undef, $U->DB_UPDATE_FAILED($patron)) unless $id;

	$logger->info("Successfully created new user [$id] in DB");

	return ( $session->request( 
		"open-ils.storage.direct.actor.user.retrieve", $id)->gather(1), undef );
}


sub _update_patron {
	my( $session, $patron, $user_obj) = @_;

	$logger->info("Updating patron ".$patron->id." in DB");
	my $evt = $U->check_perms($user_obj->id, $patron->home_ou, 'UPDATE_USER');
	return (undef, $evt) if $evt;

	my $stat = $session->request(
		"open-ils.storage.direct.actor.user.update",$patron )->gather(1);
	return (undef, $U->DB_UPDATE_FAILED($patron)) unless defined($stat);

	return ($patron);
}


sub _add_update_addresses {

	my $session = shift;
	my $patron = shift;
	my $new_patron = shift;

	my $evt;

	my $current_id; # id of the address before creation

	for my $address (@{$patron->addresses()}) {

		$address->usr($new_patron->id());

		if(ref($address) and $address->isnew()) {

			$current_id = $address->id();
			($address, $evt) = _add_address($session,$address);
			return (undef, $evt) if $evt;

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

			$address->usr($new_patron->id());
			($address, $evt) = _update_address($session, $address);
			return (undef, $evt) if $evt;

		} elsif( ref($address) and $address->isdeleted() ) {

			if( $address->id() == $new_patron->mailing_address() ) {
				$new_patron->clear_mailing_address();
				($new_patron, $evt) = _update_patron($session, $new_patron);
				return (undef, $evt) if $evt;
			}

			if( $address->id() == $new_patron->billing_address() ) {
				$new_patron->clear_billing_address();
				($new_patron, $evt) = _update_patron($session, $new_patron);
				return (undef, $evt) if $evt;
			}

			$evt = _delete_address($session, $address);
			return (undef, $evt) if $evt;
		}
	}

	return ( $new_patron, undef );
}


# adds an address to the db and returns the address with new id
sub _add_address {
	my($session, $address) = @_;
	$address->clear_id();

	$logger->info("Creating new address at street ".$address->street1);

	# put the address into the database
	my $id = $session->request(
		"open-ils.storage.direct.actor.user_address.create", $address )->gather(1);
	return (undef, $U->DB_UPDATE_FAILED($address)) unless $id;

	$address->id( $id );
	return ($address, undef);
}


sub _update_address {
	my( $session, $address ) = @_;
	$logger->info("Updating address ".$address->id." in the DB");

	my $stat = $session->request(
		"open-ils.storage.direct.actor.user_address.update", $address )->gather(1);

	return (undef, $U->DB_UPDATE_FAILED($address)) unless defined($stat);
	return ($address, undef);
}



sub _add_update_cards {

	my $session = shift;
	my $patron = shift;
	my $new_patron = shift;

	my $evt;

	my $virtual_id; #id of the card before creation
	for my $card (@{$patron->cards()}) {

		$card->usr($new_patron->id());

		if(ref($card) and $card->isnew()) {

			$virtual_id = $card->id();
			( $card, $evt ) = _add_card($session,$card);
			return (undef, $evt) if $evt;

			#if(ref($patron->card)) { $patron->card($patron->card->id); }
			if($patron->card() == $virtual_id) {
				$new_patron->card($card->id());
				$new_patron->ischanged(1);
			}

		} elsif( ref($card) and $card->ischanged() ) {
			$card->usr($new_patron->id());
			$evt = _update_card($session, $card);
			return (undef, $evt) if $evt;
		}
	}

	return ( $new_patron, undef );
}


# adds an card to the db and returns the card with new id
sub _add_card {
	my( $session, $card ) = @_;
	$card->clear_id();
	$logger->info("Adding new patron card ".$card->barcode);

	my $id = $session->request(
		"open-ils.storage.direct.actor.card.create", $card )->gather(1);
	return (undef, $U->DB_UPDATE_FAILED($card)) unless $id;
	$logger->info("Successfully created patron card $id");

	$card->id($id);
	return ( $card, undef );
}


# returns event on error.  returns undef otherwise
sub _update_card {
	my( $session, $card ) = @_;
	$logger->info("Updating patron card ".$card->id);

	my $stat = $session->request(
		"open-ils.storage.direct.actor.card.update", $card )->gather(1);
	return $U->DB_UPDATE_FAILED($card) unless defined($stat);
	return undef;
}




# returns event on error.  returns undef otherwise
sub _delete_address {
	my( $session, $address ) = @_;
	$logger->info("Deleting address ".$address->id." from DB");

	my $stat = $session->request(
		"open-ils.storage.direct.actor.user_address.delete", $address )->gather(1);

	return $U->DB_UPDATE_FAILED($address) unless defined($stat);
	return undef;
}



sub _add_survey_responses {
	my ($session, $patron, $new_patron) = @_;

	$logger->info( "Updating survey responses for patron ".$new_patron->id );

	my $responses = $patron->survey_responses;

	if($responses) {

		$_->usr($new_patron->id) for (@$responses);

		my $evt = $U->simplereq( "open-ils.circ", 
			"open-ils.circ.survey.submit.user_id", $responses );

		return (undef, $evt) if defined($U->event_code($evt));

	}

	return ( $new_patron, undef );
}


sub _create_stat_maps {

	my($session, $user_session, $patron, $new_patron) = @_;

	my $maps = $patron->stat_cat_entries();

	for my $map (@$maps) {

		my $method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.update";

		if ($map->isdeleted()) {
			$method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.delete";

		} elsif ($map->isnew()) {
			$method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.create";
			$map->clear_id;
		}


		$map->target_usr($new_patron->id);

		#warn "
		$logger->info("Updating stat entry with method $method and map $map");

		my $stat = $session->request($method, $map)->gather(1);
		return (undef, $U->DB_UPDATE_FAILED($map)) unless defined($stat);

	}

	return ($new_patron, undef);
}

sub _create_perm_maps {

	my($session, $user_session, $patron, $new_patron) = @_;

	my $maps = $patron->permissions;

	for my $map (@$maps) {

		my $method = "open-ils.storage.direct.permission.usr_perm_map.update";
		if ($map->isdeleted()) {
			$method = "open-ils.storage.direct.permission.usr_perm_map.delete";
		} elsif ($map->isnew()) {
			$method = "open-ils.storage.direct.permission.usr_perm_map.create";
			$map->clear_id;
		}


		$map->usr($new_patron->id);

		#warn( "Updating permissions with method $method and session $user_session and map $map" );
		$logger->info( "Updating permissions with method $method and map $map" );

		my $stat = $session->request($method, $map)->gather(1);
		return (undef, $U->DB_UPDATE_FAILED($map)) unless defined($stat);

	}

	return ($new_patron, undef);
}


sub _create_standing_penalties {

	my($session, $user_session, $patron, $new_patron) = @_;

	my $maps = $patron->standing_penalties;
	my $method;

	for my $map (@$maps) {

		if ($map->isdeleted()) {
			$method = "open-ils.storage.direct.actor.user_standing_penalty.delete";
		} elsif ($map->isnew()) {
			$method = "open-ils.storage.direct.actor.user_standing_penalty.create";
			$map->clear_id;
		} else {
			next;
		}

		$map->usr($new_patron->id);

		$logger->debug( "Updating standing penalty with method $method and session $user_session and map $map" );

		my $stat = $session->request($method, $map)->gather(1);
		return (undef, $U->DB_UPDATE_FAILED($map)) unless $stat;
	}

	return ($new_patron, undef);
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

	$logger->debug("Searching for user with barcode $barcode");
	my ($user_obj, $evt) = $apputils->checkses($user_session);
	return $evt if $evt;

	my $session = OpenSRF::AppSession->create("open-ils.storage");

	# find the card with the given barcode
	my $creq	= $session->request(
			"open-ils.storage.direct.actor.card.search.barcode.atomic",
			$barcode );
	my $card = $creq->gather(1);

	if(!$card || !$card->[0]) {
		$session->disconnect();
		return OpenILS::Event->new( 'USER_NOT_FOUND' );
	}

	$card = $card->[0];
	my $user = flesh_user($card->usr(), $session);
	$session->disconnect();
	if(!$user) { return OpenILS::Event->new( 'USER_NOT_FOUND' ); }
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
	argc		=> 0, 
	note		=> "Returns the entire org tree structure",
);

sub get_org_tree {
	my( $self, $client) = @_;

	if(!$cache_client) {
		$cache_client = OpenSRF::Utils::Cache->new("global", 0);
	}
	# see if it's in the cache
	#warn "Getting ORG Tree\n";
	my $tree = $cache_client->get_cache('orgtree');
	if($tree) { 
		#warn "Found orgtree in cache. returning...\n";
		return $tree; 
	}

	my $orglist = $apputils->simple_scalar_request( 
		"open-ils.storage", 
		"open-ils.storage.direct.actor.org_unit.retrieve.all.atomic" );

	#if($orglist) {
		#warn "found org list\n";
	#}

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

	#warn "patron adv with $staff_login and search " . 
		#Dumper($search_hash) . "\n";

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $req = $session->request(
		"open-ils.storage.actor.user.crazy_search", $search_hash);

	my $ans = $req->gather(1);

	my %hash = map { ($_ =>1) } @$ans;
	$ans = [ keys %hash ];

	#warn "Returning @$ans\n";

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

	my $evt;

	#warn "Updating user with method " .$self->api_name . "\n";
	my $user_obj = $apputils->check_user_session($user_session); 

	if($self->api_name =~ /password/o) {

		#make sure they know the current password
		if(!_verify_password($user_session, md5_hex($current_password))) {
			return OpenILS::EX->new("USER_WRONG_PASSWORD")->ex;
		}

		$user_obj->passwd($new_value);
	} 
	elsif($self->api_name =~ /username/o) {
		my $users = search_username(undef, undef, $new_value); 
		if( $users and $users->[0] ) {
			return OpenILS::Event->new('USERNAME_EXISTS');
		}
		$user_obj->usrname($new_value);
	}

	elsif($self->api_name =~ /email/o) {
		#warn "Updating email to $new_value\n";
		$user_obj->email($new_value);
	}

	my $session = $apputils->start_db_session();

	( $user_obj, $evt ) = _update_patron($session, $user_obj, $user_obj);
	return $evt if $evt;

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

	my( $staff, $evt ) = $apputils->checkses($login_session);
	return $evt if $evt;

	if($staff->id ne $user_id) {
		if( my $evt = $apputils->check_perms(
			$staff->id, $org_id, 'VIEW_PERMISSION') ) {
			return $evt;
		}
	}

	my @not_allowed;
	for my $perm (@$perm_types) {
		if($apputils->check_perms($user_id, $org_id, $perm)) {
			push @not_allowed, $perm;
		}
	}

	return \@not_allowed
}

__PACKAGE__->register_method(
	method	=> "check_user_perms2",
	api_name	=> "open-ils.actor.user.perm.check.multi_org",
	notes		=> q/
		Checks the permissions on a list of perms and orgs for a user
		@param authtoken The login session key
		@param user_id The id of the user to check
		@param orgs The array of org ids
		@param perms The array of permission names
		@return An array of  [ orgId, permissionName ] arrays that FAILED the check
		if the logged in user does not match 'user_id', then the logged in user must
		have VIEW_PERMISSION priveleges.
	/);

sub check_user_perms2 {
	my( $self, $client, $authtoken, $user_id, $orgs, $perms ) = @_;

	my( $staff, $target, $evt ) = $apputils->checkses_requestor(
		$authtoken, $user_id, 'VIEW_PERMISSION' );
	return $evt if $evt;

	my @not_allowed;
	for my $org (@$orgs) {
		for my $perm (@$perms) {
			if($apputils->check_perms($user_id, $org, $perm)) {
				push @not_allowed, [ $org, $perm ];
			}
		}
	}

	return \@not_allowed
}


__PACKAGE__->register_method(
	method => 'check_user_perms3',
	api_name	=> 'open-ils.actor.user.perm.highest_org',
	notes		=> q/
		Returns the highest org unit id at which a user has a given permission
		If the requestor does not match the target user, the requestor must have
		'VIEW_PERMISSION' rights at the home org unit of the target user
		@param authtoken The login session key
		@param userid The id of the user in question
		@param perm The permission to check
		@return The org unit highest in the org tree within which the user has
		the requested permission
	/);

sub check_user_perms3 {
	my( $self, $client, $authtoken, $userid, $perm ) = @_;

	my( $staff, $target, $org, $evt );

	( $staff, $target, $evt ) = $apputils->checkses_requestor(
		$authtoken, $userid, 'VIEW_PERMISSION' );
	return $evt if $evt;

	my $tree = $self->get_org_tree();
	return _find_highest_perm_org( $perm, $userid, $target->home_ou, $tree );
}


sub _find_highest_perm_org {
	my ( $perm, $userid, $start_org, $org_tree ) = @_;
	my $org = $apputils->find_org($org_tree, $start_org );

	my $lastid = undef;
	while( $org ) {
		last if ($apputils->check_perms( $userid, $org->id, $perm )); # perm failed
		$lastid = $org->id;
		$org = $apputils->find_org( $org_tree, $org->parent_ou() );
	}

	return $lastid;
}

__PACKAGE__->register_method(
	method => 'check_user_perms4',
	api_name	=> 'open-ils.actor.user.perm.highest_org.batch',
	notes		=> q/
		Returns the highest org unit id at which a user has a given permission
		If the requestor does not match the target user, the requestor must have
		'VIEW_PERMISSION' rights at the home org unit of the target user
		@param authtoken The login session key
		@param userid The id of the user in question
		@param perms An array of perm names to check 
		@return An array of orgId's  representing the org unit 
		highest in the org tree within which the user has the requested permission
		The arrah of orgId's has matches the order of the perms array
	/);

sub check_user_perms4 {
	my( $self, $client, $authtoken, $userid, $perms ) = @_;
	
	my( $staff, $target, $org, $evt );

	( $staff, $target, $evt ) = $apputils->checkses_requestor(
		$authtoken, $userid, 'VIEW_PERMISSION' );
	return $evt if $evt;

	my @arr;
	return [] unless ref($perms);
	my $tree = $self->get_org_tree();

	for my $p (@$perms) {
		push( @arr, _find_highest_perm_org( $p, $userid, $target->home_ou, $tree ) );
	}
	return \@arr;
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

__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions.count",
	notes		=> <<"	NOTES");
	Returns an object/hash of transaction, circ, title where transaction = an open 
	user transactions (mbts objects), circ is the attached circluation, and title
	is the title the circ points to
	Params are login_session, user_id
	Optional third parameter is the transactions type.  defaults to all
	NOTES

__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions.have_charge.count",
	notes		=> <<"	NOTES");
	Returns an object/hash of transaction, circ, title where transaction = an open 
	user transactions that has an initial charge (mbts objects), circ is the 
	attached circluation, and title is the title the circ points to
	Params are login_session, user_id
	Optional third parameter is the transactions type.  defaults to all
	NOTES

__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions.have_balance.count",
	notes		=> <<"	NOTES");
	Returns an object/hash of transaction, circ, title where transaction = an open 
	user transaction that has a balance (mbts objects), circ is the attached 
	circluation, and title is the title the circ points to
	Params are login_session, user_id
	Optional third parameter is the transaction type.  defaults to all
	NOTES

__PACKAGE__->register_method(
	method	=> "user_transactions",
	api_name	=> "open-ils.actor.user.transactions.have_balance.total",
	notes		=> <<"	NOTES");
	Returns an object/hash of transaction, circ, title where transaction = an open 
	user transaction that has a balance (mbts objects), circ is the attached 
	circluation, and title is the title the circ points to
	Params are login_session, user_id
	Optional third parameter is the transaction type.  defaults to all
	NOTES



sub user_transactions {
	my( $self, $client, $login_session, $user_id, $type ) = @_;

	my( $user_obj, $target, $evt ) = $apputils->checkses_requestor(
		$login_session, $user_id, 'VIEW_USER_TRANSACTIONS' );
	return $evt if $evt;
	
	my $api = $self->api_name();
	my $trans;
	my @xact;

	if(defined($type)) { @xact = (xact_type =>  $type); 

	} else { @xact = (); }

	if($api =~ /have_charge/o) {

		$trans = $apputils->simple_scalar_request( 
			"open-ils.storage",
			"open-ils.storage.direct.money.open_billable_transaction_summary.search_where.atomic",
			{ usr => $user_id, total_owed => { ">" => 0 }, @xact });

	} elsif($api =~ /have_balance/o) {

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

	if($api =~ /total/o) { 
		my $total = 0.0;
		for my $t (@$trans) {
			$total += $t->balance_owed;
		}

		$logger->debug("Total balance owed by user $user_id: $total");
		return $total;
	}

	if($api =~ /count/o) { return scalar @$trans; }
	if($api !~ /fleshed/o) { return $trans; }

	#warn "API: $api\n";

	my @resp;
	for my $t (@$trans) {
			
		#warn $t->id . "\n";


		if( $t->xact_type ne 'circulation' ) {
			push @resp, {transaction => $t};
			next;
		}

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
	method	=> "user_transaction_retrieve",
	api_name	=> "open-ils.actor.user.transaction.fleshed.retrieve",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a fleshedtransaction record
	NOTES
__PACKAGE__->register_method(
	method	=> "user_transaction_retrieve",
	api_name	=> "open-ils.actor.user.transaction.retrieve",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a transaction record
	NOTES
sub user_transaction_retrieve {
	my( $self, $client, $login_session, $bill_id ) = @_;

	my $trans = $apputils->simple_scalar_request( 
		"open-ils.storage",
		"open-ils.storage.direct.money.billable_transaction_summary.retrieve",
		$bill_id
	);

	my( $user_obj, $target, $evt ) = $apputils->checkses_requestor(
		$login_session, $trans->usr, 'VIEW_USER_TRANSACTIONS' );
	return $evt if $evt;
	
	my $api = $self->api_name();
	if($api !~ /fleshed/o) { return $trans; }

	if( $trans->xact_type ne 'circulation' ) {
		$logger->debug("Returning non-circ transaction");
		return {transaction => $trans};
	}

	my $circ = $apputils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.action.circulation.retrieve",
			$trans->id );

	return {transaction => $trans} unless $circ;
	$logger->debug("Found the circ transaction");

	my $title = $apputils->simple_scalar_request(
		"open-ils.storage", 
		"open-ils.storage.fleshed.biblio.record_entry.retrieve_by_copy",
		$circ->target_copy );

	return {transaction => $trans, circ => $circ } unless $title;
	$logger->debug("Found the circ title");

	my $mods;
	try {
		my $u = OpenILS::Utils::ModsParser->new();
		$u->start_mods_batch($title->marc());
		$mods = $u->finish_mods_batch();
	} otherwise {
		if ($title->id == -1) {
			my $copy = $apputils->simple_scalar_request(
				"open-ils.storage",
				"open-ils.storage.direct.asset.copy.retrieve",
				$circ->target_copy );

			$mods = new Fieldmapper::metabib::virtual_record;
			$mods->doc_id(-1);
			$mods->title($copy->dummy_title);
			$mods->author($copy->dummy_author);
		}
	};

	$logger->debug("MODSized the circ title");

	return {transaction => $trans, circ => $circ, record => $mods };
}


__PACKAGE__->register_method(
	method	=> "hold_request_count",
	api_name	=> "open-ils.actor.user.hold_requests.count",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns hold ready/total counts
	NOTES
sub hold_request_count {
	my( $self, $client, $login_session, $userid ) = @_;

	my( $user_obj, $target, $evt ) = $apputils->checkses_requestor(
		$login_session, $userid, 'VIEW_HOLD' );
	return $evt if $evt;
	

	my $holds = $apputils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.action.hold_request.search_where.atomic",
			{ usr => $userid,
			  fulfillment_time => {"=" => undef } }
	);

	my @ready;
	for my $h (@$holds) {
		next unless $h->capture_time;

		my $copy = $apputils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.asset.copy.retrieve",
			$h->current_copy
		);

		if ($copy->status == 8) {
			push @ready, $h;
		}
	}

	return { total => scalar(@$holds), ready => scalar(@ready) };
}


__PACKAGE__->register_method(
	method	=> "checkedout_count",
	api_name	=> "open-ils.actor.user.checked_out.count",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a transaction record
	NOTES
sub checkedout_count {
	my( $self, $client, $login_session, $userid ) = @_;

	my( $user_obj, $target, $evt ) = $apputils->checkses_requestor(
		$login_session, $userid, 'VIEW_CIRCULATIONS' );
	return $evt if $evt;
	

	my $circs = $apputils->simple_scalar_request(
			"open-ils.storage",
			"open-ils.storage.direct.action.circulation.search_where.atomic",
			{ usr => $userid,
			  checkin_time => {"=" => undef } }
	);

	my $parser = DateTime::Format::ISO8601->new;

	my (@out,@overdue);
	for my $c (@$circs) {
		my $due_dt = $parser->parse_datetime( clense_ISO8601( $c->due_date ) );
		my $due = $due_dt->epoch;

		if ($due < time) {
			push @overdue, $c;
		}
	}

	return { total => scalar(@$circs), overdue => scalar(@overdue) };
}

__PACKAGE__->register_method(
	method	=> "user_transaction_history",
	api_name	=> "open-ils.actor.user.transactions.history",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a list of billable transaction ids for a user, optionally by type
	NOTES
sub user_transaction_history {
	my( $self, $client, $login_session, $user_id, $type ) = @_;

	my( $user_obj, $target, $evt ) = $apputils->checkses_requestor(
		$login_session, $user_id, 'VIEW_USER_TRANSACTIONS' );
	return $evt if $evt;
	
	my $api = $self->api_name();
	my @xact;

	@xact = (xact_type =>  $type) if(defined($type));

	my $trans = $apputils->simple_scalar_request( 
		"open-ils.storage",
		"open-ils.storage.direct.money.billable_transaction_summary.search_where.atomic",
		{ usr => $user_id, @xact }, { order_by => 'xact_start DESC' });

	return [ map { $_->id } @$trans ];
}


__PACKAGE__->register_method(
	method	=> "user_perms",
	api_name	=> "open-ils.actor.permissions.user_perms.retrieve",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a list of permissions
	NOTES
sub user_perms {
	my( $self, $client, $authtoken, $user ) = @_;

	my( $staff, $evt ) = $apputils->checkses($authtoken);
	return $evt if $evt;

	$user ||= $staff->id;

	if( $user != $staff->id and $evt = $apputils->check_perms( $staff->id, $staff->home_ou, 'VIEW_PERMISSION') ) {
		return $evt;
	}

	return $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.permission.user_perms.atomic",
		$user);
}

__PACKAGE__->register_method(
	method	=> "retrieve_perms",
	api_name	=> "open-ils.actor.permissions.retrieve",
	notes		=> <<"	NOTES");
	Returns a list of permissions
	NOTES
sub retrieve_perms {
	my( $self, $client ) = @_;
	return $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.permission.perm_list.retrieve.all.atomic");
}

__PACKAGE__->register_method(
	method	=> "retrieve_groups",
	api_name	=> "open-ils.actor.groups.retrieve",
	notes		=> <<"	NOTES");
	Returns a list of user groupss
	NOTES
sub retrieve_groups {
	my( $self, $client ) = @_;
	return $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.permission.grp_tree.retrieve.all.atomic");
}

__PACKAGE__->register_method(
	method	=> "retrieve_groups_tree",
	api_name	=> "open-ils.actor.groups.tree.retrieve",
	notes		=> <<"	NOTES");
	Returns a list of user groups
	NOTES
sub retrieve_groups_tree {
	my( $self, $client ) = @_;
	my $groups = $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.direct.permission.grp_tree.retrieve.all.atomic");
	return $self->build_group_tree($groups);	
}


# turns an org list into an org tree
sub build_group_tree {

	my( $self, $grplist) = @_;

	return $grplist unless ( 
			ref($grplist) and @$grplist > 1 );

	my @list = sort { $a->name cmp $b->name } @$grplist;

	my $root;
	for my $grp (@list) {

		if ($grp and !defined($grp->parent)) {
			$root = $grp;
			next;
		}
		my ($parent) = grep { $_->id == $grp->parent} @list;

		$parent->children([]) unless defined($parent->children); 
		push( @{$parent->children}, $grp );
	}

	return $root;

}


__PACKAGE__->register_method(
	method	=> "add_user_to_groups",
	api_name	=> "open-ils.actor.user.set_groups",
	notes		=> <<"	NOTES");
	Adds a user to one or more permission groups
	NOTES

sub add_user_to_groups {
	my( $self, $client, $authtoken, $userid, $groups ) = @_;

	my( $requestor, $target, $evt ) = $apputils->checkses_requestor(
		$authtoken, $userid, 'CREATE_USER_GROUP_LINK' );
	return $evt if $evt;

	( $requestor, $target, $evt ) = $apputils->checkses_requestor(
		$authtoken, $userid, 'REMOVE_USER_GROUP_LINK' );
	return $evt if $evt;

	$apputils->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.permission.usr_grp_map.mass_delete', { usr => $userid } );
		
	for my $group (@$groups) {
		my $link = Fieldmapper::permission::usr_grp_map->new;
		$link->grp($group);
		$link->usr($userid);

		my $id = $apputils->simplereq(
			'open-ils.storage',
			'open-ils.storage.direct.permission.usr_grp_map.create', $link );
	}

	return 1;
}

__PACKAGE__->register_method(
	method	=> "get_user_perm_groups",
	api_name	=> "open-ils.actor.user.get_groups",
	notes		=> <<"	NOTES");
	Retrieve a user's permission groups.
	NOTES


sub get_user_perm_groups {
	my( $self, $client, $authtoken, $userid ) = @_;

	my( $requestor, $target, $evt ) = $apputils->checkses_requestor(
		$authtoken, $userid, 'VIEW_PERM_GROUPS' );
	return $evt if $evt;

	return $apputils->simplereq(
		'open-ils.storage',
		'open-ils.storage.direct.permission.usr_grp_map.search.usr.atomic', $userid );
}	




1;

