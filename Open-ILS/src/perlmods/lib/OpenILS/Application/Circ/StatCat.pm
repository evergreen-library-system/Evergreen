# ---------------------------------------------------------------
# Copyright (C) 2006  Georgia Public Library Service 
# Bill Erickson <billserickson@gmail.com>

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# ---------------------------------------------------------------

package OpenILS::Application::Circ::StatCat;
use base qw/OpenILS::Application/;
use strict; use warnings;

use OpenSRF::Utils::Logger qw($logger);
use OpenSRF::EX qw/:try/;
use OpenILS::Application::AppUtils;
my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;



__PACKAGE__->register_method(
    method  => "retrieve_stat_cat_list",
    argc    => 1,
    api_name    => "open-ils.circ.stat_cat.actor.retrieve.batch");

__PACKAGE__->register_method(
    method  => "retrieve_stat_cat_list",
    argc    => 1,
    api_name    => "open-ils.circ.stat_cat.asset.retrieve.batch");

# retrieves all of the stat cats for a given org unit
# if no orgid, user_session->home_ou is used

sub retrieve_stat_cat_list {
    my( $self, $client, $user_session, @sc ) = @_;

    if (ref($sc[0])) {
        @sc = @{$sc[0]};
    }

    my $method = "open-ils.storage.fleshed.actor.stat_cat.retrieve.batch.atomic"; 
    if( $self->api_name =~ /asset/ ) {
        $method = "open-ils.storage.fleshed.asset.stat_cat.retrieve.batch.atomic"; 
    }

    my($user_obj, $evt) = $apputils->checkses($user_session); 
    return $evt if $evt;

    my $cats = $apputils->simple_scalar_request(
                "open-ils.storage", $method, @sc);

    return [ sort { $a->name cmp $b->name } @$cats ];
}

__PACKAGE__->register_method(
    method  => "retrieve_stat_cats",
    api_name    => "open-ils.circ.stat_cat.actor.retrieve.all");

__PACKAGE__->register_method(
    method  => "retrieve_stat_cats",
    api_name    => "open-ils.circ.stat_cat.asset.retrieve.all");

# retrieves all of the stat cats for a given org unit
# if no orgid, user_session->home_ou is used

sub retrieve_stat_cats {
    my( $self, $client, $user_session, $orgid ) = @_;

    my $method = "open-ils.storage.ranged.fleshed.actor.stat_cat.all.atomic"; 
    if( $self->api_name =~ /asset/ ) {
        $method = "open-ils.storage.ranged.fleshed.asset.stat_cat.all.atomic"; 
    }

    my($user_obj, $evt) = $apputils->checkses($user_session); 
    return $evt if $evt;

    if(!$orgid) { $orgid = $user_obj->home_ou; }
    my $cats = $apputils->simple_scalar_request(
                "open-ils.storage", $method, $orgid );

    return [ sort { $a->name cmp $b->name } @$cats ];
}


__PACKAGE__->register_method(
    method  => "retrieve_ranged_intersect_stat_cats",
    api_name    => "open-ils.circ.stat_cat.asset.multirange.intersect.retrieve");

sub retrieve_ranged_intersect_stat_cats {
    my( $self, $client, $user_session, $orglist ) = @_;

    my($user_obj, $evt) = $apputils->checkses($user_session); 
    return $evt if $evt;

    if(!$orglist) { $orglist = [ $user_obj->home_ou ]; }

    # uniquify, yay!
    my %hash = map { ($_ => 1) } @$orglist;
    $orglist = [ keys %hash ];

    $logger->debug("range: @$orglist");

    my  $method = "open-ils.storage.multiranged.intersect.fleshed.asset.stat_cat.all.atomic";
    return $apputils->simple_scalar_request(
                "open-ils.storage", $method, $orglist );
}


__PACKAGE__->register_method(
    method  => "retrieve_ranged_union_stat_cats",
    api_name    => "open-ils.circ.stat_cat.asset.multirange.union.retrieve");

