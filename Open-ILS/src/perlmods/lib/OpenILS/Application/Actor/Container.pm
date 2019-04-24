package OpenILS::Application::Actor::Container;
use base 'OpenILS::Application';
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Perm;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw(md5_hex);
use OpenSRF::Utils::JSON;

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;
my $logger = "OpenSRF::Utils::Logger";

sub initialize { return 1; }

my $svc = 'open-ils.cstore';
my $meth = 'open-ils.cstore.direct.container';
my %types;
my %ctypes;
my %itypes;
my %htypes;
my %qtypes;
my %ttypes;
my %batch_perm;
my %table;

$batch_perm{'biblio'} = ['UPDATE_MARC'];
$batch_perm{'callnumber'} = ['UPDATE_VOLUME'];
$batch_perm{'copy'} = ['UPDATE_COPY'];
$batch_perm{'user'} = ['UPDATE_USER'];

$types{'biblio'} = "$meth.biblio_record_entry_bucket";
$types{'callnumber'} = "$meth.call_number_bucket";
$types{'copy'} = "$meth.copy_bucket";
$types{'user'} = "$meth.user_bucket";

$ctypes{'biblio'} = "container_biblio_record_entry_bucket";
$ctypes{'callnumber'} = "container_call_number_bucket";
$ctypes{'copy'} = "container_copy_bucket";
$ctypes{'user'} = "container_user_bucket";

$itypes{'biblio'} = "biblio_record_entry";
$itypes{'callnumber'} = "asset_call_number";
$itypes{'copy'} = "asset_copy";
$itypes{'user'} = "actor_user";

$ttypes{'biblio'} = "biblio_record_entry";
$ttypes{'callnumber'} = "call_number";
$ttypes{'copy'} = "copy";
$ttypes{'user'} = "user";

$htypes{'biblio'} = "bre";
$htypes{'callnumber'} = "acn";
$htypes{'copy'} = "acp";
$htypes{'user'} = "au";

$table{'biblio'} = "biblio.record_entry";
$table{'callnumber'} = "asset.call_number";
$table{'copy'} = "asset.copy";
$table{'user'} = "actor.usr";

#$qtypes{'biblio'} = 0 
#$qtypes{'callnumber'} = 0;
#$qtypes{'copy'} = 0;
$qtypes{'user'} = 1;

my $event;

sub _sort_buckets {
    my $buckets = shift;
    return $buckets unless ($buckets && $buckets->[0]);
    return [ sort { $a->name cmp $b->name } @$buckets ];
}

__PACKAGE__->register_method(
    method  => "bucket_retrieve_all",
    api_name    => "open-ils.actor.container.all.retrieve_by_user",
    authoritative => 1,
    notes        => <<"    NOTES");
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
        $buckets{$type} = _sort_buckets($e->$meth({owner => $user_id}));
    }

    return \%buckets;
}

__PACKAGE__->register_method(
    method  => "bucket_flesh",
    api_name    => "open-ils.actor.container.flesh",
    authoritative => 1,
    argc        => 3, 
);

__PACKAGE__->register_method(
    method  => "bucket_flesh_pub",
    api_name    => "open-ils.actor.container.public.flesh",
    argc        => 3, 
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
            my $owner = $e->retrieve_actor_user($bkt->owner)
                or return $e->die_event;
            return $e->event unless $e->allowed('VIEW_CONTAINER', $owner->home_ou);
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
    method  => "item_note_cud",
    api_name    => "open-ils.actor.container.item_note.cud",
);


