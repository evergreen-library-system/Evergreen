package OpenILS::Application::Circ::StatCat;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenSRF::EX qw/:try/;
use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";



__PACKAGE__->register_method(
	method	=> "retrieve_stat_cats",
	api_name	=> "open-ils.circ.stat_cat.actor.retrieve.all");

__PACKAGE__->register_method(
	method	=> "retrieve_stat_cats",
	api_name	=> "open-ils.circ.stat_cat.asset.retrieve.all");

# retrieves all of the stat cats for a given org unit
# if no orgid, user_session->home_ou is used

sub retrieve_stat_cats {
	my( $self, $client, $user_session, $orgid ) = @_;

	my $user_obj = $apputils->check_user_session($user_session); 
	if(!$orgid) { $orgid = $user_obj->home_ou; }

	my $method = "open-ils.storage.ranged.fleshed.actor.stat_cat.all.atomic"; 
	if( $self->api_name =~ /asset/ ) {
		$method = "open-ils.storage.ranged.fleshed.asset.stat_cat.all.atomic"; 
	}

	return $apputils->simple_scalar_request(
				"open-ils.storage", $method, $orgid );
}



__PACKAGE__->register_method(
	method	=> "retrieve_ranged_stat_cats",
	api_name	=> "open-ils.circ.stat_cat.asset.multirange.retrieve");

sub retrieve_ranged_stat_cats {
	my( $self, $client, $user_session, $orglist ) = @_;

	my $user_obj = $apputils->check_user_session($user_session); 
	if(!$orglist) { $orglist = [ $user_obj->home_ou ]; }

	# uniquify, yay!
	my %hash = map { ($_ => 1) } @$orglist;
	$orglist = [ keys %hash ];

	warn "range: @$orglist\n";

	my	$method = "open-ils.storage.multiranged.fleshed.asset.stat_cat.all.atomic";
	return $apputils->simple_scalar_request(
				"open-ils.storage", $method, $orglist );
}




__PACKAGE__->register_method(
	method	=> "stat_cat_create",
	api_name	=> "open-ils.circ.stat_cat.asset.create");

__PACKAGE__->register_method(
	method	=> "stat_cat_create",
	api_name	=> "open-ils.circ.stat_cat.actor.create");

sub stat_cat_create {
	my( $self, $client, $user_session, $stat_cat ) = @_;

	if(!$stat_cat) {
		throw OpenSRF::EX::ERROR
			("stat_cat.*.create requires a stat_cat object");
	}

	my $user_obj = $apputils->check_user_session($user_session); 
	my $orgid = $user_obj->home_ou();

	my $method = "open-ils.storage.direct.actor.stat_cat.create";
	my $entry_create = "open-ils.storage.direct.actor.stat_cat_entry.create";

	if($self->api_name =~ /asset/) {
		$method = "open-ils.storage.direct.asset.stat_cat.create";
		$entry_create = "open-ils.storage.direct.asset.stat_cat_entry.create";
	}

	my $session = $apputils->start_db_session();
	my $newid = _create_stat_cat($session, $stat_cat, $method);

	for my $entry (@{$stat_cat->entries}) {
		$entry->stat_cat($newid);
		_create_stat_entry($session, $entry, $entry_create);
	}

	$apputils->commit_db_session($session);

	warn "Stat cat creation successful with id $newid\n";

	if( $self->api_name =~ /asset/ ) {
		return _flesh_asset_cat($newid, $orgid);
	} else {
		return _flesh_user_cat($newid, $orgid);
	}

}


sub _flesh_user_cat {
	my $id = shift;
	my $orgid = shift;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $cat = $session->request(
		"open-ils.storage.direct.actor.stat_cat.retrieve",
		$id )->gather(1);

	$cat->entries( 
		$session->request(
			"open-ils.storage.ranged.actor.stat_cat_entry.search.stat_cat.atomic",
			$orgid, $id )->gather(1) );

	return $cat;
}