sub retrieve_ranged_union_stat_cats {
    my( $self, $client, $user_session, $orglist ) = @_;

    my  $method = "open-ils.storage.multiranged.union.fleshed.asset.stat_cat.all.atomic";
    use Data::Dumper;
    $logger->debug("Retrieving stat_cats with method $method and orgs " . Dumper($orglist));

    my($user_obj, $evt) = $apputils->checkses($user_session); 
    return $evt if $evt;

    if(!$orglist) { $orglist = [ $user_obj->home_ou ]; }

    # uniquify, yay!
    my %hash = map { ($_ => 1) } @$orglist;
    $orglist = [ keys %hash ];

    $logger->debug("range: @$orglist\n");

    return $apputils->simple_scalar_request(
                "open-ils.storage", $method, $orglist );
}



__PACKAGE__->register_method(
    method  => "stat_cat_create",
    api_name    => "open-ils.circ.stat_cat.asset.create");

__PACKAGE__->register_method(
    method  => "stat_cat_create",
    api_name    => "open-ils.circ.stat_cat.actor.create");

sub stat_cat_create {
    my( $self, $client, $user_session, $stat_cat ) = @_;

    my $method = "open-ils.storage.direct.actor.stat_cat.create";
    my $entry_create = "open-ils.storage.direct.actor.stat_cat_entry.create";
    my $default_entry_create = "open-ils.storage.direct.actor.stat_cat_entry_default.create";
    my $perm = 'CREATE_PATRON_STAT_CAT';
    my $eperm = 'CREATE_PATRON_STAT_CAT_ENTRY';
    my $edperm = 'CREATE_PATRON_STAT_CAT_ENTRY_DEFAULT';

    if($self->api_name =~ /asset/) {
        $method = "open-ils.storage.direct.asset.stat_cat.create";
        $entry_create = "open-ils.storage.direct.asset.stat_cat_entry.create";
        $perm = 'CREATE_COPY_STAT_CAT_ENTRY';
    }

    #my $user_obj = $apputils->check_user_session($user_session); 
    #my $orgid = $user_obj->home_ou();
    my( $user_obj, $evt ) = $apputils->checkses($user_session);
    return $evt if $evt;
    $evt = $apputils->check_perms($user_obj->id, $stat_cat->owner, $perm);
    return $evt if $evt;

    if($stat_cat->entries) {
        $evt = $apputils->check_perms($user_obj->id, $stat_cat->owner, $eperm);
        return $evt if $evt;
    }


    my $session = $apputils->start_db_session();
    $apputils->set_audit_info($session, $user_session, $user_obj->id, $user_obj->wsid);
    my $newid = _create_stat_cat($session, $stat_cat, $method);

    if( ref($stat_cat->entries) ) {
        for my $entry (@{$stat_cat->entries}) {
            $entry->stat_cat($newid);
            my $entry_id = _create_stat_entry($session, $entry, $entry_create);
            if( $self->api_name =~ /actor/ && ref($entry->default_entries) ) {
                $evt = $apputils->check_perms($user_obj->id, $stat_cat->owner, $edperm);
                return $evt if $evt;

                for my $default_entry (@{$entry->default_entries}) {
                    $default_entry->stat_cat_entry($entry_id);
                    _create_stat_entry_default($session, $default_entry, $default_entry_create);
                }
            }
        }
    }

    $apputils->commit_db_session($session);

    $logger->debug("Stat cat creation successful with id $newid");

    my $orgid = $user_obj->home_ou;
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
    $logger->debug("Creating new stat cat with name " . $stat_cat->name);;
    $stat_cat->clear_id();
    my $req = $session->request( $method, $stat_cat );
    my $id = $req->gather(1);
    if(!$id) {
        throw OpenSRF::EX::ERROR 
        ("Error creating new statistical category"); }

    $logger->debug("Stat cat create returned id $id");
    return $id;
}