sub item_note_cud {
    my($self, $conn, $auth, $class, $note) = @_;

    return new OpenILS::Event("BAD_PARAMS") unless
        $note->class_name =~ /bucket_item_note$/;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $meat = $ctypes{$class} . "_item_note";
    my $meth = "retrieve_$meat";

    my $item_meat = $ctypes{$class} . "_item";
    my $item_meth = "retrieve_$item_meat";

    my $nhint = $Fieldmapper::fieldmap->{$note->class_name}->{hint};
    (my $ihint = $nhint) =~ s/n$//og;

    my ($db_note, $item);

    if ($note->isnew) {
        $db_note = $note;

        $item = $e->$item_meth([
            $note->item, {
                flesh => 1, flesh_fields => {$ihint => ["bucket"]}
            }
        ]) or return $e->die_event;
    } else {
        $db_note = $e->$meth([
            $note->id, {
                flesh => 2,
                flesh_fields => {
                    $nhint => ['item'],
                    $ihint => ['bucket']
                }
            }
        ]) or return $e->die_event;

        $item = $db_note->item;
    }

    if($item->bucket->owner ne $e->requestor->id) {
        return $e->die_event unless $e->allowed("UPDATE_CONTAINER");
    }

    $meth = 'create_' . $meat if $note->isnew;
    $meth = 'update_' . $meat if $note->ischanged;
    $meth = 'delete_' . $meat if $note->isdeleted;
    return $e->die_event unless $e->$meth($note);
    $e->commit;
}


__PACKAGE__->register_method(
    method  => "bucket_retrieve_class",
    api_name    => "open-ils.actor.container.retrieve_by_class",
    argc        => 3, 
    authoritative   => 1, 
    notes        => <<"    NOTES");
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
    method  => "bucket_create",
    api_name    => "open-ils.actor.container.create",
    notes        => <<"    NOTES");
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
    method  => "item_create",
    api_name    => "open-ils.actor.container.item.create",
    signature => {
        desc => q/
            Adds one or more items to an existing container
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Container class.  Can be "copy", "callnumber", "biblio", or "user"', type => 'string'},
            {desc => 'Item or items.  Can either be a single container item object, or an array of them', type => 'object'},
        ],
        return => {
            desc => 'The ID of the newly created item(s).  In batch context, an array of IDs is returned'
        }
    }
);


sub item_create {
    my( $self, $client, $authtoken, $class, $item ) = @_;

    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->die_event unless $e->checkauth;
    my $items = (ref $item eq 'ARRAY') ? $item : [$item];

    my ( $bucket, $evt ) = 
        $apputils->fetch_container_e($e, $items->[0]->bucket, $class);
    return $evt if $evt;

    if( $bucket->owner ne $e->requestor->id ) {
        return $e->die_event unless
            $e->allowed('CREATE_CONTAINER_ITEM');

    } else {
#       return $e->event unless
#           $e->allowed('CREATE_CONTAINER_ITEM'); # new perm here?
    }
        
    for my $one_item (@$items) {

        $one_item->clear_id;

        my $stat;
        if( $class eq 'copy' ) {
            return $e->die_event unless
                $stat = $e->create_container_copy_bucket_item($one_item);
        }

        if( $class eq 'callnumber' ) {
            return $e->die_event unless
                $stat = $e->create_container_call_number_bucket_item($one_item);
        }

        if( $class eq 'biblio' ) {
            return $e->die_event unless
                $stat = $e->create_container_biblio_record_entry_bucket_item($one_item);
        }

        if( $class eq 'user') {
            return $e->die_event unless
                $stat = $e->create_container_user_bucket_item($one_item);
        }
    }

    $e->commit;

    # CStoreEeditor inserts the id (pkey) on newly created objects
    return [ map { $_->id } @$items ] if ref $item eq 'ARRAY';
    return $item->id; 
}



__PACKAGE__->register_method(
    method  => "item_delete",
    api_name    => "open-ils.actor.container.item.delete",
    notes        => <<"    NOTES");
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
    method  => 'full_delete',
    api_name    => 'open-ils.actor.container.full_delete',
    notes       => "Complety removes a container including all attached items",
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
    method      => 'container_update',
    api_name        => 'open-ils.actor.container.update',
    signature   => q/
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



__PACKAGE__->register_method(
    method  => "anon_cache",
    api_name    => "open-ils.actor.anon_cache.set_value",
    signature => {
        desc => q/
            Sets a value in the anon web cache.  If the session key is
            undefined, one will be automatically generated.
        /,
        params => [
            {desc => 'Session key', type => 'string'},
            {
                desc => q/Field name.  The name of the field in this cache session whose value to set/, 
                type => 'string'
            },
            {
                desc => q/The cached value.  This can be any type of object (hash, array, string, etc.)/,
                type => 'any'
            },
        ],
        return => {
            desc => 'session key on success, undef on error',
            type => 'string'
        }
    }
);

