package OpenILS::Application::Actor;
use OpenILS::Application;
use base qw/OpenILS::Application/;
use strict; use warnings;
use Data::Dumper;
$Data::Dumper::Indent = 0;
use OpenILS::Event;

use Digest::MD5 qw(md5_hex);

use OpenSRF::EX qw(:try);
use OpenILS::Perm;

use OpenILS::Application::AppUtils;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::ModsParser;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::SettingsClient;

use OpenSRF::Utils::Cache;

use OpenSRF::Utils::JSON;
use DateTime;
use DateTime::Format::ISO8601;
use OpenILS::Const qw/:const/;

use OpenILS::Application::Actor::Container;
use OpenILS::Application::Actor::ClosedDates;
use OpenILS::Application::Actor::UserGroups;
use OpenILS::Application::Actor::Friends;

use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Penalty;

sub initialize {
	OpenILS::Application::Actor::Container->initialize();
	OpenILS::Application::Actor::UserGroups->initialize();
	OpenILS::Application::Actor::ClosedDates->initialize();
}

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;

sub _d { warn "Patron:\n" . Dumper(shift()); }

my $cache;
my $set_user_settings;
my $set_ou_settings;


__PACKAGE__->register_method(
	method	=> "update_user_setting",
	api_name	=> "open-ils.actor.patron.settings.update",
);
sub update_user_setting {
	my($self, $conn, $auth, $user_id, $settings) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
    return $e->die_event unless $e->checkauth;

    $user_id = $e->requestor->id unless defined $user_id;

    unless($e->requestor->id == $user_id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;
        return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);
    }

    for my $name (keys %$settings) {
        my $val = $$settings{$name};
        my $set = $e->search_actor_user_setting({usr => $user_id, name => $name})->[0];

        if(defined $val) {
            $val = OpenSRF::Utils::JSON->perl2JSON($val);
            if($set) {
                $set->value($val);
                $e->update_actor_user_setting($set) or return $e->die_event;
            } else {
                $set = Fieldmapper::actor::user_setting->new;
                $set->usr($user_id);
                $set->name($name);
                $set->value($val);
                $e->create_actor_user_setting($set) or return $e->die_event;
            }
        } elsif($set) {
            $e->delete_actor_user_setting($set) or return $e->die_event;
        }
    }

    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
	method	=> "set_ou_settings",
	api_name	=> "open-ils.actor.org_unit.settings.update",
);
sub set_ou_settings {
	my( $self, $client, $auth, $org_id, $settings ) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $all_allowed = $e->allowed("UPDATE_ORG_UNIT_SETTING_ALL", $org_id);

	for my $name (keys %$settings) {
        my $val = $$settings{$name};
        my $set = $e->search_actor_org_unit_setting({org_unit => $org_id, name => $name})->[0];

        unless($all_allowed) {
            return $e->die_event unless $e->allowed("UPDATE_ORG_UNIT_SETTING.$name", $org_id);
        }

        if(defined $val) {
            $val = OpenSRF::Utils::JSON->perl2JSON($val);
            if($set) {
                $set->value($val);
                $e->update_actor_org_unit_setting($set) or return $e->die_event;
            } else {
                $set = Fieldmapper::actor::org_unit_setting->new;
                $set->org_unit($org_id);
                $set->name($name);
                $set->value($val);
                $e->create_actor_org_unit_setting($set) or return $e->die_event;
            }
        } elsif($set) {
            $e->delete_actor_org_unit_setting($set) or return $e->die_event;
        }
    }

    $e->commit;
    return 1;
}

my $fetch_user_settings;
my $fetch_ou_settings;

__PACKAGE__->register_method(
	method	=> "user_settings",
	api_name	=> "open-ils.actor.patron.settings.retrieve",
);
sub user_settings {
	my( $self, $client, $auth, $user_id, $setting ) = @_;

    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    $user_id = $e->requestor->id unless defined $user_id;

    my $patron = $e->retrieve_actor_user($user_id) or return $e->event;
    if($e->requestor->id != $user_id) {
        return $e->event unless $e->allowed('VIEW_USER', $patron->home_ou);
    }

    if($setting) {
        my $val = $e->search_actor_user_setting({usr => $user_id, name => $setting})->[0];
        return '' unless $val;
        return OpenSRF::Utils::JSON->JSON2perl($val->value);
    } else {
        my $s = $e->search_actor_user_setting({usr => $user_id});
	    return { map { ( $_->name => OpenSRF::Utils::JSON->JSON2perl($_->value) ) } @$s };
    }
}



__PACKAGE__->register_method(
	method	=> "ou_settings",
	api_name	=> "open-ils.actor.org_unit.settings.retrieve",
);
sub ou_settings {
	my( $self, $client, $ouid ) = @_;
	
	$logger->info("Fetching org unit settings for org $ouid");

	my $s = $apputils->simplereq(
		'open-ils.cstore',
		'open-ils.cstore.direct.actor.org_unit_setting.search.atomic', {org_unit => $ouid});

	return { map { ( $_->name => OpenSRF::Utils::JSON->JSON2perl($_->value) ) } @$s };
}



__PACKAGE__->register_method(
    api_name => 'open-ils.actor.ou_setting.ancestor_default',
    method => 'ou_ancestor_setting',
);

# ------------------------------------------------------------------
# Attempts to find the org setting value for a given org.  if not 
# found at the requested org, searches up the org tree until it 
# finds a parent that has the requested setting.
# when found, returns { org => $id, value => $value }
# otherwise, returns NULL
# ------------------------------------------------------------------
sub ou_ancestor_setting {
    my( $self, $client, $orgid, $name ) = @_;
    return $U->ou_ancestor_setting($orgid, $name);
}

__PACKAGE__->register_method(
    api_name => 'open-ils.actor.ou_setting.ancestor_default.batch',
    method => 'ou_ancestor_setting_batch',
);
sub ou_ancestor_setting_batch {
    my( $self, $client, $orgid, $name_list ) = @_;
    my %values;
    $values{$_} = $U->ou_ancestor_setting($orgid, $_) for @$name_list;
    return \%values;
}




__PACKAGE__->register_method (
	method		=> "ou_setting_delete",
	api_name		=> 'open-ils.actor.org_setting.delete',
	signature	=> q/
		Deletes a specific org unit setting for a specific location
		@param authtoken The login session key
		@param orgid The org unit whose setting we're changing
		@param setting The name of the setting to delete
		@return True value on success.
	/
);

sub ou_setting_delete {
	my( $self, $conn, $authtoken, $orgid, $setting ) = @_;
	my( $reqr, $evt) = $U->checkses($authtoken);
	return $evt if $evt;
	$evt = $U->check_perms($reqr->id, $orgid, 'UPDATE_ORG_SETTING');
	return $evt if $evt;

	my $id = $U->cstorereq(
		'open-ils.cstore.direct.actor.org_unit_setting.id_list', 
		{ name => $setting, org_unit => $orgid } );

	$logger->debug("Retrieved setting $id in org unit setting delete");

	my $s = $U->cstorereq(
		'open-ils.cstore.direct.actor.org_unit_setting.delete', $id );

	$logger->activity("User ".$reqr->id." deleted org unit setting $id") if $s;
	return $s;
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

	$evt = check_group_perm($session, $user_obj, $patron);
	return $evt if $evt;


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

	($new_patron, $evt) = _create_stat_maps($session, $user_session, $patron, $new_patron, $user_obj);
	return $evt if $evt;

	($new_patron, $evt) = _create_perm_maps($session, $user_session, $patron, $new_patron, $user_obj);
	return $evt if $evt;

	$logger->activity("user ".$user_obj->id." updating/creating  user ".$new_patron->id);

	my $opatron;
	if(!$patron->isnew) {
		$opatron = new_editor()->retrieve_actor_user($new_patron->id);
	}

	$apputils->commit_db_session($session);

	return flesh_user($new_patron->id(), new_editor(requestor => $user_obj));
}


sub flesh_user {
	my $id = shift;
    my $e = shift;
	return new_flesh_user($id, [
		"cards",
		"card",
		"standing_penalties",
		"addresses",
		"billing_address",
		"mailing_address",
		"stat_cat_entries" ], $e );
}






# clone and clear stuff that would break the database
sub _clone_patron {
	my $patron = shift;

	my $new_patron = $patron->clone;
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

	my $ex = $session->request(
		'open-ils.storage.direct.actor.user.search.usrname', $patron->usrname())->gather(1);
	if( $ex and @$ex ) {
		return (undef, OpenILS::Event->new('USERNAME_EXISTS'));
	}

	$logger->info("Creating new user in the DB with username: ".$patron->usrname());

	my $id = $session->request(
		"open-ils.storage.direct.actor.user.create", $patron)->gather(1);
	return (undef, $U->DB_UPDATE_FAILED($patron)) unless $id;

	$logger->info("Successfully created new user [$id] in DB");

	return ( $session->request( 
		"open-ils.storage.direct.actor.user.retrieve", $id)->gather(1), undef );
}