sub _create_stat_entry {
    my( $session, $stat_entry, $method) = @_;

    $logger->debug("Creating new stat entry with value " . $stat_entry->value);
    $stat_entry->clear_id();

    my $req = $session->request($method, $stat_entry);
    my $id = $req->gather(1);

    $logger->debug("Stat entry " . Dumper($stat_entry));    
    
    if(!$id) {
        throw OpenSRF::EX::ERROR 
        ("Error creating new stat cat entry"); }

    $logger->debug("Stat cat entry create returned id $id");
    return $id;
}


__PACKAGE__->register_method(
    method  => "update_stat_entry",
    api_name    => "open-ils.circ.stat_cat.actor.entry.update");

__PACKAGE__->register_method(
    method  => "update_stat_entry",
    api_name    => "open-ils.circ.stat_cat.asset.entry.update");

sub update_stat_entry {
    my( $self, $client, $user_session, $entry ) = @_;


    my $method = "open-ils.storage.direct.actor.stat_cat_entry.update";
    my $perm = 'UPDATE_PATRON_STAT_CAT_ENTRY';
    if($self->api_name =~ /asset/) {
        $method = "open-ils.storage.direct.asset.stat_cat_entry.update";
        $perm = 'UPDATE_COPY_STAT_CAT_ENTRY';
    }

    my( $user_obj, $evt )  = $apputils->checkses($user_session); 
    return $evt if $evt;
    $evt = $apputils->check_perms( $user_obj->id, $entry->owner, $perm );
    return $evt if $evt;

    my $session = $apputils->start_db_session();
    $apputils->set_audit_info($session, $user_session, $user_obj->id, $user_obj->wsid);
    my $req = $session->request($method, $entry); 
    my $status = $req->gather(1);
    $apputils->commit_db_session($session);
    $logger->debug("stat cat entry with value " . $entry->value . " updated with status $status");
    return 1;
}

sub _update_stat_entry_default {
    my( $session, $default_entry, $method) = @_;

    $logger->debug("Updating new default stat entry for stat_cat " . $default_entry->stat_cat . 
        " for org unit " . $default_entry->owner .
        " with new entry id " . $default_entry->stat_cat_entry);

    my $req = $session->request($method, $default_entry);
    my $status = $req->gather(1);

    $logger->debug("Default stat entry " . Dumper($default_entry)); 
    
    if(!$status) {
        throw OpenSRF::EX::ERROR 
        ("Error updating default stat cat entry"); }

    $logger->debug("Default stat cat entry update returned status $status");
    return $status;
}

__PACKAGE__->register_method(
    method  => "update_stat",
    api_name    => "open-ils.circ.stat_cat.actor.update");

__PACKAGE__->register_method(
    method  => "update_stat",
    api_name    => "open-ils.circ.stat_cat.asset.update");

sub update_stat {
    my( $self, $client, $user_session, $cat ) = @_;

    my $method = "open-ils.storage.direct.actor.stat_cat.update";
    my $perm = 'UPDATE_PATRON_STAT_CAT';
    if($self->api_name =~ /asset/) {
        $method = "open-ils.storage.direct.asset.stat_cat.update";
        $perm = 'UPDATE_COPY_STAT_CAT';
    }

    my( $user_obj, $evt )  = $apputils->checkses($user_session); 
    return $evt if $evt;
    $evt = $apputils->check_perms( $user_obj->id, $cat->owner, $perm );
    return $evt if $evt;

    my $session = $apputils->start_db_session();
    $apputils->set_audit_info($session, $user_session, $user_obj->id, $user_obj->wsid);
    my $req = $session->request($method, $cat); 
    my $status = $req->gather(1);
    $apputils->commit_db_session($session);
    $logger->info("stat cat with id " . $cat->id . " updated with status $status");
    return 1;
}