__PACKAGE__->register_method(
    method  => "anon_cache",
    api_name    => "open-ils.actor.anon_cache.get_value",
    signature => {
        desc => q/
            Returns the cached data at the specified field within the specified cache session.
        /,
        params => [
            {desc => 'Session key', type => 'string'},
            {
                desc => q/Field name.  The name of the field in this cache session whose value to set/, 
                type => 'string'
            },
        ],
        return => {
            desc => 'cached value on success, undef on error',
            type => 'any'
        }
    }
);

__PACKAGE__->register_method(
    method  => "anon_cache",
    api_name    => "open-ils.actor.anon_cache.delete_session",
    signature => {
        desc => q/
            Deletes a cache session.
        /,
        params => [
            {desc => 'Session key', type => 'string'},
        ],
        return => {
            desc => 'Session key',
            type => 'string'
        }
    }
);

sub anon_cache {
    my($self, $conn, $ses_key, $field_key, $value) = @_;

    my $sc = OpenSRF::Utils::SettingsClient->new;
    my $cache = OpenSRF::Utils::Cache->new('anon');
    my $cache_timeout = $sc->config_value(cache => anon => 'max_cache_time') || 1800; # 30 minutes
    my $cache_size = $sc->config_value(cache => anon => 'max_cache_size') || 102400; # 100k

    if($self->api_name =~ /delete_session/) {

       return $cache->delete_cache($ses_key); 

    }  elsif( $self->api_name =~ /set_value/ ) {

        $ses_key = md5_hex(time . rand($$)) unless $ses_key;
        my $blob = $cache->get_cache($ses_key) || {};
        $blob->{$field_key} = $value;
        return undef if 
            length(OpenSRF::Utils::JSON->perl2JSON($blob)) > $cache_size; # bytes, characters, whatever ;)
        $cache->put_cache($ses_key, $blob, $cache_timeout);
        return $ses_key;

    } else {

        my $blob = $cache->get_cache($ses_key) or return undef;
        return $blob if (!defined($field_key));
        return $blob->{$field_key};
    }
}

