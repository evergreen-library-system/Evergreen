package OpenILS::Application::Actor::Container;
use base 'OpenILS::Application';
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Perm;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;
my $logger = "OpenSRF::Utils::Logger";

sub initialize { return 1; }

my $svc = 'open-ils.cstore';
my $meth = 'open-ils.cstore.direct.container';
my %types;
my %ctypes;
$types{'biblio'} = "$meth.biblio_record_entry_bucket";
$types{'callnumber'} = "$meth.call_number_bucket";
$types{'copy'} = "$meth.copy_bucket";
$types{'user'} = "$meth.user_bucket";
$ctypes{'biblio'} = "container_biblio_record_entry_bucket";
$ctypes{'callnumber'} = "container_call_number_bucket";
$ctypes{'copy'} = "container_copy_bucket";
$ctypes{'user'} = "container_user_bucket";
my $event;

sub _sort_buckets {
	my $buckets = shift;
	return $buckets unless ($buckets && $buckets->[0]);
	return [ sort { $a->name cmp $b->name } @$buckets ];
}

__PACKAGE__->register_method(
	method	=> "bucket_retrieve_all",
	api_name	=> "open-ils.actor.container.all.retrieve_by_user",
	notes		=> <<"	NOTES");
		Retrieves all un-fleshed buckets assigned to given user 
		PARAMS(authtoken, bucketOwnerId)
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
	NOTES

sub bucket_retrieve_all {
	my($self, $client, $auth, $user_id) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;

    if($e->requestor->id ne $user_id) {
        return $e->event unless $e->allowed('VIEW_CONTAINER');
    }
    
	my %buckets;
    for my $type (keys %ctypes) {
        my $meth = "search_" . $ctypes{$type};
	    $buckets{$type} = $e->$meth({owner => $user_id});
    }

	return \%buckets;
}

__PACKAGE__->register_method(
	method	=> "bucket_flesh",
	api_name	=> "open-ils.actor.container.flesh",
	argc		=> 3, 
);

__PACKAGE__->register_method(
	method	=> "bucket_flesh_pub",
	api_name	=> "open-ils.actor.container.public.flesh",
	argc		=> 3, 
);

sub bucket_flesh {
	my($self, $conn, $auth, $class, $bucket_id) = @_;
    my $e = new_editor(authtoken => $auth);
    return $e->event unless $e->checkauth;
    return _bucket_flesh($self, $conn, $e, $class, $bucket_id);
}

sub bucket_flesh_pub {
    my($self, $conn, $class, $bucket_id) = @_;
    my $e = new_editor();
    return _bucket_flesh($self, $conn, $e, $class, $bucket_id);
}

sub _bucket_flesh {
	my($self, $conn, $e, $class, $bucket_id) = @_;
	my $meth = 'retrieve_' . $ctypes{$class};
    my $bkt = $e->$meth($bucket_id) or return $e->event;

	unless($U->is_true($bkt->pub)) {
        return undef if $self->api_name =~ /public/;
        unless($bkt->owner eq $e->requestor->id) {
            return $e->event unless $e->allowed('VIEW_CONTAINER', $bkt);
        }
	}

    my $fmclass = $bkt->class_name . "i";
    $meth = 'search_' . $ctypes{$class} . '_item';
	$bkt->items(
        $e->$meth(
            {bucket => $bucket_id}, 
            {   order_by => {$fmclass => "pos"},
                flesh => 1, 
                flesh_fields => {$fmclass => ['notes']}
            }
        )
    );

	return $bkt;
}


__PACKAGE__->register_method(
	method	=> "item_note_cud",
	api_name	=> "open-ils.actor.container.item_note.cud",
);


sub item_note_cud {
    my($self, $conn, $auth, $class, $note) = @_;
    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $meth = 'retrieve_' . $ctypes{$class};
    my $nclass = $note->class_name;
    (my $iclass = $nclass) =~ s/n$//og;

    my $db_note = $e->$meth($note->id, {
        flesh => 2,
        flesh_fields => {
            $nclass => ['item'],
            $iclass => ['bucket']
        }
    });

    if($db_note->item->bucket->owner ne $e->requestor->id) {
        return $e->die_event unless 
            $e->allowed('UPDATE_CONTAINER', $db_note->item->bucket);
    }

    $meth = 'create_' . $ctypes{$class} if $note->isnew;
    $meth = 'update_' . $ctypes{$class} if $note->ischanged;
    $meth = 'delete_' . $ctypes{$class} if $note->isdeleted;
    return $e->die_event unless $e->$meth($note);
    $e->commit;
}


__PACKAGE__->register_method(
	method	=> "bucket_retrieve_class",
	api_name	=> "open-ils.actor.container.retrieve_by_class",
	argc		=> 3, 
	notes		=> <<"	NOTES");
		Retrieves all un-fleshed buckets by class assigned to given user 
		PARAMS(authtoken, bucketOwnerId, class [, type])
		class can be one of "biblio", "callnumber", "copy", "user"
		The optional "type" parameter allows you to limit the search by 
		bucket type.  
		If bucketOwnerId is not defined, the authtoken is used as the
		bucket owner.
		If requestor ID is different than bucketOwnerId, requestor must have
		VIEW_CONTAINER permissions.
	NOTES