__PACKAGE__->register_method(
    method  => "create_stat_entry",
    api_name    => "open-ils.circ.stat_cat.actor.entry.create");

__PACKAGE__->register_method(
    method  => "create_stat_entry",
    api_name    => "open-ils.circ.stat_cat.asset.entry.create");

sub create_stat_entry {
    my( $self, $client, $user_session, $entry ) = @_;

    my $method = "open-ils.storage.direct.actor.stat_cat_entry.create";
    my $default_entry_create = "open-ils.storage.direct.actor.stat_cat_entry_default.create";
    my $default_entry_update = "open-ils.storage.direct.actor.stat_cat_entry_default.update";
    my $perm = 'CREATE_PATRON_STAT_CAT_ENTRY';
    my $edperm = 'CREATE_PATRON_STAT_CAT_ENTRY_DEFAULT';
    my $edperm_update = 'UPDATE_PATRON_STAT_CAT_ENTRY_DEFAULT';
    my $type = 'actor';
    if($self->api_name =~ /asset/) {
        $method = "open-ils.storage.direct.asset.stat_cat_entry.create";
        $perm = 'CREATE_COPY_STAT_CAT_ENTRY';
        $type = 'asset';
    }

    my( $user_obj, $evt )  = $apputils->checkses($user_session); 
    return $evt if $evt;
    $evt = $apputils->check_perms( $user_obj->id, $entry->owner, $perm );
    return $evt if $evt;

    my $session = $apputils->start_db_session();
    $apputils->set_audit_info($session, $user_session, $user_obj->id, $user_obj->wsid);
    my $newid = _create_stat_entry($session, $entry, $method);

    if( $self->api_name =~ /actor/ && ref($entry->default_entries) ) {
        $evt = $apputils->check_perms($user_obj->id, $entry->owner, $edperm);
        return $evt if $evt;

        for my $default_entry (@{$entry->default_entries}) {
            $default_entry->stat_cat_entry($newid);
            my $target;
            ($target, $evt) = $apputils->fetch_stat_cat_entry_default_by_stat_cat_and_org($type, 
                                                    $default_entry->stat_cat, 
                                                    $default_entry->owner);
            if( $target ) {
                $evt = $apputils->check_perms($user_obj->id, $default_entry->owner, $edperm_update);
                return $evt if $evt;
                $target->stat_cat_entry($newid);
                _update_stat_entry_default($session, $target, $default_entry_update);
            } else {
                _create_stat_entry_default($session, $default_entry, $default_entry_create);
            }
        }
    }

    $apputils->commit_db_session($session);

    $logger->info("created stat cat entry $newid");

    return $newid;
}

__PACKAGE__->register_method(
    method => "create_stat_entry_default",
    api_name => "open-ils.circ.stat_cat.actor.entry.default.create");


sub create_stat_entry_default {
    my( $self, $client, $user_session, $default_entry ) = @_;

    my $create_method = "open-ils.storage.direct.actor.stat_cat_entry_default.create";
    my $update_method = "open-ils.storage.direct.actor.stat_cat_entry_default.update";
    my $create_perm = 'UPDATE_PATRON_STAT_CAT_ENTRY_DEFAULT';
    my $update_perm = 'CREATE_PATRON_STAT_CAT_ENTRY_DEFAULT';
    my $type = 'actor';
    my ($target, $id);

    my( $user_obj, $evt )  = $apputils->checkses($user_session); 
    return $evt if $evt;

    my $session = $apputils->start_db_session();

    ($target, $evt) = $apputils->fetch_stat_cat_entry_default_by_stat_cat_and_org(
        $type, 
        $default_entry->stat_cat, 
        $default_entry->owner);
    if( $target ) {
        $evt = $apputils->check_perms($user_obj->id, $default_entry->owner, $update_perm);
        return $evt if $evt;
        $id = $target->id;
        $default_entry->id($id);
        _update_stat_entry_default($session, $default_entry, $update_method);
        $logger->info("updated stat cat default entry $id");
    } else {
        $evt = $apputils->check_perms($user_obj->id, $default_entry->owner, $create_perm);
        return $evt if $evt;
        $id = _create_stat_entry_default($session, $default_entry, $create_method);
        $logger->info("created stat cat default entry $id");
    }

    $apputils->commit_db_session($session);

    return $id;
}