sub batch_statcat_apply {
    my $self = shift;
    my $client = shift;
    my $ses = shift;
    my $c_id = shift;
    my $changes = shift;

    # $changes is a hashref that looks like:
    #   {
    #       remove  => [ qw/ stat cat ids to remove / ],
    #       apply   => { $statcat_id => $value_string, ... }
    #   }

    my $class = 'user';
    my $max = 0;
    my $count = 0;
    my $stage = 0;

    my $e = new_editor(xact=>1, authtoken=>$ses);
    return $e->die_event unless $e->checkauth;
    $client->respond({ ord => $stage++, stage => 'CONTAINER_BATCH_UPDATE_PERM_CHECK' });
    return $e->die_event unless $e->allowed('CONTAINER_BATCH_UPDATE');

    my $meth = 'retrieve_' . $ctypes{$class};
    my $bkt = $e->$meth($c_id) or return $e->die_event;

    unless($bkt->owner eq $e->requestor->id) {
        $client->respond({ ord => $stage++, stage => 'CONTAINER_PERM_CHECK' });
        my $owner = $e->retrieve_actor_user($bkt->owner)
            or return $e->die_event;
        return $e->die_event unless (
            $e->allowed('VIEW_CONTAINER', $bkt->owning_lib) || $e->allowed('VIEW_CONTAINER', $owner->home_ou)
        );
    }

    $meth = 'search_' . $ctypes{$class} . '_item';
    my $contents = $e->$meth({bucket => $c_id});

    if ($self->{perms}) {
        $max = scalar(@$contents);
        $client->respond({ ord => $stage, max => $max, count => 0, stage => 'ITEM_PERM_CHECK' });
        for my $item (@$contents) {
            $count++;
            $meth = 'retrieve_' . $itypes{$class};
            my $field = 'target_'.$ttypes{$class};
            my $obj = $e->$meth($item->$field);

            for my $perm_field (keys %{$self->{perms}}) {
                my $perm_def = $self->{perms}->{$perm_field};
                my ($pwhat,$pwhere) = ([split ' ', $perm_def], $perm_field);
                for my $p (@$pwhat) {
                    $e->allowed($p, $obj->$pwhere) or return $e->die_event;
                }
            }
            $client->respond({ ord => $stage, max => $max, count => $count, stage => 'ITEM_PERM_CHECK' });
        }
        $stage++;
    }

    my @users = map { $_->target_user } @$contents;
    $max = scalar(@users) * scalar(@{$changes->{remove}});
    $count = 0;
    $client->respond({ ord => $stage, max => $max, count => $count, stage => 'STAT_CAT_REMOVE' });

    my $chunk = int($max / 10) || 1;
    my $to_remove = $e->search_actor_stat_cat_entry_user_map({ target_usr => \@users, stat_cat => $changes->{remove} });
    for my $t (@$to_remove) {
        $e->delete_actor_stat_cat_entry_user_map($t);
        $count++;
        $client->respond({ ord => $stage, max => $max, count => $count, stage => 'STAT_CAT_REMOVE' })
            unless ($count % $chunk);
    }

    $stage++;

    $max = scalar(@users) * scalar(keys %{$changes->{apply}});
    $count = 0;
    $client->respond({ ord => $stage, max => $max, count => $count, stage => 'STAT_CAT_APPLY' });

    $chunk = int($max / 10) || 1;
    for my $item (@$contents) {
        for my $astatcat (keys %{$changes->{apply}}) {
            my $new_value = $changes->{apply}->{$astatcat};
            my $to_change = $e->search_actor_stat_cat_entry_user_map({ target_usr => $item->target_user, stat_cat => $astatcat });
            if (@$to_change) {
                $to_change = $$to_change[0];
                $to_change->stat_cat_entry($new_value);
                $e->update_actor_stat_cat_entry_user_map($to_change);
            } else {
                $to_change = new Fieldmapper::actor::stat_cat_entry_user_map;
                $to_change->stat_cat_entry($new_value);
                $to_change->stat_cat($astatcat);
                $to_change->target_usr($item->target_user);
                $e->create_actor_stat_cat_entry_user_map($to_change);
            }
            $count++;
            $client->respond({ ord => $stage, max => $max, count => $count, stage => 'STAT_CAT_APPLY' })
                unless ($count % $chunk);
        }
    }

    $e->commit;

    return { stage => 'COMPLETE' };
}

__PACKAGE__->register_method(
    method  => "batch_statcat_apply",
    api_name    => "open-ils.actor.container.user.batch_statcat_apply",
    ctype       => 'user',
    perms       => {
            home_ou     => 'UPDATE_USER', # field -> perm means "test this perm with field as context OU", both old and new
    },
    fields      => [ qw/active profile juvenile home_ou expire_date barred net_access_level/ ],
    signature => {
        desc => 'Edits allowed fields on users in a bucket',
        params => [{
            desc => 'Session key', type => 'string',
            desc => 'User container id',
            desc => 'Hash of statcats to apply or remove', type => 'hash',
        }],
        return => {
            desc => 'Object with the structure { stage => "stage string", max => max_for_stage, count => count_in_stage }',
            type => 'hash'
        }
    }
);