sub check_group_perm {
	my( $session, $requestor, $patron ) = @_;
	my $evt;

	# first let's see if the requestor has 
	# priveleges to update this user in any way
	if( ! $patron->isnew ) {
		my $p = $session->request(
			'open-ils.storage.direct.actor.user.retrieve', $patron->id )->gather(1);

		# If we are the requestor (trying to update our own account)
		# and we are not trying to change our profile, we're good
		if( $p->id == $requestor->id and 
				$p->profile == $patron->profile ) {
			return undef;
		}


		$evt = group_perm_failed($session, $requestor, $p);
		return $evt if $evt;
	}

	# They are allowed to edit this patron.. can they put the 
	# patron into the group requested?
	$evt = group_perm_failed($session, $requestor, $patron);
	return $evt if $evt;
	return undef;
}


sub group_perm_failed {
	my( $session, $requestor, $patron ) = @_;

	my $perm;
	my $grp;
	my $grpid = $patron->profile;

	do {

		$logger->debug("user update looking for group perm for group $grpid");
		$grp = $session->request(
			'open-ils.storage.direct.permission.grp_tree.retrieve', $grpid )->gather(1);
		return OpenILS::Event->new('PERMISSION_GRP_TREE_NOT_FOUND') unless $grp;

	} while( !($perm = $grp->application_perm) and ($grpid = $grp->parent) );

	$logger->info("user update checking perm $perm on user ".
		$requestor->id." for update/create on user username=".$patron->usrname);

	my $evt = $U->check_perms($requestor->id, $patron->home_ou, $perm);
	return $evt if $evt;
	return undef;
}



sub _update_patron {
	my( $session, $patron, $user_obj, $noperm) = @_;

	$logger->info("Updating patron ".$patron->id." in DB");

	my $evt;

	if(!$noperm) {
		$evt = $U->check_perms($user_obj->id, $patron->home_ou, 'UPDATE_USER');
		return (undef, $evt) if $evt;
	}

	# update the password by itself to avoid the password protection magic
	if( $patron->passwd ) {
		my $s = $session->request(
			'open-ils.storage.direct.actor.user.remote_update',
			{id => $patron->id}, {passwd => $patron->passwd})->gather(1);
		return (undef, $U->DB_UPDATE_FAILED($patron)) unless defined($s);
		$patron->clear_passwd;
	}

	if(!$patron->ident_type) {
		$patron->clear_ident_type;
		$patron->clear_ident_value;
	}

    $evt = verify_last_xact($session, $patron);
    return (undef, $evt) if $evt;

	my $stat = $session->request(
		"open-ils.storage.direct.actor.user.update",$patron )->gather(1);
	return (undef, $U->DB_UPDATE_FAILED($patron)) unless defined($stat);

	return ($patron);
}

sub verify_last_xact {
    my( $session, $patron ) = @_;
    return undef unless $patron->id and $patron->id > 0;
    my $p = $session->request(
        'open-ils.storage.direct.actor.user.retrieve', $patron->id)->gather(1);
    my $xact = $p->last_xact_id;
    return undef unless $xact;
    $logger->info("user xact = $xact, saving with xact " . $patron->last_xact_id);
    return OpenILS::Event->new('XACT_COLLISION')
        if $xact != $patron->last_xact_id;
    return undef;
}


sub _check_dup_ident {
	my( $session, $patron ) = @_;

	return undef unless $patron->ident_value;

	my $search = {
		ident_type	=> $patron->ident_type, 
		ident_value => $patron->ident_value,
	};

	$logger->debug("patron update searching for dup ident values: " . 
		$patron->ident_type . ':' . $patron->ident_value);

	$search->{id} = {'!=' => $patron->id} if $patron->id and $patron->id > 0;

	my $dups = $session->request(
		'open-ils.storage.direct.actor.user.search_where.atomic', $search )->gather(1);


	return OpenILS::Event->new('PATRON_DUP_IDENT1', payload => $patron )
		if $dups and @$dups;

	return undef;
}