sub _create_stat_entry_default {
    my( $session, $stat_entry_default, $method) = @_;

    $logger->debug("Creating new default stat entry for stat_cat " . $stat_entry_default->stat_cat);
    $stat_entry_default->clear_id();

    my $req = $session->request($method, $stat_entry_default);
    my $id = $req->gather(1);

    $logger->debug("Default stat entry " . Dumper($stat_entry_default));    

    if(!$id) {
        throw OpenSRF::EX::ERROR 
        ("Error creating new default stat cat entry"); }

    $logger->debug("Default stat cat entry create returned id $id");
    return $id;
}

__PACKAGE__->register_method(
    method  => "create_stat_map",
    api_name    => "open-ils.circ.stat_cat.actor.user_map.create");

__PACKAGE__->register_method(
    method  => "create_stat_map",
    api_name    => "open-ils.circ.stat_cat.asset.copy_map.create");

sub create_stat_map {
    my( $self, $client, $user_session, $map ) = @_;


    my ( $evt, $copy, $volume, $patron, $user_obj );

    my $method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.create";
    my $ret = "open-ils.storage.direct.actor.stat_cat_entry_user_map.retrieve";
    my $perm = 'CREATE_PATRON_STAT_CAT_ENTRY_MAP';
    my $perm_org;

    if($self->api_name =~ /asset/) {
        $method = "open-ils.storage.direct.asset.stat_cat_entry_copy_map.create";
        $ret = "open-ils.storage.direct.asset.stat_cat_entry_copy_map.retrieve";
        $perm = 'CREATE_COPY_STAT_CAT_ENTRY_MAP';
        ( $copy, $evt ) = $apputils->fetch_copy($map->owning_copy);
        return $evt if $evt;
        ( $volume, $evt ) = $apputils->fetch_callnumber($copy->call_number);
        return $evt if $evt;
        $perm_org = $volume->owning_lib;

    } else {
        ($patron, $evt) = $apputils->fetch_user($map->target_usr);
        return $evt if $evt;
        $perm_org = $patron->home_ou;
    }

    ( $user_obj, $evt )  = $apputils->checkses($user_session); 
    return $evt if $evt;
    $evt = $apputils->check_perms( $user_obj->id, $perm_org, $perm );
    return $evt if $evt;

    $logger->debug( $user_obj->id . " creating new stat cat map" );

    $map->clear_id();

    my $session = $apputils->start_db_session();
    $apputils->set_audit_info($session, $user_session, $user_obj->id, $user_obj->wsid);
    my $req = $session->request($method, $map); 
    my $newid = $req->gather(1);
    $logger->debug("Created new stat cat map with id $newid");
    $apputils->commit_db_session($session);

    return $apputils->simple_scalar_request( "open-ils.storage", $ret, $newid );

}


__PACKAGE__->register_method(
    method  => "update_stat_map",
    api_name    => "open-ils.circ.stat_cat.actor.user_map.update");

__PACKAGE__->register_method(
    method  => "update_stat_map",
    api_name    => "open-ils.circ.stat_cat.asset.copy_map.update");