sub apply_rollback {
    my $self = shift;
    my $client = shift;
    my $ses = shift;
    my $c_id = shift;
    my $main_fsg = shift;

    my $max = 0;
    my $count = 0;
    my $stage = 0;

    my $class = $self->{ctype} or return undef;

    my $e = new_editor(xact=>1, authtoken=>$ses);
    return $e->die_event unless $e->checkauth;

    for my $bp (@{$batch_perm{$class}}) {
        return { stage => 'COMPLETE' } unless $e->allowed($bp);
    }

    $client->respond({ ord => $stage++, stage => 'CONTAINER_BATCH_UPDATE_PERM_CHECK' });
    return $e->die_event unless $e->allowed('CONTAINER_BATCH_UPDATE');

    my $meth = 'retrieve_' . $ctypes{$class};
    my $bkt = $e->$meth($c_id) or return $e->die_event;

    unless($bkt->owner eq $e->requestor->id) {
        $client->respond({ ord => $stage++, stage => 'CONTAINER_PERM_CHECK' });
        my $owner = $e->retrieve_actor_user($bkt->owner)
            or return $e->die_event;
        return $e->die_event unless (
            $e->allowed('VIEW_CONTAINER', $bkt->owning_lib) || $e->allowed('VIEW_CONTAINER', $owner->home_ou)
        );
    }

    $main_fsg = $e->retrieve_action_fieldset_group($main_fsg);
    return { stage => 'COMPLETE', error => 'No field set group' } unless $main_fsg;

    my $rbg = $e->retrieve_action_fieldset_group($main_fsg->rollback_group);
    return { stage => 'COMPLETE', error => 'No rollback field set group' } unless $rbg;

    my $fieldsets = $e->search_action_fieldset({fieldset_group => $rbg->id});
    $max = scalar(@$fieldsets);

    $client->respond({ ord => $stage, max => $max, count => 0, stage => 'APPLY_EDITS' });
    for my $fs (@$fieldsets) {
        my $res = $e->json_query({
            from => ['action.apply_fieldset', $fs->id, $table{$class}, 'id', undef]
        })->[0]->{'action.apply_fieldset'};

        $client->respond({
            ord => $stage,
            max => $max,
            count => ++$count,
            stage => 'APPLY_EDITS',
            error => $res ? "Could not apply fieldset ".$fs->id.": $res" : undef
        });
    }

    $main_fsg->rollback_time('now');
    $e->update_action_fieldset_group($main_fsg);

    $e->commit;

    return { stage => 'COMPLETE' };
}
__PACKAGE__->register_method(
    method  => "apply_rollback",
    max_bundle_count => 1,
    api_name    => "open-ils.actor.container.user.apply_rollback",
    ctype       => 'user',
    signature => {
        desc => 'Applys rollback of a fieldset group to users in a bucket',
        params => [
            { desc => 'Session key', type => 'string' },
            { desc => 'User container id', type => 'number' },
            { desc => 'Main (non-rollback) fieldset group' },
        ],
        return => {
            desc => 'Object with the structure { fieldset_group => $id, stage => "COMPLETE", error => ("error string if any"|undef if none) }',
            type => 'hash'
        }
    }
);