sub _add_update_addresses {

	my $session = shift;
	my $patron = shift;
	my $new_patron = shift;

	my $evt;

	my $current_id; # id of the address before creation

	for my $address (@{$patron->addresses()}) {

		next unless ref $address;
		$current_id = $address->id();

		if( $patron->billing_address() and
			$patron->billing_address() == $current_id ) {
			$logger->info("setting billing addr to $current_id");
			$new_patron->billing_address($address->id());
			$new_patron->ischanged(1);
		}
	
		if( $patron->mailing_address() and
			$patron->mailing_address() == $current_id ) {
			$new_patron->mailing_address($address->id());
			$logger->info("setting mailing addr to $current_id");
			$new_patron->ischanged(1);
		}


		if($address->isnew()) {

			$address->usr($new_patron->id());

			($address, $evt) = _add_address($session,$address);
			return (undef, $evt) if $evt;

			# we need to get the new id
			if( $patron->billing_address() and 
					$patron->billing_address() == $current_id ) {
				$new_patron->billing_address($address->id());
				$logger->info("setting billing addr to $current_id");
				$new_patron->ischanged(1);
			}

			if( $patron->mailing_address() and
					$patron->mailing_address() == $current_id ) {
				$new_patron->mailing_address($address->id());
				$logger->info("setting mailing addr to $current_id");
				$new_patron->ischanged(1);
			}

		} elsif($address->ischanged() ) {

			($address, $evt) = _update_address($session, $address);
			return (undef, $evt) if $evt;

		} elsif($address->isdeleted() ) {

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


__PACKAGE__->register_method(
	method	=> "set_user_work_ous",
	api_name	=> "open-ils.actor.user.work_ous.update",
);

sub set_user_work_ous {
	my $self = shift;
	my $client = shift;
	my $ses = shift;
	my $maps = shift;

	my( $requestor, $evt ) = $apputils->checksesperm( $ses, 'ASSIGN_WORK_ORG_UNIT' );
	return $evt if $evt;

	my $session = $apputils->start_db_session();

	for my $map (@$maps) {

		my $method = "open-ils.storage.direct.permission.usr_work_ou_map.update";
		if ($map->isdeleted()) {
			$method = "open-ils.storage.direct.permission.usr_work_ou_map.delete";
		} elsif ($map->isnew()) {
			$method = "open-ils.storage.direct.permission.usr_work_ou_map.create";
			$map->clear_id;
		}

		#warn( "Updating permissions with method $method and session $ses and map $map" );
		$logger->info( "Updating work_ou map with method $method and map $map" );

		my $stat = $session->request($method, $map)->gather(1);
		$logger->warn( "update failed: ".$U->DB_UPDATE_FAILED($map) ) unless defined($stat);

	}

	$apputils->commit_db_session($session);

	return scalar(@$maps);
}


__PACKAGE__->register_method(
	method	=> "set_user_perms",
	api_name	=> "open-ils.actor.user.permissions.update",
);

sub set_user_perms {
	my $self = shift;
	my $client = shift;
	my $ses = shift;
	my $maps = shift;

	my $session = $apputils->start_db_session();

	my( $user_obj, $evt ) = $U->checkses($ses);
	return $evt if $evt;

	my $perms = $session->request('open-ils.storage.permission.user_perms.atomic', $user_obj->id)->gather(1);

	my $all = undef;
	$all = 1 if ($U->is_true($user_obj->super_user()));
    $all = 1 unless ($U->check_perms($user_obj->id, $user_obj->home_ou, 'EVERYTHING'));

	for my $map (@$maps) {

		my $method = "open-ils.storage.direct.permission.usr_perm_map.update";
		if ($map->isdeleted()) {
			$method = "open-ils.storage.direct.permission.usr_perm_map.delete";
		} elsif ($map->isnew()) {
			$method = "open-ils.storage.direct.permission.usr_perm_map.create";
			$map->clear_id;
		}

		next if (!$all and !grep { $_->perm eq $map->perm and $U->is_true($_->grantable) and $_->depth <= $map->depth } @$perms);
		#warn( "Updating permissions with method $method and session $ses and map $map" );
		$logger->info( "Updating permissions with method $method and map $map" );

		my $stat = $session->request($method, $map)->gather(1);
		$logger->warn( "update failed: ".$U->DB_UPDATE_FAILED($map) ) unless defined($stat);

	}

	$apputils->commit_db_session($session);

	return scalar(@$maps);
}


__PACKAGE__->register_method(
	method	=> "user_retrieve_by_barcode",
    authoritative => 1,
	api_name	=> "open-ils.actor.user.fleshed.retrieve_by_barcode",);

sub user_retrieve_by_barcode {
	my($self, $client, $user_session, $barcode) = @_;

	$logger->debug("Searching for user with barcode $barcode");
	my ($user_obj, $evt) = $apputils->checkses($user_session);
	return $evt if $evt;

	my $card = OpenILS::Application::AppUtils->simple_scalar_request(
			"open-ils.cstore", 
			"open-ils.cstore.direct.actor.card.search.atomic",
			{ barcode => $barcode }
	);

	if(!$card || !$card->[0]) {
		return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' );
	}

	$card = $card->[0];
	my $user = flesh_user($card->usr(), new_editor(requestor => $user_obj));

	$evt = $U->check_perms($user_obj->id, $user->home_ou, 'VIEW_USER');
	return $evt if $evt;

	if(!$user) { return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' ); }
	return $user;

}



__PACKAGE__->register_method(
	method	=> "get_user_by_id",
    authoritative => 1,
	api_name	=> "open-ils.actor.user.retrieve",);

sub get_user_by_id {
	my ($self, $client, $auth, $id) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	my $user = $e->retrieve_actor_user($id)
		or return $e->event;
	return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);	
	return $user;
}



__PACKAGE__->register_method(
	method	=> "get_org_types",
	api_name	=> "open-ils.actor.org_types.retrieve",);

sub get_org_types {
    return $U->get_org_types();
}



__PACKAGE__->register_method(
	method	=> "get_user_ident_types",
	api_name	=> "open-ils.actor.user.ident_types.retrieve",
);
my $ident_types;
sub get_user_ident_types {
	return $ident_types if $ident_types;
	return $ident_types = 
		new_editor()->retrieve_all_config_identification_type();
}




__PACKAGE__->register_method(
	method	=> "get_org_unit",
	api_name	=> "open-ils.actor.org_unit.retrieve",
);

sub get_org_unit {
	my( $self, $client, $user_session, $org_id ) = @_;
	my $e = new_editor(authtoken => $user_session);
	if(!$org_id) {
		return $e->event unless $e->checkauth;
		$org_id = $e->requestor->ws_ou;
	}
	my $o = $e->retrieve_actor_org_unit($org_id)
		or return $e->event;
	return $o;
}

__PACKAGE__->register_method(
	method	=> "search_org_unit",
	api_name	=> "open-ils.actor.org_unit_list.search",
);

sub search_org_unit {

	my( $self, $client, $field, $value ) = @_;

	my $list = OpenILS::Application::AppUtils->simple_scalar_request(
		"open-ils.cstore",
		"open-ils.cstore.direct.actor.org_unit.search.atomic", 
		{ $field => $value } );

	return $list;
}


# build the org tree

__PACKAGE__->register_method(
	method	=> "get_org_tree",
	api_name	=> "open-ils.actor.org_tree.retrieve",
	argc		=> 0, 
	note		=> "Returns the entire org tree structure",
);

sub get_org_tree {
	my $self = shift;
	my $client = shift;
    return $U->get_org_tree($client->session->session_locale);
}


__PACKAGE__->register_method(
	method	=> "get_org_descendants",
	api_name	=> "open-ils.actor.org_tree.descendants.retrieve"
);

# depth is optional.  org_unit is the id
sub get_org_descendants {
	my( $self, $client, $org_unit, $depth ) = @_;

    if(ref $org_unit eq 'ARRAY') {
        $depth ||= [];
        my @trees;
        for my $i (0..scalar(@$org_unit)-1) {
            my $list = $U->simple_scalar_request(
			    "open-ils.storage", 
			    "open-ils.storage.actor.org_unit.descendants.atomic",
			    $org_unit->[$i], $depth->[$i] );
            push(@trees, $U->build_org_tree($list));
        }
        return \@trees;

    } else {
	    my $orglist = $apputils->simple_scalar_request(
			    "open-ils.storage", 
			    "open-ils.storage.actor.org_unit.descendants.atomic",
			    $org_unit, $depth );
	    return $U->build_org_tree($orglist);
    }
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
	return $U->build_org_tree($orglist);
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
			"open-ils.cstore",
			"open-ils.cstore.direct.config.standing.search.atomic",
			{ id => { "!=" => undef } }
		);
}



__PACKAGE__->register_method(
	method	=> "get_my_org_path",
	api_name	=> "open-ils.actor.org_unit.full_path.retrieve"
);

sub get_my_org_path {
	my( $self, $client, $auth, $org_id ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	$org_id = $e->requestor->ws_ou unless defined $org_id;

	return $apputils->simple_scalar_request(
		"open-ils.storage",
		"open-ils.storage.actor.org_unit.full_path.atomic",
		$org_id );
}


__PACKAGE__->register_method(
	method	=> "patron_adv_search",
	api_name	=> "open-ils.actor.patron.search.advanced" );
sub patron_adv_search {
	my( $self, $client, $auth, $search_hash, 
        $search_limit, $search_sort, $include_inactive, $search_depth ) = @_;

	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->event unless $e->allowed('VIEW_USER');
	return $U->storagereq(
		"open-ils.storage.actor.user.crazy_search", $search_hash, 
            $search_limit, $search_sort, $include_inactive, $e->requestor->ws_ou, $search_depth);
}


__PACKAGE__->register_method(
	method	=> "update_passwd",
    authoritative => 1,
	api_name	=> "open-ils.actor.user.password.update");

__PACKAGE__->register_method(
	method	=> "update_passwd",
	api_name	=> "open-ils.actor.user.username.update");

__PACKAGE__->register_method(
	method	=> "update_passwd",
	api_name	=> "open-ils.actor.user.email.update");

sub update_passwd {
    my( $self, $conn, $auth, $new_val, $orig_pw ) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $db_user = $e->retrieve_actor_user($e->requestor->id)
        or return $e->die_event;
    my $api = $self->api_name;

    if( $api =~ /password/o ) {

        # make sure the original password matches the in-database password
        return OpenILS::Event->new('INCORRECT_PASSWORD')
            if md5_hex($orig_pw) ne $db_user->passwd;
        $db_user->passwd($new_val);

    } else {

        # if we don't clear the password, the user will be updated with
        # a hashed version of the hashed version of their password
        $db_user->clear_passwd;

        if( $api =~ /username/o ) {

            # make sure no one else has this username
            my $exist = $e->search_actor_user({usrname=>$new_val},{idlist=>1}); 
			return OpenILS::Event->new('USERNAME_EXISTS') if @$exist;
            $db_user->usrname($new_val);

        } elsif( $api =~ /email/o ) {
            $db_user->email($new_val);
        }
    }

    $e->update_actor_user($db_user) or return $e->die_event;
    $e->commit;
    return 1;
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
		if( $evt = $apputils->check_perms(
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
	my($self, $client, $authtoken, $user_id, $perm) = @_;
	my $e = new_editor(authtoken=>$authtoken);
	return $e->event unless $e->checkauth;

	my $tree = $U->get_org_tree();

    unless($e->requestor->id == $user_id) {
        my $user = $e->retrieve_actor_user($user_id)
            or return $e->event;
        return $e->event unless $e->allowed('VIEW_PERMISSION', $user->home_ou);
	    return $U->find_highest_perm_org($perm, $user_id, $user->home_ou, $tree );
    }

    return $U->find_highest_perm_org($perm, $user_id, $e->requestor->ws_ou, $tree);
}

__PACKAGE__->register_method(
	method => 'user_has_work_perm_at',
	api_name	=> 'open-ils.actor.user.has_work_perm_at',
    authoritative => 1,
    signature => {
        desc => q/
            Returns a set of org unit IDs which represent the highest orgs in 
            the org tree where the user has the requested permission.  The
            purpose of this method is to return the smallest set of org units
            which represent the full expanse of the user's ability to perform
            the requested action.  The user whose perms this method should
            check is implied by the authtoken. /,
        params => [
		    {desc => 'authtoken', type => 'string'},
            {desc => 'permission name', type => 'string'},
        ],
        return => {desc => 'An array of org IDs'}
    }
);

sub user_has_work_perm_at {
    my($self, $conn, $auth, $perm) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $U->user_has_work_perm_at($e, $perm);
}

__PACKAGE__->register_method(
	method => 'user_has_work_perm_at_batch',
	api_name	=> 'open-ils.actor.user.has_work_perm_at.batch',
    authoritative => 1,
);

sub user_has_work_perm_at_batch {
    my($self, $conn, $auth, $perms) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    my $map = {};
    $map->{$_} = $U->user_has_work_perm_at($e, $_) for @$perms;
    return $map;
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
	my $tree = $U->get_org_tree();

	for my $p (@$perms) {
		push( @arr, $U->find_highest_perm_org( $p, $userid, $target->home_ou, $tree ) );
	}
	return \@arr;
}




__PACKAGE__->register_method(
	method	=> "user_fines_summary",
	api_name	=> "open-ils.actor.user.fines.summary",
    authoritative => 1,
	notes		=> <<"	NOTES");
	Returns a short summary of the users total open fines, excluding voided fines
	Params are login_session, user_id
	Returns a 'mous' object.
	NOTES

sub user_fines_summary {
	my( $self, $client, $auth, $user_id ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	my $user = $e->retrieve_actor_user($user_id)
		or return $e->event;

	if( $user_id ne $e->requestor->id ) {
		return $e->event unless 
			$e->allowed('VIEW_USER_FINES_SUMMARY', $user->home_ou);
	}
	
	# run this inside a transaction to prevent replication delay errors
	my $ses = $U->start_db_session();
	my $s = $ses->request(
		'open-ils.storage.money.open_user_summary.search', $user_id )->gather(1);
	$U->rollback_db_session($ses);
	return $s;
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

	($trans) = $self
		->method_lookup('open-ils.actor.user.transactions.history.still_open')
		->run($login_session => $user_id => $type);

	if($api =~ /have_charge/o) {

		$trans = [ grep { int($_->total_owed * 100) > 0 } @$trans ];

	} elsif($api =~ /have_balance/o) {

		$trans = [ grep { int($_->balance_owed * 100) != 0 } @$trans ];
	} else {

		$trans = [ grep { int($_->total_owed * 100) > 0 } @$trans ];

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

	my @resp;
	for my $t (@$trans) {
			
		if( $t->xact_type ne 'circulation' ) {
			push @resp, {transaction => $t};
			next;
		}

		my $circ = $apputils->simple_scalar_request(
				"open-ils.cstore",
				"open-ils.cstore.direct.action.circulation.retrieve",
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
		$mods->doc_id($title->id) if $mods;

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

	# XXX I think I'm deprecated... make sure

	my $trans = $apputils->simple_scalar_request( 
		"open-ils.cstore",
		"open-ils.cstore.direct.money.billable_transaction_summary.retrieve",
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
			"open-ils.cstore",
			"open-ils..direct.action.circulation.retrieve",
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
		if ($title->id == OILS_PRECAT_RECORD) {
			my $copy = $apputils->simple_scalar_request(
				"open-ils.cstore",
				"open-ils.cstore.direct.asset.copy.retrieve",
				$circ->target_copy );

			$mods = new Fieldmapper::metabib::virtual_record;
			$mods->doc_id(OILS_PRECAT_RECORD);
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
    authoritative => 1,
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
			"open-ils.cstore",
			"open-ils.cstore.direct.action.hold_request.search.atomic",
			{ 
				usr => $userid,
				fulfillment_time => {"=" => undef },
				cancel_time => undef,
			}
	);

	my @ready;
	for my $h (@$holds) {
		next unless $h->capture_time and $h->current_copy;

		my $copy = $apputils->simple_scalar_request(
			"open-ils.cstore",
			"open-ils.cstore.direct.asset.copy.retrieve",
			$h->current_copy
		);

		if ($copy and $copy->status == 8) {
			push @ready, $h;
		}
	}

	return { total => scalar(@$holds), ready => scalar(@ready) };
}


__PACKAGE__->register_method(
	method	=> "checkedout_count",
	api_name	=> "open-ils.actor.user.checked_out.count__",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a transaction record
	NOTES

# XXX Deprecate Me
sub checkedout_count {
	my( $self, $client, $login_session, $userid ) = @_;

	my( $user_obj, $target, $evt ) = $apputils->checkses_requestor(
		$login_session, $userid, 'VIEW_CIRCULATIONS' );
	return $evt if $evt;
	
	my $circs = $apputils->simple_scalar_request(
			"open-ils.cstore",
			"open-ils.cstore.direct.action.circulation.search.atomic",
			{ usr => $userid, stop_fines => undef }
			#{ usr => $userid, checkin_time => {"=" => undef } }
	);

	my $parser = DateTime::Format::ISO8601->new;

	my (@out,@overdue);
	for my $c (@$circs) {
		my $due_dt = $parser->parse_datetime( clense_ISO8601( $c->due_date ) );
		my $due = $due_dt->epoch;

		if ($due < DateTime->today->epoch) {
			push @overdue, $c;
		}
	}

	return { total => scalar(@$circs), overdue => scalar(@overdue) };
}


__PACKAGE__->register_method(
	method		=> "checked_out",
	api_name		=> "open-ils.actor.user.checked_out",
    authoritative => 1,
	argc			=> 2,
	signature	=> q/
		Returns a structure of circulations objects sorted by
		out, overdue, lost, claims_returned, long_overdue.
		A list of IDs are returned of each type.
		lost, long_overdue, and claims_returned circ will not
		be "finished" (there is an outstanding balance or some 
		other pending action on the circ). 

		The .count method also includes a 'total' field which 
		sums all "open" circs
	/
);

__PACKAGE__->register_method(
	method		=> "checked_out",
	api_name		=> "open-ils.actor.user.checked_out.count",
    authoritative => 1,
	argc			=> 2,
	signature	=> q/@see open-ils.actor.user.checked_out/
);

sub checked_out {
	my( $self, $conn, $auth, $userid ) = @_;

	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;

	if( $userid ne $e->requestor->id ) {
        my $user = $e->retrieve_actor_user($userid) or return $e->event;
		unless($e->allowed('VIEW_CIRCULATIONS', $user->home_ou)) {

            # see if there is a friend link allowing circ.view perms
            my $allowed = OpenILS::Application::Actor::Friends->friend_perm_allowed(
                $e, $userid, $e->requestor->id, 'circ.view');
            return $e->event unless $allowed;
        }
	}

	my $count = $self->api_name =~ /count/;
	return _checked_out( $count, $e, $userid );
}

sub _checked_out {
	my( $iscount, $e, $userid ) = @_;
	my $meth = 'open-ils.storage.actor.user.checked_out';
	$meth = "$meth.count" if $iscount;
	return $U->storagereq($meth, $userid);
}


sub _checked_out_WHAT {
	my( $iscount, $e, $userid ) = @_;

	my $circs = $e->search_action_circulation( 
		{ usr => $userid, stop_fines => undef });

	my $mcircs = $e->search_action_circulation( 
		{ 
			usr => $userid, 
			checkin_time => undef, 
			xact_finish => undef, 
		});

	
	push( @$circs, @$mcircs );

	my $parser = DateTime::Format::ISO8601->new;

	# split the circs up into overdue and not-overdue circs
	my (@out,@overdue);
	for my $c (@$circs) {
		if( $c->due_date ) {
			my $due_dt = $parser->parse_datetime( clense_ISO8601( $c->due_date ) );
			my $due = $due_dt->epoch;
			if ($due < DateTime->today->epoch) {
				push @overdue, $c->id;
			} else {
				push @out, $c->id;
			}
		} else {
			push @out, $c->id;
		}
	}

	# grab all of the lost, claims-returned, and longoverdue circs
	#my $open = $e->search_action_circulation(
	#	{usr => $userid, stop_fines => { '!=' => undef }, xact_finish => undef });


	# these items have stop_fines, but no xact_finish, so money
	# is owed on them and they have not been checked in
	my $open = $e->search_action_circulation(
		{
			usr				=> $userid, 
			stop_fines		=> { in => [ qw/LOST CLAIMSRETURNED LONGOVERDUE/ ] }, 
			xact_finish		=> undef,
			checkin_time	=> undef,
		}
	);


	my( @lost, @cr, @lo );
	for my $c (@$open) {
		push( @lost, $c->id ) if $c->stop_fines eq 'LOST';
		push( @cr, $c->id ) if $c->stop_fines eq 'CLAIMSRETURNED';
		push( @lo, $c->id ) if $c->stop_fines eq 'LONGOVERDUE';
	}


	if( $iscount ) {
		return {
			total		=> @$circs + @lost + @cr + @lo,
			out		=> scalar(@out),
			overdue	=> scalar(@overdue),
			lost		=> scalar(@lost),
			claims_returned	=> scalar(@cr),
			long_overdue		=> scalar(@lo)
		};
	}

	return {
		out		=> \@out,
		overdue	=> \@overdue,
		lost		=> \@lost,
		claims_returned	=> \@cr,
		long_overdue		=> \@lo
	};
}



__PACKAGE__->register_method(
	method		=> "checked_in_with_fines",
	api_name		=> "open-ils.actor.user.checked_in_with_fines",
    authoritative => 1,
	argc			=> 2,
	signature	=> q/@see open-ils.actor.user.checked_out/
);
sub checked_in_with_fines {
	my( $self, $conn, $auth, $userid ) = @_;

	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;

	if( $userid ne $e->requestor->id ) {
		return $e->event unless $e->allowed('VIEW_CIRCULATIONS');
	}

	# money is owed on these items and they are checked in
	my $open = $e->search_action_circulation(
		{
			usr				=> $userid, 
			xact_finish		=> undef,
			checkin_time	=> { "!=" => undef },
		}
	);


	my( @lost, @cr, @lo );
	for my $c (@$open) {
		push( @lost, $c->id ) if $c->stop_fines eq 'LOST';
		push( @cr, $c->id ) if $c->stop_fines eq 'CLAIMSRETURNED';
		push( @lo, $c->id ) if $c->stop_fines eq 'LONGOVERDUE';
	}

	return {
		lost		=> \@lost,
		claims_returned	=> \@cr,
		long_overdue		=> \@lo
	};
}









__PACKAGE__->register_method(
	method	=> "user_transaction_history",
	api_name	=> "open-ils.actor.user.transactions.history",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a list of billable transaction ids for a user, optionally by type
	NOTES
__PACKAGE__->register_method(
	method	=> "user_transaction_history",
	api_name	=> "open-ils.actor.user.transactions.history.have_charge",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a list of billable transaction ids for a user that have an initial charge, optionally by type
	NOTES
__PACKAGE__->register_method(
	method	=> "user_transaction_history",
	api_name	=> "open-ils.actor.user.transactions.history.have_balance",
    authoritative => 1,
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a list of billable transaction ids for a user that have a balance, optionally by type
	NOTES
__PACKAGE__->register_method(
	method	=> "user_transaction_history",
	api_name	=> "open-ils.actor.user.transactions.history.still_open",
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a list of billable transaction ids for a user that are not finished
	NOTES
__PACKAGE__->register_method(
	method	=> "user_transaction_history",
	api_name	=> "open-ils.actor.user.transactions.history.have_bill",
    authoritative => 1,
	argc		=> 1,
	notes		=> <<"	NOTES");
	Returns a list of billable transaction ids for a user that has billings
	NOTES

sub user_transaction_history {
	my( $self, $conn, $auth, $userid, $type ) = @_;

	# run inside of a transaction to prevent replication delays
	my $e = new_editor(xact=>1, authtoken=>$auth);
	return $e->die_event unless $e->checkauth;

	if( $e->requestor->id ne $userid ) {
		return $e->die_event 
			unless $e->allowed('VIEW_USER_TRANSACTIONS');
	}

	my $api = $self->api_name;
	my @xact_finish  = (xact_finish => undef ) if ($api =~ /history.still_open$/);

	my @xacts = @{ $e->search_money_billable_transaction(
		[	{ usr => $userid, @xact_finish },
			{ flesh => 1,
			  flesh_fields => { mbt => [ qw/billings payments grocery circulation/ ] },
			  order_by => { mbt => 'xact_start DESC' },
			}
		],
      {substream => 1}
	) };

	$e->rollback;

	my @mbts = $U->make_mbts( $e, @xacts );

	if(defined($type)) {
		@mbts = grep { $_->xact_type eq $type } @mbts;
	}

	if($api =~ /have_balance/o) {
		@mbts = grep { int($_->balance_owed * 100) != 0 } @mbts;
	}

	if($api =~ /have_charge/o) {
		@mbts = grep { defined($_->last_billing_ts) } @mbts;
	}

	if($api =~ /have_bill/o) {
		@mbts = grep { int($_->total_owed * 100) != 0 } @mbts;
	}

	return [@mbts];
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
		"open-ils.cstore",
		"open-ils.cstore.direct.permission.perm_list.search.atomic",
		{ id => { '!=' => undef } }
	);
}

__PACKAGE__->register_method(
	method	=> "retrieve_groups",
	api_name	=> "open-ils.actor.groups.retrieve",
	notes		=> <<"	NOTES");
	Returns a list of user groupss
	NOTES
sub retrieve_groups {
	my( $self, $client ) = @_;
	return new_editor()->retrieve_all_permission_grp_tree();
}

__PACKAGE__->register_method(
	method	=> "retrieve_org_address",
	api_name	=> "open-ils.actor.org_unit.address.retrieve",
	notes		=> <<'	NOTES');
	Returns an org_unit address by ID
	@param An org_address ID
	NOTES
sub retrieve_org_address {
	my( $self, $client, $id ) = @_;
	return $apputils->simple_scalar_request(
		"open-ils.cstore",
		"open-ils.cstore.direct.actor.org_address.retrieve",
		$id
	);
}

__PACKAGE__->register_method(
	method	=> "retrieve_groups_tree",
	api_name	=> "open-ils.actor.groups.tree.retrieve",
	notes		=> <<"	NOTES");
	Returns a list of user groups
	NOTES
sub retrieve_groups_tree {
	my( $self, $client ) = @_;
	return new_editor()->search_permission_grp_tree(
		[
			{ parent => undef},
			{	
				flesh				=> -1,
				flesh_fields	=> { pgt => ["children"] }, 
				order_by			=> { pgt => 'name'}
			}
		]
	)->[0];
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
		'open-ils.cstore',
		'open-ils.cstore.direct.permission.usr_grp_map.search.atomic', { usr => $userid } );
}	


__PACKAGE__->register_method(
	method	=> "get_user_work_ous",
	api_name	=> "open-ils.actor.user.get_work_ous",
	notes		=> <<"	NOTES");
	Retrieve a user's work org units.
	NOTES
__PACKAGE__->register_method(
	method	=> "get_user_work_ous",
	api_name	=> "open-ils.actor.user.get_work_ous.ids",
	notes		=> <<"	NOTES");
	Retrieve a user's work org units.
	NOTES


sub get_user_work_ous {
	my( $self, $client, $auth, $userid ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    $userid ||= $e->requestor->id;

    if($e->requestor->id != $userid) {
        my $user = $e->retrieve_actor_user($userid)
            or return $e->event;
        return $e->event unless $e->allowed('ASSIGN_WORK_ORG_UNIT', $user->home_ou);
    }

    return $e->search_permission_usr_work_ou_map({usr => $userid})
        unless $self->api_name =~ /.ids$/;

    # client just wants a list of org IDs
    return $U->get_user_work_ou_ids($e, $userid);
}	




__PACKAGE__->register_method (
	method		=> 'register_workstation',
	api_name		=> 'open-ils.actor.workstation.register.override',
	signature	=> q/@see open-ils.actor.workstation.register/);

__PACKAGE__->register_method (
	method		=> 'register_workstation',
	api_name		=> 'open-ils.actor.workstation.register',
	signature	=> q/
		Registers a new workstion in the system
		@param authtoken The login session key
		@param name The name of the workstation id
		@param owner The org unit that owns this workstation
		@return The workstation id on success, WORKSTATION_NAME_EXISTS
		if the name is already in use.
	/);

sub register_workstation {
	my( $self, $conn, $authtoken, $name, $owner ) = @_;

	my $e = new_editor(authtoken=>$authtoken, xact=>1);
	return $e->die_event unless $e->checkauth;
	return $e->die_event unless $e->allowed('REGISTER_WORKSTATION', $owner);
	my $existing = $e->search_actor_workstation({name => $name})->[0];

	if( $existing ) {

		if( $self->api_name =~ /override/o ) {
            # workstation with the given name exists.  

            if($owner ne $existing->owning_lib) {
                # if necessary, update the owning_lib of the workstation

                $logger->info("changing owning lib of workstation ".$existing->id.
                    " from ".$existing->owning_lib." to $owner");
			    return $e->die_event unless 
                    $e->allowed('UPDATE_WORKSTATION', $existing->owning_lib); 

			    return $e->die_event unless $e->allowed('UPDATE_WORKSTATION', $owner); 

                $existing->owning_lib($owner);
			    return $e->die_event unless $e->update_actor_workstation($existing);

                $e->commit;

            } else {
                $logger->info(  
                    "attempt to register an existing workstation.  returning existing ID");
            }

            return $existing->id;

		} else {
			return OpenILS::Event->new('WORKSTATION_NAME_EXISTS')
		}
	}

	my $ws = Fieldmapper::actor::workstation->new;
	$ws->owning_lib($owner);
	$ws->name($name);
	$e->create_actor_workstation($ws) or return $e->die_event;
	$e->commit;
	return $ws->id; # note: editor sets the id on the new object for us
}

__PACKAGE__->register_method (
	method		=> 'workstation_list',
	api_name		=> 'open-ils.actor.workstation.list',
	signature	=> q/
		Returns a list of workstations registered at the given location
		@param authtoken The login session key
		@param ids A list of org_unit.id's for the workstation owners
	/);

sub workstation_list {
	my( $self, $conn, $authtoken, @orgs ) = @_;

	my $e = new_editor(authtoken=>$authtoken);
	return $e->event unless $e->checkauth;
    my %results;

    for my $o (@orgs) {
	    return $e->event 
            unless $e->allowed('REGISTER_WORKSTATION', $o);
        $results{$o} = $e->search_actor_workstation({owning_lib=>$o});
    }
    return \%results;
}







__PACKAGE__->register_method (
	method		=> 'fetch_patron_note',
	api_name		=> 'open-ils.actor.note.retrieve.all',
    authoritative => 1,
	signature	=> q/
		Returns a list of notes for a given user
		Requestor must have VIEW_USER permission if pub==false and
		@param authtoken The login session key
		@param args Hash of params including
			patronid : the patron's id
			pub : true if retrieving only public notes
	/
);

sub fetch_patron_note {
	my( $self, $conn, $authtoken, $args ) = @_;
	my $patronid = $$args{patronid};

	my($reqr, $evt) = $U->checkses($authtoken);
	return $evt if $evt;

	my $patron;
	($patron, $evt) = $U->fetch_user($patronid);
	return $evt if $evt;

	if($$args{pub}) {
		if( $patronid ne $reqr->id ) {
			$evt = $U->check_perms($reqr->id, $patron->home_ou, 'VIEW_USER');
			return $evt if $evt;
		}
		return $U->cstorereq(
			'open-ils.cstore.direct.actor.usr_note.search.atomic', 
			{ usr => $patronid, pub => 't' } );
	}

	$evt = $U->check_perms($reqr->id, $patron->home_ou, 'VIEW_USER');
	return $evt if $evt;

	return $U->cstorereq(
		'open-ils.cstore.direct.actor.usr_note.search.atomic', { usr => $patronid } );
}

__PACKAGE__->register_method (
	method		=> 'create_user_note',
	api_name		=> 'open-ils.actor.note.create',
	signature	=> q/
		Creates a new note for the given user
		@param authtoken The login session key
		@param note The note object
	/
);
sub create_user_note {
	my( $self, $conn, $authtoken, $note ) = @_;
	my $e = new_editor(xact=>1, authtoken=>$authtoken);
	return $e->die_event unless $e->checkauth;

	my $user = $e->retrieve_actor_user($note->usr)
		or return $e->die_event;

	return $e->die_event unless 
		$e->allowed('UPDATE_USER',$user->home_ou);

	$note->creator($e->requestor->id);
	$e->create_actor_usr_note($note) or return $e->die_event;
	$e->commit;
	return $note->id;
}


__PACKAGE__->register_method (
	method		=> 'delete_user_note',
	api_name		=> 'open-ils.actor.note.delete',
	signature	=> q/
		Deletes a note for the given user
		@param authtoken The login session key
		@param noteid The note id
	/
);
sub delete_user_note {
	my( $self, $conn, $authtoken, $noteid ) = @_;

	my $e = new_editor(xact=>1, authtoken=>$authtoken);
	return $e->die_event unless $e->checkauth;
	my $note = $e->retrieve_actor_usr_note($noteid)
		or return $e->die_event;
	my $user = $e->retrieve_actor_user($note->usr)
		or return $e->die_event;
	return $e->die_event unless 
		$e->allowed('UPDATE_USER', $user->home_ou);
	
	$e->delete_actor_usr_note($note) or return $e->die_event;
	$e->commit;
	return 1;
}


__PACKAGE__->register_method (
	method		=> 'update_user_note',
	api_name		=> 'open-ils.actor.note.update',
	signature	=> q/
		@param authtoken The login session key
		@param note The note
	/
);

sub update_user_note {
	my( $self, $conn, $auth, $note ) = @_;
	my $e = new_editor(authtoken=>$auth, xact=>1);
	return $e->event unless $e->checkauth;
	my $patron = $e->retrieve_actor_user($note->usr)
		or return $e->event;
	return $e->event unless 
		$e->allowed('UPDATE_USER', $patron->home_ou);
	$e->update_actor_user_note($note)
		or return $e->event;
	$e->commit;
	return 1;
}




__PACKAGE__->register_method (
	method		=> 'create_closed_date',
	api_name	=> 'open-ils.actor.org_unit.closed_date.create',
	signature	=> q/
		Creates a new closing entry for the given org_unit
		@param authtoken The login session key
		@param note The closed_date object
	/
);
sub create_closed_date {
	my( $self, $conn, $authtoken, $cd ) = @_;

	my( $user, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;

	$evt = $U->check_perms($user->id, $cd->org_unit, 'CREATE_CLOSEING');
	return $evt if $evt;

	$logger->activity("user ".$user->id." creating library closing for ".$cd->org_unit);

	my $id = $U->storagereq(
		'open-ils.storage.direct.actor.org_unit.closed_date.create', $cd );
	return $U->DB_UPDATE_FAILED($cd) unless $id;
	return $id;
}


__PACKAGE__->register_method (
	method		=> 'delete_closed_date',
	api_name	=> 'open-ils.actor.org_unit.closed_date.delete',
	signature	=> q/
		Deletes a closing entry for the given org_unit
		@param authtoken The login session key
		@param noteid The close_date id
	/
);
sub delete_closed_date {
	my( $self, $conn, $authtoken, $cd ) = @_;

	my( $user, $evt ) = $U->checkses($authtoken);
	return $evt if $evt;

	my $cd_obj;
	($cd_obj, $evt) = fetch_closed_date($cd);
	return $evt if $evt;

	$evt = $U->check_perms($user->id, $cd->org_unit, 'DELETE_CLOSEING');
	return $evt if $evt;

	$logger->activity("user ".$user->id." deleting library closing for ".$cd->org_unit);

	my $stat = $U->storagereq(
		'open-ils.storage.direct.actor.org_unit.closed_date.delete', $cd );
	return $U->DB_UPDATE_FAILED($cd) unless $stat;
	return $stat;
}


__PACKAGE__->register_method(
	method => 'usrname_exists',
	api_name	=> 'open-ils.actor.username.exists',
	signature => q/
		Returns 1 if the requested username exists, returns 0 otherwise
	/
);

sub usrname_exists {
	my( $self, $conn, $auth, $usrname ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	my $a = $e->search_actor_user({usrname => $usrname, deleted=>'f'}, {idlist=>1});
	return $$a[0] if $a and @$a;
	return undef;
}

__PACKAGE__->register_method(
	method => 'barcode_exists',
	api_name	=> 'open-ils.actor.barcode.exists',
    authoritative => 1,
	signature => q/
		Returns 1 if the requested barcode exists, returns 0 otherwise
	/
);

sub barcode_exists {
	my( $self, $conn, $auth, $barcode ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	my $card = $e->search_actor_card({barcode => $barcode});
	if (@$card) {
		return 1;
	} else {
		return 0;
	}
	#return undef unless @$card;
	#return $card->[0]->usr;
}


__PACKAGE__->register_method(
	method => 'retrieve_net_levels',
	api_name	=> 'open-ils.actor.net_access_level.retrieve.all',
);

sub retrieve_net_levels {
	my( $self, $conn, $auth ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
	return $e->retrieve_all_config_net_access_level();
}


__PACKAGE__->register_method(
	method => 'fetch_org_by_shortname',
	api_name => 'open-ils.actor.org_unit.retrieve_by_shorname',
);
sub fetch_org_by_shortname {
	my( $self, $conn, $sname ) = @_;
	my $e = new_editor();
	my $org = $e->search_actor_org_unit({ shortname => uc($sname)})->[0];
	return $e->event unless $org;
	return $org;
}


__PACKAGE__->register_method(
	method => 'session_home_lib',
	api_name => 'open-ils.actor.session.home_lib',
);

sub session_home_lib {
	my( $self, $conn, $auth ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return undef unless $e->checkauth;
	my $org = $e->retrieve_actor_org_unit($e->requestor->home_ou);
	return $org->shortname;
}

__PACKAGE__->register_method(
	method => 'session_safe_token',
	api_name => 'open-ils.actor.session.safe_token',
	signature => q/
		Returns a hashed session ID that is safe for export to the world.
		This safe token will expire after 1 hour of non-use.
		@param auth Active authentication token
	/
);

sub session_safe_token {
	my( $self, $conn, $auth ) = @_;
	my $e = new_editor(authtoken=>$auth);
	return undef unless $e->checkauth;

	my $safe_token = md5_hex($auth);

	$cache ||= OpenSRF::Utils::Cache->new("global", 0);

	# Add more like the following if needed...
	$cache->put_cache(
		"safe-token-home_lib-shortname-$safe_token",
		$e->retrieve_actor_org_unit(
			$e->requestor->home_ou
		)->shortname,
		60 * 60
	);

	return $safe_token;
}


__PACKAGE__->register_method(
	method => 'safe_token_home_lib',
	api_name => 'open-ils.actor.safe_token.home_lib.shortname',
	signature => q/
		Returns the home library shortname from the session
		asscociated with a safe token from generated by
		open-ils.actor.session.safe_token.
		@param safe_token Active safe token
	/
);

sub safe_token_home_lib {
	my( $self, $conn, $safe_token ) = @_;

	$cache ||= OpenSRF::Utils::Cache->new("global", 0);
	return $cache->get_cache( 'safe-token-home_lib-shortname-'. $safe_token );
}



__PACKAGE__->register_method(
	method => 'slim_tree',
	api_name	=> "open-ils.actor.org_tree.slim_hash.retrieve",
);
sub slim_tree {
	my $tree = new_editor()->search_actor_org_unit( 
		[
			{"parent_ou" => undef },
			{
				flesh				=> -1,
				flesh_fields	=> { aou =>  ['children'] },
				order_by			=> { aou => 'name'},
				select			=> { aou => ["id","shortname", "name"]},
			}
		]
	)->[0];

	return trim_tree($tree);
}


sub trim_tree {
	my $tree = shift;
	return undef unless $tree;
	my $htree = {
		code => $tree->shortname,
		name => $tree->name,
	};
	if( $tree->children and @{$tree->children} ) {
		$htree->{children} = [];
		for my $c (@{$tree->children}) {
			push( @{$htree->{children}}, trim_tree($c) );
		}
	}

	return $htree;
}


__PACKAGE__->register_method(
	method	=> "update_penalties",
	api_name	=> "open-ils.actor.user.penalties.update");

sub update_penalties {
	my($self, $conn, $auth, $user_id) = @_;
	my $e = new_editor(authtoken=>$auth, xact => 1);
	return $e->die_event unless $e->checkauth;
    my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);
    my $evt = OpenILS::Utils::Penalty->calculate_penalties($e, $user_id, $e->requestor->ws_ou);
    return $evt if $evt;
    $e->commit;
    return 1;
}


__PACKAGE__->register_method(
	method	=> "apply_penalty",
	api_name	=> "open-ils.actor.user.penalty.apply");

sub apply_penalty {
	my($self, $conn, $auth, $penalty) = @_;
	my $e = new_editor(authtoken=>$auth, xact => 1);
	return $e->die_event unless $e->checkauth;
    my $user = $e->retrieve_actor_user($penalty->usr) or return $e->die_event;
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

    # is it already applied?
    return 1 if $e->search_actor_user_standing_penalty(
        {   usr => $penalty->usr, 
            standing_penalty => $penalty->standing_penalty,
            org_unit => $penalty->org_unit
        })->[0];

    $e->create_actor_user_standing_penalty($penalty) or return $e->die_event;
    $e->commit;
    return $penalty->id;
}

__PACKAGE__->register_method(
	method	=> "remove_penalty",
	api_name	=> "open-ils.actor.user.penalty.remove");

sub remove_penalty {
	my($self, $conn, $auth, $penalty) = @_;
	my $e = new_editor(authtoken=>$auth, xact => 1);
	return $e->die_event unless $e->checkauth;
    my $user = $e->retrieve_actor_user($penalty->usr) or return $e->die_event;
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

    $e->delete_actor_user_standing_penalty($penalty) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method	=> "update_penalty_note",
	api_name	=> "open-ils.actor.user.penalty.note.update");

sub update_penalty_note {
	my($self, $conn, $auth, $penalty_ids, $note) = @_;
	my $e = new_editor(authtoken=>$auth, xact => 1);
	return $e->die_event unless $e->checkauth;
    for my $penalty_id (@$penalty_ids) {
        my $penalty = $e->search_actor_user_standing_penalty( { id => $penalty_id } )->[0];
        if (! $penalty ) { return $e->die_event; }
        my $user = $e->retrieve_actor_user($penalty->usr) or return $e->die_event;
        return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

        $penalty->note( $note ); $penalty->ischanged( 1 );

        $e->update_actor_user_standing_penalty($penalty) or return $e->die_event;
    }
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
	method => "ranged_penalty_thresholds",
	api_name => "open-ils.actor.grp_penalty_threshold.ranged.retrieve",
    stream => 1
);

sub ranged_penalty_thresholds {
	my($self, $conn, $auth, $context_org) = @_;
	my $e = new_editor(authtoken=>$auth);
	return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_GROUP_PENALTY_THRESHOLD', $context_org);
    my $list = $e->search_permission_grp_penalty_threshold([
        {org_unit => $U->get_org_ancestors($context_org)},
        {order_by => {pgpt => 'id'}}
    ]);
    $conn->respond($_) for @$list;
    return undef;
}



__PACKAGE__->register_method(
	method	=> "user_retrieve_fleshed_by_id",
    authoritative => 1,
	api_name	=> "open-ils.actor.user.fleshed.retrieve",);

sub user_retrieve_fleshed_by_id {
	my( $self, $client, $auth, $user_id, $fields ) = @_;
	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;

	if( $e->requestor->id != $user_id ) {
		return $e->event unless $e->allowed('VIEW_USER');
	}

	$fields ||= [
		"cards",
		"card",
		"standing_penalties",
		"addresses",
		"billing_address",
		"mailing_address",
		"stat_cat_entries" ];
	return new_flesh_user($user_id, $fields, $e);
}


sub new_flesh_user {

	my $id = shift;
	my $fields = shift || [];
	my $e = shift;

    my $fetch_penalties = 0;
    if(grep {$_ eq 'standing_penalties'} @$fields) {
        $fields = [grep {$_ ne 'standing_penalties'} @$fields];
        $fetch_penalties = 1;
    }

	my $user = $e->retrieve_actor_user(
   	[
      	$id,
      	{
         	"flesh" 			=> 1,
         	"flesh_fields" =>  { "au" => $fields }
      	}
   	]
	) or return $e->event;


	if( grep { $_ eq 'addresses' } @$fields ) {

		$user->addresses([]) unless @{$user->addresses};
        # don't expose "replaced" addresses by default
        $user->addresses([grep {$_->id >= 0} @{$user->addresses}]);
	
		if( ref $user->billing_address ) {
			unless( grep { $user->billing_address->id == $_->id } @{$user->addresses} ) {
				push( @{$user->addresses}, $user->billing_address );
			}
		}
	
		if( ref $user->mailing_address ) {
			unless( grep { $user->mailing_address->id == $_->id } @{$user->addresses} ) {
				push( @{$user->addresses}, $user->mailing_address );
			}
		}
	}

    if($fetch_penalties) {
        # grab the user penalties ranged for this location
        $user->standing_penalties(
            $e->search_actor_user_standing_penalty([
                {   usr => $id, 
                    org_unit => $U->get_org_ancestors($e->requestor->ws_ou)
                },
                {   flesh => 1,
                    flesh_fields => {ausp => ['standing_penalty']}
                }
            ])
        );
    }

	$e->rollback;
	$user->clear_passwd();
	return $user;
}




__PACKAGE__->register_method(
	method	=> "user_retrieve_parts",
	api_name	=> "open-ils.actor.user.retrieve.parts",);

sub user_retrieve_parts {
	my( $self, $client, $auth, $user_id, $fields ) = @_;
	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;
	if( $e->requestor->id != $user_id ) {
		return $e->event unless $e->allowed('VIEW_USER');
	}
	my @resp;
	my $user = $e->retrieve_actor_user($user_id) or return $e->event;
	push(@resp, $user->$_()) for(@$fields);
	return \@resp;
}



__PACKAGE__->register_method(
    method => 'user_opt_in_enabled',
    api_name => 'open-ils.actor.user.org_unit_opt_in.enabled',
    signature => q/
        @return 1 if user opt-in is globally enabled, 0 otherwise.
    /);

sub user_opt_in_enabled {
    my($self, $conn) = @_;
    my $sc = OpenSRF::Utils::SettingsClient->new;
    return 1 if lc($sc->config_value(share => user => 'opt_in')) eq 'true'; 
    return 0;
}
    

__PACKAGE__->register_method(
    method => 'user_opt_in_at_org',
    api_name => 'open-ils.actor.user.org_unit_opt_in.check',
    signature => q/
        @param $auth The auth token
        @param user_id The ID of the user to test
        @return 1 if the user has opted in at the specified org,
            event on error, and 0 otherwise. /);
sub user_opt_in_at_org {
    my($self, $conn, $auth, $user_id) = @_;

    # see if we even need to enforce the opt-in value
    return 1 unless user_opt_in_enabled($self);

	my $e = new_editor(authtoken => $auth);
	return $e->event unless $e->checkauth;
    my $org_id = $e->requestor->ws_ou;

    my $user = $e->retrieve_actor_user($user_id) or return $e->event;
	return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);

    # user is automatically opted-in at the home org
    return 1 if $user->home_ou eq $org_id;

    my $vals = $e->search_actor_usr_org_unit_opt_in(
        {org_unit=>$org_id, usr=>$user_id},{idlist=>1});

    return 1 if @$vals;
    return 0;
}

__PACKAGE__->register_method(
    method => 'create_user_opt_in_at_org',
    api_name => 'open-ils.actor.user.org_unit_opt_in.create',
    signature => q/
        @param $auth The auth token
        @param user_id The ID of the user to test
        @return The ID of the newly created object, event on error./);

sub create_user_opt_in_at_org {
    my($self, $conn, $auth, $user_id) = @_;

	my $e = new_editor(authtoken => $auth, xact=>1);
	return $e->die_event unless $e->checkauth;
    my $org_id = $e->requestor->ws_ou;

    my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;
	return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);

    my $opt_in = Fieldmapper::actor::usr_org_unit_opt_in->new;

    $opt_in->org_unit($org_id);
    $opt_in->usr($user_id);
    $opt_in->staff($e->requestor->id);
    $opt_in->opt_in_ts('now');
    $opt_in->opt_in_ws($e->requestor->wsid);

    $opt_in = $e->create_actor_usr_org_unit_opt_in($opt_in)
        or return $e->die_event;

    $e->commit;

    return $opt_in->id;
}


__PACKAGE__->register_method (
	method		=> 'retrieve_org_hours',
	api_name	=> 'open-ils.actor.org_unit.hours_of_operation.retrieve',
	signature	=> q/
        Returns the hours of operation for a specified org unit
		@param authtoken The login session key
		@param org_id The org_unit ID
	/
);

sub retrieve_org_hours {
    my($self, $conn, $auth, $org_id) = @_;
    my $e = new_editor(authtoken => $auth);
	return $e->die_event unless $e->checkauth;
    $org_id ||= $e->requestor->ws_ou;
    return $e->retrieve_actor_org_unit_hours_of_operation($org_id);
}


__PACKAGE__->register_method (
	method		=> 'verify_user_password',
	api_name	=> 'open-ils.actor.verify_user_password',
	signature	=> q/
        Given a barcode or username and the MD5 encoded password, 
        returns 1 if the password is correct.  Returns 0 otherwise.
	/
);

sub verify_user_password {
    my($self, $conn, $auth, $barcode, $username, $password) = @_;
    my $e = new_editor(authtoken => $auth);
	return $e->die_event unless $e->checkauth;
    my $user;
    my $user_by_barcode;
    my $user_by_username;
    if($barcode) {
        my $card = $e->search_actor_card([
            {barcode => $barcode},
            {flesh => 1, flesh_fields => {ac => ['usr']}}])->[0] or return 0;
        $user_by_barcode = $card->usr;
        $user = $user_by_barcode;
    }
    if ($username) {
        $user_by_username = $e->search_actor_user({usrname => $username})->[0] or return 0;
        $user = $user_by_username;
    }
    return 0 if (!$user);
    return 0 if ($user_by_username && $user_by_barcode && $user_by_username->id != $user_by_barcode->id); 
    return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);
    return 1 if $user->passwd eq $password;
    return 0;
}

__PACKAGE__->register_method (
	method		=> 'retrieve_usr_id_via_barcode_or_usrname',
	api_name	=> "open-ils.actor.user.retrieve_id_by_barcode_or_username",
	signature	=> q/
        Given a barcode or username returns the id for the user or
        a failure event.
	/
);

sub retrieve_usr_id_via_barcode_or_usrname {
    my($self, $conn, $auth, $barcode, $username) = @_;
    my $e = new_editor(authtoken => $auth);
	return $e->die_event unless $e->checkauth;
    my $user;
    my $user_by_barcode;
    my $user_by_username;
    if($barcode) {
        my $card = $e->search_actor_card([
            {barcode => $barcode},
            {flesh => 1, flesh_fields => {ac => ['usr']}}])->[0] or return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' );
        $user_by_barcode = $card->usr;
        $user = $user_by_barcode;
    }
    if ($username) {
        $user_by_username = $e->search_actor_user({usrname => $username})->[0] or return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' );

        $user = $user_by_username;
    }
	return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' ) if (!$user);
	return OpenILS::Event->new( 'ACTOR_USER_NOT_FOUND' ) if ($user_by_username && $user_by_barcode && $user_by_username->id != $user_by_barcode->id); 
    return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);
    return $user->id;
}


__PACKAGE__->register_method (
	method		=> 'merge_users',
	api_name	=> 'open-ils.actor.user.merge',
	signature	=> {
        desc => q/
            Given a list of source users and destination user, transfer all data from the source
            to the dest user and delete the source user.  All user related data is 
            transferred, including circulations, holds, bookbags, etc.
        /
    }
);

sub merge_users {
    my($self, $conn, $auth, $master_id, $user_ids, $options) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
	return $e->die_event unless $e->checkauth;

    my $master_user = $e->retrieve_actor_user($master_id) or return $e->die_event;
    my $del_addrs = ($U->ou_ancestor_setting_value(
        $master_user->home_ou, 'circ.user_merge.delete_addresses', $e)) ? 't' : 'f';
    my $del_cards = ($U->ou_ancestor_setting_value(
        $master_user->home_ou, 'circ.user_merge.delete_cards', $e)) ? 't' : 'f';
    my $deactivate_cards = ($U->ou_ancestor_setting_value(
        $master_user->home_ou, 'circ.user_merge.deactivate_cards', $e)) ? 't' : 'f';

    for my $src_id (@$user_ids) {
        my $src_user = $e->retrieve_actor_user($src_id) or return $e->die_event;

        return $e->die_event unless $e->allowed('MERGE_USERS', $src_user->home_ou);
        if($src_user->home_ou ne $master_user->home_ou) {
            return $e->die_event unless $e->allowed('MERGE_USERS', $master_user->home_ou);
        }

        return $e->die_event unless 
            $e->json_query({from => [
                'actor.usr_merge', 
                $src_id, 
                $master_id,
                $del_addrs,
                $del_cards,
                $deactivate_cards
            ]});
    }

    $e->commit;
    return 1;
}


__PACKAGE__->register_method (
	method		=> 'approve_user_address',
	api_name	=> 'open-ils.actor.user.pending_address.approve',
	signature	=> {
        desc => q/
        /
    }
);

sub approve_user_address {
    my($self, $conn, $auth, $addr) = @_;
    my $e = new_editor(xact => 1, authtoken => $auth);
	return $e->die_event unless $e->checkauth;
    if(ref $addr) {
        # if the caller passes an address object, assume they want to 
        # update it first before approving it
        $e->update_actor_user_address($addr) or return $e->die_event;
    } else {
        $addr = $e->retrieve_actor_user_address($addr) or return $e->die_event;
    }
    my $user = $e->retrieve_actor_user($addr->usr);
    return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);
    my $result = $e->json_query({from => ['actor.approve_pending_address', $addr->id]})->[0]
        or return $e->die_event;
    $e->commit;
    return [values %$result]->[0]; 
}


__PACKAGE__->register_method (
	method		=> 'retrieve_friends',
	api_name	=> 'open-ils.actor.friends.retrieve',
	signature	=> {
        desc => q/
            returns { confirmed: [], pending_out: [], pending_in: []}
            pending_out are users I'm requesting friendship with
            pending_in are users requesting friendship with me
        /
    }
);

sub retrieve_friends {
    my($self, $conn, $auth, $user_id, $options) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    $user_id ||= $e->requestor->id;

    if($user_id != $e->requestor->id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->event;
        return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);
    }

    return OpenILS::Application::Actor::Friends->retrieve_friends(  
        $e, $user_id, $options);
}



__PACKAGE__->register_method (
	method		=> 'apply_friend_perms',
	api_name	=> 'open-ils.actor.friends.perms.apply',
	signature	=> {
        desc => q/
        /
    }
);
sub apply_friend_perms {
    my($self, $conn, $auth, $user_id, $delegate_id, @perms) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->event unless $e->checkauth;

    if($user_id != $e->requestor->id) {
        my $user = $e->retrieve_actor_user($user_id) or return $e->die_event;
        return $e->die_event unless $e->allowed('VIEW_USER', $user->home_ou);
    }

    for my $perm (@perms) {
        my $evt = 
            OpenILS::Application::Actor::Friends->apply_friend_perm(
                $e, $user_id, $delegate_id, $perm);
        return $evt if $evt;
    }

    $e->commit;
    return 1;
}


__PACKAGE__->register_method (
	method		=> 'update_user_pending_address',
	api_name	=> 'open-ils.actor.user.address.pending.cud'
);

sub update_user_pending_address {
    my($self, $conn, $auth, $addr) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->event unless $e->checkauth;

    if($addr->usr != $e->requestor->id) {
        my $user = $e->retrieve_actor_user($addr->usr) or return $e->die_event;
        return $e->die_event unless $e->allowed('UPDATE_USER', $user->home_ou);
    }

    if($addr->isnew) {
        $e->create_actor_user_address($addr) or return $e->die_event;
    } elsif($addr->isdeleted) {
        $e->delete_actor_user_address($addr) or return $e->die_event;
    } else {
        $e->update_actor_user_address($addr) or return $e->die_event;
    }

    $e->commit;
    return $addr->id;
}


__PACKAGE__->register_method (
	method		=> 'user_events',
	api_name    => 'open-ils.actor.user.events.circ',
    stream      => 1,
);
__PACKAGE__->register_method (
	method		=> 'user_events',
	api_name    => 'open-ils.actor.user.events.ahr',
    stream      => 1,
);

sub user_events {
    my($self, $conn, $auth, $user_id, $filters) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    (my $obj_type = $self->api_name) =~ s/.*\.([a-z]+)$/$1/;
    my $user_field = 'usr';

    $filters ||= {};
    $filters->{target} = { 
        select => { $obj_type => ['id'] },
        from => $obj_type,
        where => {usr => $user_id}
    };

    my $user = $e->retrieve_actor_user($user_id) or return $e->event;
    if($e->requestor->id != $user_id) {
        return $e->event unless $e->allowed('VIEW_USER', $user->home_ou);
    }

    my $ses = OpenSRF::AppSession->create('open-ils.trigger');
    my $req = $ses->request('open-ils.trigger.events_by_target', $obj_type, $filters);
    while(my $resp = $req->recv) {
        my $val = $resp->content;
        $conn->respond($val) if $val;
    }

    return undef;
}


1;