sub bucket_retrieve_class {
	my( $self, $client, $authtoken, $userid, $class, $type ) = @_;

	my( $staff, $user, $evt ) = 
		$apputils->checkses_requestor( $authtoken, $userid, 'VIEW_CONTAINER' );
	return $evt if $evt;

	$logger->debug("User " . $staff->id . 
		" retrieving buckets for user $userid [class=$class, type=$type]");

	my $meth = $types{$class} . ".search.atomic";
	my $buckets;

	if( $type ) {
		$buckets = $apputils->simplereq( $svc, 
			$meth, { owner => $userid, btype => $type } );
	} else {
		$logger->debug("Grabbing buckets by class $class: $svc : $meth :  {owner => $userid}");
		$buckets = $apputils->simplereq( $svc, $meth, { owner => $userid } );
	}

	return _sort_buckets($buckets);
}

__PACKAGE__->register_method(
	method	=> "bucket_create",
	api_name	=> "open-ils.actor.container.create",
	notes		=> <<"	NOTES");
		Creates a new bucket object.  If requestor is different from
		bucketOwner, requestor needs CREATE_CONTAINER permissions
		PARAMS(authtoken, bucketObject);
		Returns the new bucket object
	NOTES

sub bucket_create {
	my( $self, $client, $authtoken, $class, $bucket ) = @_;

	my $e = new_editor(xact=>1, authtoken=>$authtoken);
	return $e->event unless $e->checkauth;

	if( $bucket->owner ne $e->requestor->id ) {
		return $e->event unless
			$e->allowed('CREATE_CONTAINER');

	} else {
		return $e->event unless
			$e->allowed('CREATE_MY_CONTAINER');
	}
		
	$bucket->clear_id;

    my $evt = OpenILS::Event->new('CONTAINER_EXISTS', 
        payload => [$class, $bucket->owner, $bucket->btype, $bucket->name]);
    my $search = {name => $bucket->name, owner => $bucket->owner, btype => $bucket->btype};

	my $obj;
	if( $class eq 'copy' ) {
        return $evt if $e->search_container_copy_bucket($search)->[0];
		return $e->event unless
			$obj = $e->create_container_copy_bucket($bucket);
	}

	if( $class eq 'callnumber' ) {
        return $evt if $e->search_container_call_number_bucket($search)->[0];
		return $e->event unless
			$obj = $e->create_container_call_number_bucket($bucket);
	}

	if( $class eq 'biblio' ) {
        return $evt if $e->search_container_biblio_record_entry_bucket($search)->[0];
		return $e->event unless
			$obj = $e->create_container_biblio_record_entry_bucket($bucket);
	}

	if( $class eq 'user') {
        return $evt if $e->search_container_user_bucket($search)->[0];
		return $e->event unless
			$obj = $e->create_container_user_bucket($bucket);
	}

	$e->commit;
	return $obj->id;
}


__PACKAGE__->register_method(
	method	=> "item_create",
	api_name	=> "open-ils.actor.container.item.create",
	notes		=> <<"	NOTES");
		PARAMS(authtoken, class, item)
	NOTES

sub item_create {
	my( $self, $client, $authtoken, $class, $item ) = @_;

	my $e = new_editor(xact=>1, authtoken=>$authtoken);
	return $e->event unless $e->checkauth;

	my ( $bucket, $evt ) = $apputils->fetch_container_e($e, $item->bucket, $class);
	return $evt if $evt;

	if( $bucket->owner ne $e->requestor->id ) {
		return $e->event unless
			$e->allowed('CREATE_CONTAINER_ITEM');

	} else {
#		return $e->event unless
#			$e->allowed('CREATE_CONTAINER_ITEM'); # new perm here?
	}
		
	$item->clear_id;

	my $stat;
	if( $class eq 'copy' ) {
		return $e->event unless
			$stat = $e->create_container_copy_bucket_item($item);
	}

	if( $class eq 'callnumber' ) {
		return $e->event unless
			$stat = $e->create_container_call_number_bucket_item($item);
	}

	if( $class eq 'biblio' ) {
		return $e->event unless
			$stat = $e->create_container_biblio_record_entry_bucket_item($item);
	}

	if( $class eq 'user') {
		return $e->event unless
			$stat = $e->create_container_user_bucket_item($item);
	}

	$e->commit;
	return $stat->id;
}



__PACKAGE__->register_method(
	method	=> "item_delete",
	api_name	=> "open-ils.actor.container.item.delete",
	notes		=> <<"	NOTES");
		PARAMS(authtoken, class, itemId)
	NOTES

sub item_delete {
	my( $self, $client, $authtoken, $class, $itemid ) = @_;

	my $e = new_editor(xact=>1, authtoken=>$authtoken);
	return $e->event unless $e->checkauth;

	my $ret = __item_delete($e, $class, $itemid);
	$e->commit unless $U->event_code($ret);
	return $ret;
}