sub update_stat_map {
    my( $self, $client, $user_session, $map ) = @_;

    my ( $evt, $copy, $volume, $patron, $user_obj );

    my $method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.update";
    my $perm = 'UPDATE_PATRON_STAT_ENTRY_MAP';
    my $perm_org;

    if($self->api_name =~ /asset/) {
        $method = "open-ils.storage.direct.asset.stat_cat_entry_copy_map.update";
        $perm = 'UPDATE_COPY_STAT_ENTRY_MAP';
        ( $copy, $evt ) = $apputils->fetch_copy($map->owning_copy);
        return $evt if $evt;
        ( $volume, $evt ) = $apputils->fetch_callnumber($copy->call_number);
        return $evt if $evt;
        $perm_org = $volume->owning_lib;

    } else {
        ($patron, $evt) = $apputils->fetch_user($map->target_usr);
        return $evt if $evt;
        $perm_org = $patron->home_ou;
    }


    ( $user_obj, $evt )  = $apputils->checkses($user_session); 
    return $evt if $evt;
    $evt = $apputils->check_perms( $user_obj->id, $perm_org, $perm );
    return $evt if $evt;


    my $session = $apputils->start_db_session();
    $apputils->set_audit_info($session, $user_session, $user_obj->id, $user_obj->wsid);
    my $req = $session->request($method, $map); 
    my $newid = $req->gather(1);
    $logger->debug("Updated new stat cat map with id $newid");
    $apputils->commit_db_session($session);

    return $newid;
}



__PACKAGE__->register_method(
    method  => "retrieve_maps",
    api_name    => "open-ils.circ.stat_cat.actor.user_map.retrieve");

__PACKAGE__->register_method(
    method  => "retrieve_maps",
    api_name    => "open-ils.circ.stat_cat.asset.copy_map.retrieve");

sub retrieve_maps {
    my( $self, $client, $user_session, $target ) = @_;


    my( $user_obj, $evt ) = $apputils->checkses($user_session); 
    return $evt if $evt;

    my  $method = "open-ils.storage.direct.asset.stat_cat_entry_copy_map.search.owning_copy.atomic";
    if($self->api_name =~ /actor/ ) {
        if(!$target) { $target = $user_obj->id; }
        $method = "open-ils.storage.direct.actor.stat_cat_entry_user_map.search.target_usr.atomic";
    }

    return $apputils->simple_scalar_request("open-ils.storage", $method, $target);
}




__PACKAGE__->register_method(
    method  => "delete_stats",
    api_name    => "open-ils.circ.stat_cat.actor.delete");

__PACKAGE__->register_method(
    method  => "delete_stats",
    api_name    => "open-ils.circ.stat_cat.asset.delete");

sub delete_stats {
    my( $self, $client, $user_session, $target ) = @_;
    
    my $cat;

    my $type = "actor";
    my $perm = 'DELETE_PATRON_STAT_CAT';
    if($self->api_name =~ /asset/) { 
        $type = "asset"; 
        $perm = 'DELETE_COPY_STAT_CAT';
    }

    my( $user_obj, $evt )  = $apputils->checkses($user_session); 
    return $evt if $evt;

    ( $cat, $evt ) = $apputils->fetch_stat_cat( $type, $target );
    return $evt if $evt;

    $evt = $apputils->check_perms( $user_obj->id, $cat->owner, $perm );
    return $evt if $evt;

    my $session = OpenSRF::AppSession->create("open-ils.storage");
    return _delete_stats($session, $target, $type);
}

sub _delete_stats {
    my( $session, $stat, $type) = @_;

    my  $method = "open-ils.storage.direct.asset.stat_cat.delete";
    if($type =~ /actor/ ) {
        $method = "open-ils.storage.direct.actor.stat_cat.delete";
    }
    return $session->request($method, $stat)->gather(1);
}



__PACKAGE__->register_method(
    method  => "delete_entry",
    api_name    => "open-ils.circ.stat_cat.actor.entry.delete");

__PACKAGE__->register_method(
    method  => "delete_entry",
    api_name    => "open-ils.circ.stat_cat.asset.entry.delete");