sub batch_edit {
    my $self = shift;
    my $client = shift;
    my $ses = shift;
    my $c_id = shift;
    my $edit_name = shift;
    my $edits = shift;

    my $max = 0;
    my $count = 0;
    my $stage = 0;

    my $class = $self->{ctype} or return undef;

    my $e = new_editor(xact=>1, authtoken=>$ses);
    return $e->die_event unless $e->checkauth;

    for my $bp (@{$batch_perm{$class}}) {
        return { stage => 'COMPLETE' } unless $e->allowed($bp);
    }

    $client->respond({ ord => $stage++, stage => 'CONTAINER_BATCH_UPDATE_PERM_CHECK' });
    return $e->die_event unless $e->allowed('CONTAINER_BATCH_UPDATE');

    my $meth = 'retrieve_' . $ctypes{$class};
    my $bkt = $e->$meth($c_id) or return $e->die_event;

    unless($bkt->owner eq $e->requestor->id) {
        $client->respond({ ord => $stage++, stage => 'CONTAINER_PERM_CHECK' });
        my $owner = $e->retrieve_actor_user($bkt->owner)
            or return $e->die_event;
        return $e->die_event unless (
            $e->allowed('VIEW_CONTAINER', $bkt->owning_lib) || $e->allowed('VIEW_CONTAINER', $owner->home_ou)
        );
    }

    $meth = 'search_' . $ctypes{$class} . '_item';
    my $contents = $e->$meth({bucket => $c_id});

    $max = 0;
    $max = scalar(@$contents) if ($self->{perms});
    $max += scalar(@$contents) if ($self->{base_perm});

    my $obj_cache = {};
    if ($self->{base_perm}) {
        $client->respond({ ord => $stage, max => $max, count => $count, stage => 'ITEM_PERM_CHECK' });
        for my $item (@$contents) {
            $count++;
            $meth = 'retrieve_' . $itypes{$class};
            my $field = 'target_'.$ttypes{$class};
            my $obj = $$obj_cache{$item->$field} = $e->$meth($item->$field);

            for my $perm_field (keys %{$self->{base_perm}}) {
                my $perm_def = $self->{base_perm}->{$perm_field};
                my ($pwhat,$pwhere) = ([split ' ', $perm_def], $perm_field);
                for my $p (@$pwhat) {
                    $e->allowed($p, $obj->$pwhere) or return $e->die_event;
                    if ($$edits{$pwhere}) {
                        $e->allowed($p, $$edits{$pwhere}) or do {
                            $logger->warn("Cannot update $class ".$obj->id.", $pwhat at $pwhere not allowed.");
                            return $e->die_event;
                        };
                    }
                }
            }
            $client->respond({ ord => $stage, max => $max, count => $count, stage => 'ITEM_PERM_CHECK' });
        }
    }

    if ($self->{perms}) {
        $client->respond({ ord => $stage, max => $max, count => $count, stage => 'ITEM_PERM_CHECK' });
        for my $item (@$contents) {
            $count++;
            $meth = 'retrieve_' . $itypes{$class};
            my $field = 'target_'.$ttypes{$class};
            my $obj = $$obj_cache{$item->$field} || $e->$meth($item->$field);

            for my $perm_field (keys %{$self->{perms}}) {
                my $perm_def = $self->{perms}->{$perm_field};
                if (ref($perm_def) eq 'HASH') { # we care about specific values being set
                    for my $perm_value (keys %$perm_def) {
                        if (exists $$edits{$perm_field} && $$edits{$perm_field} eq $perm_value) { # check permission
                            while (my ($pwhat,$pwhere) = each %{$$perm_def{$perm_value}}) {
                                if ($pwhere eq '*') {
                                    $pwhere = undef;
                                } else {
                                    $pwhere = $obj->$pwhere;
                                }
                                $pwhat = [ split / /, $pwhat ];
                                for my $p (@$pwhat) {
                                    $e->allowed($p, $pwhere) or do {
                                        $pwhere ||= "everywhere";
                                        $logger->warn("Cannot update $class ".$obj->id.", $pwhat at $pwhere not allowed.");
                                        return $e->die_event;
                                    };
                                }
                            }
                        }
                    }
                } elsif (ref($perm_def) eq 'CODE') { # we need to run the code on old and new, and pass both tests
                    if (exists $$edits{$perm_field}) {
                        $perm_def->($e, $obj->$perm_field) or return $e->die_event;
                        $perm_def->($e, $$edits{$perm_field}) or return $e->die_event;
                    }
                } else { # we're checking an ou field
                    my ($pwhat,$pwhere) = ([split ' ', $perm_def], $perm_field);
                    if ($$edits{$pwhere}) {
                        for my $p (@$pwhat) {
                            $e->allowed($p, $obj->$pwhere) or return $e->die_event;
                            $e->allowed($p, $$edits{$pwhere}) or do {
                                $logger->warn("Cannot update $class ".$obj->id.", $pwhat at $pwhere not allowed.");
                                return $e->die_event;
                            };
                        }
                    }
                }
            }
            $client->respond({ ord => $stage, max => $max, count => $count, stage => 'ITEM_PERM_CHECK' });
        }
        $stage++;
    }

    $client->respond({ ord => $stage++, stage => 'FIELDSET_GROUP_CREATE' });
    my $fsgroup = Fieldmapper::action::fieldset_group->new;
    $fsgroup->isnew(1);
    $fsgroup->name($edit_name);
    $fsgroup->creator($e->requestor->id);
    $fsgroup->owning_lib($e->requestor->ws_ou);
    $fsgroup->container($c_id);
    $fsgroup->container_type($ttypes{$class});
    $fsgroup = $e->create_action_fieldset_group($fsgroup);

    $client->respond({ ord => $stage++, stage => 'FIELDSET_CREATE' });
    my $fieldset = Fieldmapper::action::fieldset->new;
    $fieldset->isnew(1);
    $fieldset->fieldset_group($fsgroup->id);
    $fieldset->owner($e->requestor->id);
    $fieldset->owning_lib($e->requestor->ws_ou);
    $fieldset->status('PENDING');
    $fieldset->classname($htypes{$class});
    $fieldset->name($edit_name . ' batch group fieldset');
    $fieldset->stored_query($qtypes{$class});
    $fieldset = $e->create_action_fieldset($fieldset);

    my @keys = keys %$edits;
    $max = scalar(@keys);
    $count = 0;
    $client->respond({ ord => $stage, count=> $count, max => $max, stage => 'FIELDSET_EDITS_CREATE' });
    for my $key (@keys) {
        if ($self->{fields}) { # restrict edits to registered fields
            next unless (grep { $_ eq $key } @{$self->{fields}});
        }
        my $fs_cv = Fieldmapper::action::fieldset_col_val->new;
        $fs_cv->isnew(1);
        $fs_cv->fieldset($fieldset->id);
        $fs_cv->col($key);
        $fs_cv->val($$edits{$key});
        $e->create_action_fieldset_col_val($fs_cv);
        $count++;
        $client->respond({ ord => $stage, count=> $count, max => $max, stage => 'FIELDSET_EDITS_CREATE' });
    }

    $client->respond({ ord => ++$stage, stage => 'CONSTRUCT_QUERY' });
    my $qstore = OpenSRF::AppSession->connect('open-ils.qstore');
    my $prep = $qstore->request('open-ils.qstore.prepare', $fieldset->stored_query)->gather(1);
    my $token = $prep->{token};
    $qstore->request('open-ils.qstore.bind_param', $token, {bucket => $c_id})->gather(1);
    my $sql = $qstore->request('open-ils.qstore.sql', $token)->gather(1);
    $sql =~ s/\n\s*/ /g; # normalize the string
    $sql =~ s/;\s*//g; # kill trailing semicolon

    $client->respond({ ord => ++$stage, stage => 'APPLY_EDITS' });
    my $res = $e->json_query({
        from => ['action.apply_fieldset', $fieldset->id, $table{$class}, 'id', $sql]
    })->[0]->{'action.apply_fieldset'};

    $e->commit;
    $qstore->disconnect;

    return { fieldset_group => $fsgroup->id, stage => 'COMPLETE', error => $res };
}