sub _flesh_asset_cat {
	my $id = shift;
	my $orgid = shift;

	my $session = OpenSRF::AppSession->create("open-ils.storage");
	my $cat = $session->request(
		"open-ils.storage.direct.asset.stat_cat.retrieve",
		$id )->gather(1);

	$cat->entries( 
		$session->request(
			"open-ils.storage.ranged.asset.stat_cat_entry.search.stat_cat.atomic",
			$orgid,  $id )->gather(1) );

	return $cat;

}


sub _create_stat_cat {
	my( $session, $stat_cat, $method) = @_;
	warn "Creating new stat cat with name " . $stat_cat->name . "\n";
	$stat_cat->clear_id();
	my $req = $session->request( $method, $stat_cat );
	my $id = $req->gather(1);
	if(!$id) {
		throw OpenSRF::EX::ERROR 
		("Error creating new statistical category"); }

	warn "Stat cat create returned id $id\n";
	return $id;
}


sub _create_stat_entry {
	my( $session, $stat_entry, $method) = @_;
	warn "Creating new stat entry with value " . $stat_entry->value . "\n";
	$stat_entry->clear_id();
	my $req = $session->request($method, $stat_entry);
	my $id = $req->gather(1);
	if(!$id) {
		throw OpenSRF::EX::ERROR 
		("Error creating new stat cat entry"); }

	warn "Stat cat entry create returned id $id\n";
	return $id;
}


__PACKAGE__->register_method(
	method	=> "update_stat_entry",
	api_name	=> "open-ils.circ.stat_cat.actor.entry.update");

__PACKAGE__->register_method(
	method	=> "update_stat_entry",
	api_name	=> "open-ils.circ.stat_cat.asset.entry.update");

sub update_stat_entry {
	my( $self, $client, $user_session, $entry ) = @_;

	my $user_obj = $apputils->check_user_session($user_session); 

	my $method = "open-ils.storage.direct.actor.stat_cat_entry.update";
	if($self->api_name =~ /asset/) {
		$method = "open-ils.storage.direct.asset.stat_cat_entry.update";
	}

	my $session = $apputils->start_db_session();
	my $req = $session->request($method, $entry); 
	my $status = $req->gather(1);
	$apputils->commit_db_session($session);
	warn "stat cat entry with value " . $entry->value . " updated with status $status\n";
	return 1;
}



__PACKAGE__->register_method(
	method	=> "create_stat_map",
	api_name	=> "open-ils.circ.stat_cat.actor.user_map.create");

__PACKAGE__->register_method(
	method	=> "create_stat_map",
	api_name	=> "open-ils.circ.stat_cat.asset.copy_map.create");

sub create_stat_map {
	my( $self, $client, $user_session, $map ) = @_;

	my $user_obj = $apputils->check_user_session($user_session); 

	warn "Creating stat_cat_map\n";

	$map->clear_id();

	my $method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.create";
	my $ret = "open-ils.storage.direct.actor.stat_cat_entry_user_map.retrieve";
	if($self->api_name =~ /asset/) {
		$method = "open-ils.storage.direct.asset.stat_cat_entry_copy_map.create";
		$ret = "open-ils.storage.direct.asset.stat_cat_entry_copy_map.retrieve";
	}

	my $session = $apputils->start_db_session();
	my $req = $session->request($method, $map); 
	my $newid = $req->gather(1);
	warn "Created new stat cat map with id $newid\n";
	$apputils->commit_db_session($session);

	return $apputils->simple_scalar_request( "open-ils.storage", $ret, $newid );

}



__PACKAGE__->register_method(
	method	=> "retrieve_maps",
	api_name	=> "open-ils.circ.stat_cat.actor.user_map.retrieve");

__PACKAGE__->register_method(
	method	=> "retrieve_maps",
	api_name	=> "open-ils.circ.stat_cat.asset.copy_map.retrieve");

sub retrieve_maps {
	my( $self, $client, $user_session, $target ) = @_;

	my $user_obj = $apputils->check_user_session($user_session); 

	my	$method = "open-ils.storage.direct.asset.stat_cat_entry_copy_map.search.owning_copy";
	if($self->api_name =~ /actor/ ) {
		if(!$target) { $target = $user_obj->id; }
		$method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.search.target_usr";
	}

	return $apputils->simple_scalar_request("open-ils.storage", $method, $target);
}











1;