sub delete_entry {
    my( $self, $client, $user_session, $target ) = @_;

    my $type = "actor";
    my $perm = 'DELETE_PATRON_STAT_CAT_ENTRY';
    if($self->api_name =~ /asset/) { 
        $type = "asset"; 
        $perm = 'DELETE_COPY_STAT_CAT_ENTRY';
    }

    my $entry;
    my( $user_obj, $evt )  = $apputils->checkses($user_session); 
    return $evt if $evt;

    ( $entry, $evt ) = $apputils->fetch_stat_cat_entry( $type, $target );
    return $evt if $evt;

    $evt = $apputils->check_perms( $user_obj->id, $entry->owner, $perm );
    return $evt if $evt;

    my $session = OpenSRF::AppSession->create("open-ils.storage");
    return _delete_entry($session, $target, $type);
}

sub _delete_entry {
    my( $session, $stat_entry, $type) = @_;

    my  $method = "open-ils.storage.direct.asset.stat_cat_entry.delete";
    if($type =~ /actor/ ) {
        $method = "open-ils.storage.direct.actor.stat_cat_entry.delete";
    }

    return $session->request($method, $stat_entry)->gather(1);
}


__PACKAGE__->register_method(
    method => "delete_entry_default",
    api_name => "open-ils.circ.stat_cat.actor.entry.default.delete");

sub delete_entry_default {
    my( $self, $client, $user_session, $target ) = @_;

    my $type = "actor";
    my $perm = 'DELETE_PATRON_STAT_CAT_ENTRY_DEFAULT';

    my $default_entry;
    my( $user_obj, $evt )  = $apputils->checkses($user_session); 
    return $evt if $evt;

    ( $default_entry, $evt ) = $apputils->fetch_stat_cat_entry_default( $type, $target );
    return $evt if $evt;

    $evt = $apputils->check_perms( $user_obj->id, $default_entry->owner, $perm );
    return $evt if $evt;

    my $session = OpenSRF::AppSession->create("open-ils.storage");
    return _delete_entry_default($session, $target, $type);
}

sub _delete_entry_default {
    my( $session, $stat_entry, $type) = @_;

    my $method = "open-ils.storage.direct.actor.stat_cat_entry_default.delete";
    if($type =~ /asset/ ) {
        $method = "open-ils.storage.direct.asset.stat_cat_entry_default.delete";
    }

    return $session->request($method, $stat_entry)->gather(1);
}

__PACKAGE__->register_method(
    method => 'fetch_stats_by_copy',
    api_name    => 'open-ils.circ.asset.stat_cat_entries.fleshed.retrieve_by_copy',
);


sub fetch_stats_by_copy {
    my( $self, $conn, $args ) = @_;

    my @entries;

    if( $$args{public} ) {
        my $maps = $U->cstorereq(
            'open-ils.cstore.direct.asset.stat_cat_entry_copy_map.search.atomic', { owning_copy => $$args{copyid} });


        for my $map (@$maps) {

            $logger->debug("map ".$map->id);
            $logger->debug("map ".$map->stat_cat_entry);

            my $entry = $U->cstorereq(
                'open-ils.cstore.direct.asset.stat_cat_entry.retrieve', $map->stat_cat_entry);

            $logger->debug("Found entry ".$entry->id);

            my $cat = $U->cstorereq(
                'open-ils.cstore.direct.asset.stat_cat.retrieve', $entry->stat_cat );
            $entry->stat_cat( $cat );
            push( @entries, $entry );
        }
    }

    return \@entries;
}

__PACKAGE__->register_method(
    method => 'retrieve_entry_default',
    api_name => "open-ils.circ.stat_cat.actor.entry_default.ancestor_default",
);

sub retrieve_entry_default {
    my( $self, $client, $user_session, $orgid, $stat_cat ) = @_;
    
    my $method = "open-ils.storage.actor.stat_cat_entry_default.ancestor.retrieve.atomic";

    return $apputils->simple_scalar_request( "open-ils.storage", $method, $orgid, $stat_cat);
}



1;