__PACKAGE__->register_method(
    method  => "batch_edit",
    max_bundle_count => 1,
    api_name    => "open-ils.actor.container.user.batch_edit",
    ctype       => 'user',
    base_perm   => { home_ou => 'UPDATE_USER' },
    perms       => {
            profile => sub {
                my ($e, $group) = @_;
                my $g = $e->retrieve_permission_grp_tree($group);
                if (my $p = $g->application_perm()) {
                    return $e->allowed($p);
                }
                return 1;
            }, # code ref is run with params (editor,value), for both old and new value
            # home_ou => 'UPDATE_USER', # field -> perm means "test this perm with field as context OU", both old and new
            barred  => {
                    t => { BAR_PATRON => 'home_ou' },
                    f => { UNBAR_PATRON => 'home_ou' }
            } # field -> struct means "if field getting value "key" check -> perm -> at context org, both old and new
    },
    fields      => [ qw/active profile juvenile home_ou expire_date barred net_access_level/ ],
    signature => {
        desc => 'Edits allowed fields on users in a bucket',
        params => [
            { desc => 'Session key', type => 'string' },
            { desc => 'User container id', type => 'number' },
            { desc => 'Batch edit name', type => 'string' },
            { desc => 'Edit hash, key is column, value is new value to apply', type => 'hash' },
        ],
        return => {
            desc => 'Object with the structure { fieldset_group => $id, stage => "COMPLETE", error => ("error string if any"|undef if none) }',
            type => 'hash'
        }
    }
);

__PACKAGE__->register_method(
    method  => "batch_edit",
    api_name    => "open-ils.actor.container.user.batch_delete",
    ctype       => 'user',
    perms       => {
            deleted => {
                    t => { 'DELETE_USER UPDATE_USER' => 'home_ou' },
                    f => { 'UPDATE_USER' => 'home_ou' }
            }
    },
    fields      => [ qw/deleted/ ],
    signature => {
        desc => 'Deletes users in a bucket',
        params => [{
            { desc => 'Session key', type => 'string' },
            { desc => 'User container id', type => 'number' },
            { desc => 'Batch delete name', type => 'string' },
            { desc => 'Edit delete, key is "deleted", value is new value to apply ("t")', type => 'hash' },
            
        }],
        return => {
            desc => 'Object with the structure { fieldset_group => $id, stage => "COMPLETE", error => ("error string if any"|undef if none) }',
            type => 'hash'
        }
    }
);



1;


