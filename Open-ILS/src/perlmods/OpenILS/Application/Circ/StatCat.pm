package OpenILS::Application::Circ::StatCat;
use base qw/OpenSRF::Application/;
use strict; use warnings;

use OpenSRF::EX qw/:try/;
use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";



__PACKAGE__->register_method(
	method	=> "retrieve_stat_cats",
	api_name	=> "open-ils.circ.stat_cat.user.retrieve.all");

__PACKAGE__->register_method(
	method	=> "retrieve_stat_cats",
	api_name	=> "open-ils.circ.stat_cat.copy.retrieve.all");

# retrieves all of the stat cats for a given org unit
# if no orgid, user_session->home_ou is used

sub retrieve_stat_cats {
	my( $self, $client, $user_session, $orgid ) = @_;

	my $user_obj = $apputils->check_user_session($user_session); 
	if(!$orgid) { $orgid = $user_obj->home_ou; }

	my $method = "open-ils.storage.ranged.fleshed.actor.stat_cat.all.atomic"; 
	if( $self->api_name =~ /copy/ ) {
		$method = "open-ils.storage.ranged.fleshed.asset.stat_cat.all.atomic"; 
	}

	return $apputils->simple_scalar_request(
				"open-ils.storage", $method, $orgid );
}




__PACKAGE__->register_method(
	method	=> "stat_cat_create",
	api_name	=> "open-ils.circ.stat_cat.copy.create");

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
	warn "creating new stat_cat with name " . $stat_cat->name() . "\n";


	my $method = "open-ils.storage.direct.actor.stat_cat.create";
	my $entry_create = "open-ils.storage.direct.actor.stat_cat_entry.create";

	if($self->api_name =~ /copy/) {
		$method = "open-ils.storage.direct.asset.stat_cat.create";
		$entry_create = "open-ils.storage.direct.asset.stat_cat_entry.create";
	}

	my $session = $apputils->start_db_session();
	my $newid = _create_stat_cat($session, $stat_cat, $method);

	for my $entry ($stat_cat->entries) {
		_create_stat_entry($session, $entry, $entry_create);
	}

	$apputils->commit_db_session($session);

	warn "Stat cat creation successful with id $newid\n";

	if( $self->api_name =~ /copy/ ) {
		return _flesh_copy_cat($newid, $orgid);
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


sub _flesh_copy_cat {
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
	$stat_cat->clear_id();
	my $req = $session->request( $method, $stat_cat );
	my $id = $req->gather(1);
	if(!$id) {
		throw OpenSRF::EX::ERROR 
			("Error creating new statistical category");
	}
	return $id;
}


sub _create_stat_entry {
	my( $session, $stat_entry, $method) = @_;
}















1;