sub __item_delete {
	my( $e, $class, $itemid ) = @_;
	my( $bucket, $item, $evt);

	( $item, $evt ) = $U->fetch_container_item_e( $e, $itemid, $class );
	return $evt if $evt;

	( $bucket, $evt ) = $U->fetch_container_e($e, $item->bucket, $class);
	return $evt if $evt;

	if( $bucket->owner ne $e->requestor->id ) {
      my $owner = $e->retrieve_actor_user($bucket->owner)
         or return $e->die_event;
		return $e->event unless $e->allowed('DELETE_CONTAINER_ITEM', $owner->home_ou);
	}

	my $stat;
	if( $class eq 'copy' ) {
        for my $note (@{$e->search_container_copy_bucket_item_note({item => $item->id})}) {
            return $e->event unless 
                $e->delete_container_copy_bucket_item_note($note);
        }
		return $e->event unless
			$stat = $e->delete_container_copy_bucket_item($item);
	}

	if( $class eq 'callnumber' ) {
        for my $note (@{$e->search_container_call_number_bucket_item_note({item => $item->id})}) {
            return $e->event unless 
                $e->delete_container_call_number_bucket_item_note($note);
        }
		return $e->event unless
			$stat = $e->delete_container_call_number_bucket_item($item);
	}

	if( $class eq 'biblio' ) {
        for my $note (@{$e->search_container_biblio_record_entry_bucket_item_note({item => $item->id})}) {
            return $e->event unless 
                $e->delete_container_biblio_record_entry_bucket_item_note($note);
        }
		return $e->event unless
			$stat = $e->delete_container_biblio_record_entry_bucket_item($item);
	}

	if( $class eq 'user') {
        for my $note (@{$e->search_container_user_bucket_item_note({item => $item->id})}) {
            return $e->event unless 
                $e->delete_container_user_bucket_item_note($note);
        }
		return $e->event unless
			$stat = $e->delete_container_user_bucket_item($item);
	}

	return $stat;
}


__PACKAGE__->register_method(
	method	=> 'full_delete',
	api_name	=> 'open-ils.actor.container.full_delete',
	notes		=> "Complety removes a container including all attached items",
);	

sub full_delete {
	my( $self, $client, $authtoken, $class, $containerId ) = @_;
	my( $container, $evt);

	my $e = new_editor(xact=>1, authtoken=>$authtoken);
	return $e->event unless $e->checkauth;

	( $container, $evt ) = $apputils->fetch_container_e($e, $containerId, $class);
	return $evt if $evt;

	if( $container->owner ne $e->requestor->id ) {
      my $owner = $e->retrieve_actor_user($container->owner)
         or return $e->die_event;
		return $e->event unless $e->allowed('DELETE_CONTAINER', $owner->home_ou);
	}

	my $items; 

	my @s = ({bucket => $containerId}, {idlist=>1});

	if( $class eq 'copy' ) {
		$items = $e->search_container_copy_bucket_item(@s);
	}

	if( $class eq 'callnumber' ) {
		$items = $e->search_container_call_number_bucket_item(@s);
	}

	if( $class eq 'biblio' ) {
		$items = $e->search_container_biblio_record_entry_bucket_item(@s);
	}

	if( $class eq 'user') {
		$items = $e->search_container_user_bucket_item(@s);
	}

	__item_delete($e, $class, $_) for @$items;

	my $stat;
	if( $class eq 'copy' ) {
		return $e->event unless
			$stat = $e->delete_container_copy_bucket($container);
	}

	if( $class eq 'callnumber' ) {
		return $e->event unless
			$stat = $e->delete_container_call_number_bucket($container);
	}

	if( $class eq 'biblio' ) {
		return $e->event unless
			$stat = $e->delete_container_biblio_record_entry_bucket($container);
	}

	if( $class eq 'user') {
		return $e->event unless
			$stat = $e->delete_container_user_bucket($container);
	}

	$e->commit;
	return $stat;
}

__PACKAGE__->register_method(
	method		=> 'container_update',
	api_name		=> 'open-ils.actor.container.update',
	signature	=> q/
		Updates the given container item.
		@param authtoken The login session key
		@param class The container class
		@param container The container item
		@return true on success, 0 on no update, Event on error
		/
);

sub container_update {
	my( $self, $conn, $authtoken, $class, $container )  = @_;

	my $e = new_editor(xact=>1, authtoken=>$authtoken);
	return $e->event unless $e->checkauth;

	my ( $dbcontainer, $evt ) = $U->fetch_container_e($e, $container->id, $class);
	return $evt if $evt;

	if( $e->requestor->id ne $container->owner ) {
		return $e->event unless $e->allowed('UPDATE_CONTAINER');
	}

	my $stat;
	if( $class eq 'copy' ) {
		return $e->event unless
			$stat = $e->update_container_copy_bucket($container);
	}

	if( $class eq 'callnumber' ) {
		return $e->event unless
			$stat = $e->update_container_call_number_bucket($container);
	}

	if( $class eq 'biblio' ) {
		return $e->event unless
			$stat = $e->update_container_biblio_record_entry_bucket($container);
	}

	if( $class eq 'user') {
		return $e->event unless
			$stat = $e->update_container_user_bucket($container);
	}

	$e->commit;
	return $stat;
}




1;


