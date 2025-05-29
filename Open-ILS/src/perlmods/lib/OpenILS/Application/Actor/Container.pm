package OpenILS::Application::Actor::Container;
use base 'OpenILS::Application';
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Perm;
use OpenSRF::EX qw(:try);
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Cache;
use Digest::MD5 qw(md5_hex);
use OpenSRF::Utils::JSON;

my $apputils = "OpenILS::Application::AppUtils";
my $U = $apputils;
my $conf;
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
my %jtypes;
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

$jtypes{'biblio'} = "cbreb";
#$jtypes{'callnumber'} = "ccnb";
#$jtypes{'copy'} = "ccb";
#$jtypes{'user'} = "cub";

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
    method  => "get_bucket_ids_shared_with_others",
    api_name    => "open-ils.actor.container.retrieve_biblio_record_entry_buckets_shared_with_others",
    signature => {
        desc => q/
            Returns a list of the user's record buckets that are shared with other orgs and users.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
        ],
        return => {
            desc => 'An array of bucket IDs for record buckets that are shared with other orgs and users.'
        }
    }
);
__PACKAGE__->register_method(
    method  => "get_bucket_ids_shared_with_others",
    api_name    => "open-ils.actor.container.retrieve_biblio_record_entry_buckets_shared_with_others.count"
);

__PACKAGE__->register_method(
    method  => "get_bucket_ids_shared_with_user",
    api_name    => "open-ils.actor.container.retrieve_biblio_record_entry_buckets_shared_with_user",
    signature => {
        desc => q/
            Returns a list of record buckets being shared with the requestor, either directly or indirectly.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
        ],
        return => {
            desc => 'An array of bucket IDs for buckets being shared with requestor, either directly or indirectly.'
        }
    }
);
__PACKAGE__->register_method(
    method  => "get_bucket_ids_shared_with_user",
    api_name    => "open-ils.actor.container.retrieve_biblio_record_entry_buckets_shared_with_user.count"
);

sub get_bucket_ids_shared_with_others {
    my ($self, $client, $authtoken) = @_;
    my $e = new_editor(authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    # No need for further perm checking, we're dealing with one's own bucket shares

    my $bucket_retrieve_method;
    my $bucket_org_share_retrieve_method;
    my $bucket_user_share_retrieve_method;
    my $object_class_for_user_object_perms;
    if ($self->api_name =~ 'biblio_record_entry') {
        $bucket_retrieve_method = 'search_container_biblio_record_entry_bucket';
        $bucket_org_share_retrieve_method = 'search_container_biblio_record_entry_bucket_shares';
        $bucket_user_share_retrieve_method = 'search_permission_usr_object_perm_map';
        $object_class_for_user_object_perms = 'cbreb';
    }

    my $view_container_perm = $e->search_permission_perm_list({code => "VIEW_CONTAINER"})->[0]->id;

    my $user_id = $e->requestor->id;

    # First, get all buckets owned by the user
    my $user_buckets = $e->$bucket_retrieve_method({owner => $user_id});

    # Now, get all share mappings for these buckets
    my $bucket_ids = [map { $_->id } @$user_buckets];
    my $org_share_mappings = $e->$bucket_org_share_retrieve_method({bucket => $bucket_ids});
    my $user_share_mappings = $e->$bucket_user_share_retrieve_method({
        perm => $view_container_perm,
        object_type => $object_class_for_user_object_perms,
        object_id => $bucket_ids
    });

    #use Data::Dumper;
    #$logger->warn('org_share_mappings, dumper: ' . Dumper($org_share_mappings) );
    #$logger->warn('user_share_mappings, dumper: ' . Dumper($user_share_mappings) );

    # Create a hash of bucket IDs that have shares
    my %shared_bucket_ids = ();
    if ($org_share_mappings && ref($org_share_mappings) eq 'ARRAY') {
        foreach my $m (@$org_share_mappings) {
            $shared_bucket_ids{ $m->bucket } = 1;
        }
    }
    if ($user_share_mappings && ref($user_share_mappings) eq 'ARRAY') {
        foreach my $m (@$user_share_mappings) {
            $shared_bucket_ids{ $m->object_id } = 1;
        }
    }

    # Filter the user's buckets to only those that are shared
    my @shared_bucket_ids = keys %shared_bucket_ids;

    my $results = [keys %shared_bucket_ids];
    if ($self->api_name =~ 'count') {
        return scalar(@$results);
    } else { 
        return $results;
    }
}

sub get_bucket_ids_shared_with_user {
    my ($self, $client, $authtoken) = @_;
    my $e = new_editor(authtoken => $authtoken);
    return $e->die_event unless $e->checkauth;

    # We may want to make an optional argument for this
    # but if we do, remember to change ->home_ou
    # No need for perm checking unless we do that.
    my $user_id = $e->requestor->id;

    # Get user's working locations and home org.
    # We don't usually merge home libs with working locations, so...
    # TODO: sanity check this, re: staff versus patrons
    my $work_ous = $U->get_user_work_ou_ids($e, $user_id);
    my $home_ou = $e->requestor->home_ou;
    my @user_ous = ($home_ou, @$work_ous);

    # Merging all full paths, going with inheritance
    my $all_ou_ids = [];
    for my $ou_id (@user_ous) {
        push @$all_ou_ids, @{$U->get_org_full_path($ou_id)};
    }
    # Remove duplicates
    my %ou_ids_uniq = map { $_ => 1 } @$all_ou_ids;
    $all_ou_ids = [keys %ou_ids_uniq];

    my $json_query;
    my $bucket_user_share_retrieve_method;
    my $object_class_for_user_object_perms;
    if ($self->api_name =~ 'biblio_record_entry') {
        $json_query = {
            select => { cbrebs => ['bucket'], cbreb => ['id'] },
            from => { cbrebs => { cbreb => { type => 'inner' } } },
            where => { '+cbrebs' => { share_org => $all_ou_ids },
                '+cbreb' => { owner => { '!=' => $user_id } } },
            distinct => 1
        };
        $bucket_user_share_retrieve_method = 'search_permission_usr_object_perm_map';
        $object_class_for_user_object_perms = 'cbreb';
    }

    # Get buckets shared with any of these orgs not owned by user
    my $org_share_mappings = $e->json_query($json_query);
    # Buckets being shared directly with the user
    my $user_share_mappings = $e->$bucket_user_share_retrieve_method({
        perm => $e->search_permission_perm_list({code => "VIEW_CONTAINER"})->[0]->id,
        object_type => $object_class_for_user_object_perms,
        usr => $user_id
    });

    #use Data::Dumper;
    #$logger->warn('org_share_mappings, dumper: ' . Dumper($org_share_mappings) );
    #$logger->warn('user_share_mappings, dumper: ' . Dumper($user_share_mappings) );

    # Create a hash of bucket IDs that have shares
    my %shared_bucket_ids = ();
    if ($org_share_mappings && ref($org_share_mappings) eq 'ARRAY') {
        foreach my $m (@$org_share_mappings) {
            $shared_bucket_ids{ $m->{bucket} } = 1;
        }
    }
    if ($user_share_mappings && ref($user_share_mappings) eq 'ARRAY') {
        foreach my $m (@$user_share_mappings) {
            $shared_bucket_ids{ $m->object_id } = 1;
        }
    }

    my @bucket_ids = keys %shared_bucket_ids;

    my $results = \@bucket_ids;
    if ($self->api_name =~ 'count') {
        return scalar(@$results);
    } else { 
        return $results;
    }
}

__PACKAGE__->register_method(
    method  => "pcrud_count",
    api_name    => "open-ils.actor.count_with_pcrud", # TODO: should build pcrud.count instead, but expedient
    authoritative => 1,
    signature => {
        desc => q/
            Take a class hint and pcrud query and return the count of results. No options.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Class hint', type => 'string'},
            {desc => 'Query', type => 'hash'},
        ],
        return => {
            desc => 'Returns a count or an exception.'
        }
    }
);

#sub pcrud_count {
#    my ($self, $client, $authtoken, $hint, $query) = @_;
#    my $e = new_editor(authtoken => $authtoken);
#    return $e->event unless $e->checkauth;
#
#    my $search = "search_" . Fieldmapper->class_for_hint($hint);
#    $search =~ s/::/_/g;
#
#    my $ids = $e->$search($query, { 'id_list' => 1 });
#
#    return scalar(@$ids);
#}

sub pcrud_count {
    my ($self, $client, $authtoken, $hint, $query) = @_;

    # overkill coming

    return OpenILS::Event->new('BAD_PARAMS')
        unless defined($authtoken) && defined($hint) && defined($query);

    return OpenILS::Event->new('BAD_PARAMS')
        unless ref($query) eq 'HASH';

    my $e = new_editor(authtoken => $authtoken);
    return $e->event unless $e->checkauth;

    $e->personality('open-ils.pcrud');

    #if(!$conf) {
    #    $conf = OpenSRF::Utils::SettingsClient->new;
    #    my $idl = OpenSRF::Utils::SettingsClient->new->config_value("IDL");
    #    Fieldmapper->import(IDL => $idl);
    #}
    #
    #my $class = Fieldmapper->class_for_hint($hint);

    # Having trouble with generalizing the method, so special coding cbreb and friends for now

    my $class;
    if ($hint eq 'cbreb') {
        $class = "container::biblio_record_entry_bucket";
    } elsif ($hint eq 'cbrebuf') {
        $class = "container::biblio_record_entry_bucket_usr_flag";
    } elsif ($hint eq 'cbrebs') {
        $class = "container::biblio_record_entry_bucket_shares";
    } elsif ($hint eq 'cbrebi') {
        $class = "container::biblio_record_entry_bucket_item";
    }

    return OpenILS::Event->new('BAD_PARAMS', note => "Invalid class hint: $hint")
        unless $class;

    my $search = "search_" . $class;
    $search =~ s/::/_/g;

    unless ($e->can($search)) {
        return OpenILS::Event->new('INTERNAL_SERVER_ERROR', 
            note => "Method $search not found");
    }

    my $ids;
    eval {
        $ids = $e->$search($query, { 'id_list' => 1, 'atomic' => 1 });
    };

    if ($@) {
        return OpenILS::Event->new('INTERNAL_SERVER_ERROR', 
            note => "Error in search: $@");
    }

    unless (defined $ids && ref($ids) eq 'ARRAY') {
        return OpenILS::Event->new('INTERNAL_SERVER_ERROR', 
            note => "Unexpected result from search");
    }

    return scalar(@$ids);
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
            return $e->event unless (
                $e->allowed('VIEW_CONTAINER', $owner->home_ou) or
                $e->allowed('VIEW_CONTAINER', $bkt->owning_lib)
            );
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


for my $btype (keys %jtypes) {
    __PACKAGE__->register_method(
        method   => "bucket_count_stats",
        api_name => "open-ils.actor.container.$ttypes{$btype}.count_stats",
        authoritative => 1,
        btype    => $btype
    );
}
sub bucket_count_stats {
    my($self, $conn, $auth, $ids) = @_;
    $ids = [$ids] unless ref($ids);
    my $class = $self->{btype};
    return undef unless $jtypes{$class} and @$ids;
    my $e = new_editor(authtoken => $auth);
    return $e->die_event unless $e->checkauth;
    my $icore = $jtypes{$class}.'i';
    my $score = $jtypes{$class}.'s';
    my %icounts = ();
    my %org_shares = ();
    my %view_user_shares = ();
    my %update_user_shares = ();

    my $iquery_result = $e->json_query({
        select => {$icore => [
            { column => 'bucket', alias  => 'id' },
            { column => 'id',     alias => 'count',
              transform => 'count', aggregate => 1 }
        ]},
        from => $icore,
        where => {bucket => $ids}
    });
    if ($iquery_result && ref($iquery_result) eq 'ARRAY') {
        %icounts = map { $_->{id} => $_->{count} } @$iquery_result;
    } else {
        $logger->warn("No results or error in item count query for $class");
    }

    my $org_query_result = $e->json_query({
        select => {$score => [
            { column => 'bucket', alias  => 'id' },
            { column => 'id',     alias => 'count',
              transform => 'count', aggregate => 1 }
        ]},
        from => $score,
        where => {bucket => $ids}
    });
    if ($org_query_result && ref($org_query_result) eq 'ARRAY') {
        %org_shares = map { $_->{id} => $_->{count} } @$org_query_result;
    } else {
        $logger->warn("No results or error in org share count query for $class");
    }

    my $view_perm_id = $e->search_permission_perm_list({code=>'VIEW_CONTAINER'})->[0]->id;
    my $update_perm_id = $e->search_permission_perm_list({code=>'UPDATE_CONTAINER'})->[0]->id;

    my $user_query_result = $e->json_query({
        select => {puopm => [
            { column => 'object_id', alias  => 'id' },
            { column => 'perm',      alias  => 'perm' },
            { column => 'usr',       alias => 'count',
              transform => 'count', aggregate => 1,
              distinct => 1}
        ]},
        from => puopm => where => {
            object_type => $jtypes{$class},
            object_id => $ids,
            perm => [$view_perm_id, $update_perm_id]
        }
    });
    if ($user_query_result && ref($user_query_result) eq 'ARRAY') {
        for my $result (@$user_query_result) {
            if ($result->{perm} == $view_perm_id) {
                $view_user_shares{$result->{id}} = $result->{count};
            } elsif ($result->{perm} == $update_perm_id) {
                $update_user_shares{$result->{id}} = $result->{count};
            }
        }
    } else {
        $logger->warn("No results or error in user share count query for $class");
    }

    return { map {
        $_ => {
            item_count => $icounts{$_} || 0,
            org_share_count => $org_shares{$_} || 0,
            usr_view_share_count => $view_user_shares{$_} || 0,
            usr_update_share_count => $update_user_shares{$_} || 0
        }
    } @$ids };
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

    $userid = $staff->id unless $userid;

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
    method  => "update_record_bucket_org_share_mapping",
    api_name    => "open-ils.actor.container.update_record_bucket_org_share_mapping",
    signature => {
        desc => q/
            Sets the org share mappings for the specified bucket and org ids.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Record bucket Ids to work with.', type => 'array'},
            {desc => 'Org Ids to share with.', type => 'array'},
        ],
        return => {
            desc => '1 for success, otherwise exception'
        }
    }
);

sub update_record_bucket_org_share_mapping {
    my( $self, $client, $authtoken, $bucket_ids, $org_ids ) = @_;
    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->die_event unless $e->checkauth;

    my $bucket_retrieve_method;
    my $bucket_share_retrieve_method;
    my $bucket_share_delete_method;
    my $bucket_share_create_method;
    my $share_perm;
    my $fm_type;

    if ($self->api_name =~ 'update_record_bucket_org_share_mapping') {
        $bucket_retrieve_method = 'search_container_biblio_record_entry_bucket';
        $bucket_share_retrieve_method = 'search_container_biblio_record_entry_bucket_shares';
        $bucket_share_delete_method = 'delete_container_biblio_record_entry_bucket_shares';
        $bucket_share_create_method = 'create_container_biblio_record_entry_bucket_shares';
        $share_perm = 'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_ORG_SHARE';
        $fm_type = 'Fieldmapper::container::biblio_record_entry_bucket_shares';
    }

    # Fetch buckets
    my $buckets = $e->$bucket_retrieve_method( { id => $bucket_ids } );

    # Test permission against all buckets 
    for my $bucket (@$buckets) {
        if ($bucket->owner ne $e->requestor->id) {
            if ($bucket->owning_lib) {
                return $e->die_event unless $e->allowed($share_perm, $bucket->owning_lib);
            } else {
                return $e->die_event unless $e->allowed($share_perm, $e->requestor->home_ou);
            }
        }
    }

    # Create desired mappings
    my $desired_maps = [];
    for my $bucket_id (@$bucket_ids) {
        for my $org_id (@$org_ids) {
            push @$desired_maps, { bucket => $bucket_id, share_org => $org_id };
        }
    }

    # Fetch existing mappings from _shares table
    my $existing_maps = $e->$bucket_share_retrieve_method( { bucket => $bucket_ids } );

    # Where existing rows not in desired rows, delete those
    my $maps_to_delete = [];
    for my $existing_map (@$existing_maps) {
        unless (grep { $_->{bucket} == $existing_map->bucket && $_->{share_org} == $existing_map->share_org } @$desired_maps) {
            push @$maps_to_delete, $existing_map;
        }
    }

    for my $map (@$maps_to_delete) {
        return $e->die_event unless $e->$bucket_share_delete_method($map);
    }

    # Where desired rows not in existing rows, create those
    my $needed_maps = [];
    for my $desired_map (@$desired_maps) {
        unless (grep { $_->bucket == $desired_map->{bucket} && $_->share_org == $desired_map->{share_org} } @$existing_maps) {
            push @$needed_maps, $desired_map;
        }
    }

    for my $map (@$needed_maps) {
        my $obj = $fm_type->new;
        $obj->bucket($map->{bucket});
        $obj->share_org($map->{share_org});
        return $e->die_event unless $e->$bucket_share_create_method($obj);
    }

    return $e->die_event unless $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method  => "retrieve_org_ids_from_record_bucket_org_share_mapping",
    api_name    => "open-ils.actor.container.retrieve_record_bucket_shared_org_ids",
    signature => {
        desc => q/
            Retrieves org ids for the set of orgs referenced in org share mappings for the specified buckets.
        /,
        params => [
            {desc => 'Authentication token', type => 'string'},
            {desc => 'Record bucket Ids to work with.', type => 'array'},
        ],
        return => {
            desc => 'An array of org ids, otherwise exception'
        }
    }
);

sub retrieve_org_ids_from_record_bucket_org_share_mapping {
    my( $self, $client, $authtoken, $bucket_ids ) = @_;
    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->die_event unless $e->checkauth;

    my $bucket_share_retrieve_method;
    if ($self->api_name =~ 'retrieve_record_bucket_shared_org_ids') {
        $bucket_share_retrieve_method = 'search_container_biblio_record_entry_bucket_shares';
    }

    # Fetch mappings shares table
    my $maps = $e->$bucket_share_retrieve_method( { bucket => $bucket_ids } );

    # Getting our set of org ids
    my %ou_ids_uniq = map { $_->share_org => 1 } @$maps;
    return [keys %ou_ids_uniq];
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
            {desc => 'Duplicate check.  Avoid adding an item that is already in a container', type => 'bool'},
        ],
        return => {
            desc => 'The ID of the newly created item(s).  In batch context, an array of IDs is returned'
        }
    }
);


sub item_create {
    my( $self, $client, $authtoken, $class, $item, $dupe_check ) = @_;

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
            next if (
                $dupe_check &&
                $e->search_container_copy_bucket_item(
                    {bucket => $one_item->bucket, target_copy => $one_item->target_copy}
                )->[0]
            );
            return $e->die_event unless
                $stat = $e->create_container_copy_bucket_item($one_item);
        }

        if( $class eq 'callnumber' ) {
            next if (
                $dupe_check &&
                $e->search_container_call_number_bucket_item(
                    {bucket => $one_item->bucket, target_call_number => $one_item->target_call_number}
                )->[0]
            );
            return $e->die_event unless
                $stat = $e->create_container_call_number_bucket_item($one_item);
        }

        if( $class eq 'biblio' ) {
            next if (
                $dupe_check &&
                $e->search_container_biblio_record_entry_bucket_item(
                    {bucket => $one_item->bucket, target_biblio_record_entry => $one_item->target_biblio_record_entry}
                )->[0]
            );
            return $e->die_event unless
                $stat = $e->create_container_biblio_record_entry_bucket_item($one_item);
        }

        if( $class eq 'user') {
            next if (
                $dupe_check &&
                $e->search_container_user_bucket_item(
                    {bucket => $one_item->bucket, target_user => $one_item->target_user}
                )->[0]
            );
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
    method  => 'batch_add_items',
    api_name    => 'open-ils.actor.container.item.create.batch',
    stream      => 1,
    max_bundle_count => 1,
    signature => {
        desc => 'Add items to a bucket',
        params => [
            {desc => 'Auth token', type => 'string'},
            {desc => q/
                Container class.  
                Can be "copy", "call_number", "biblio_record_entry", or "user"'/,
                type => 'string'},
            {desc => 'Bucket ID', type => 'number'},
            {desc => q/
                Item target identifiers.  E.g. for record buckets,
                the identifier would be the bib record id/, 
                type => 'array'
            },
        ],
        return => {
            desc => 'Stream of new item Identifiers',
            type => 'number'
        }
    }
);

sub batch_add_items {
    my ($self, $client, $auth, $bucket_class, $bucket_id, $target_ids) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $constructor = "Fieldmapper::container::${bucket_class}_bucket_item";
    my $create = "create_container_${bucket_class}_bucket_item";
    my $retrieve = "retrieve_container_${bucket_class}_bucket";
    my $column = "target_${bucket_class}";

    my $bucket = $e->$retrieve($bucket_id) or return $e->die_event;

    if ($bucket->owner ne $e->requestor->id) {
        return $e->die_event unless $e->allowed('CREATE_CONTAINER_ITEM');
    }

    for my $target_id (@$target_ids) {

        my $item = $constructor->new;
        $item->bucket($bucket_id);
        $item->$column($target_id);

        return $e->die_event unless $e->$create($item);
        $client->respond($target_id);
    }

    $e->commit;
    return undef;
}

__PACKAGE__->register_method(
    method  => 'batch_delete_items',
    api_name    => 'open-ils.actor.container.item.delete.batch',
    stream      => 1,
    max_bundle_count => 1,
    signature => {
        desc => 'Remove items from a bucket',
        params => [
            {desc => 'Auth token', type => 'string'},
            {desc => q/
                Container class.  
                Can be "copy", "call_number", "biblio_record_entry", or "user"'/,
                type => 'string'},
            {desc => q/
                Item target identifiers.  E.g. for record buckets,
                the identifier would be the bib record id/, 
                type => 'array'
            }
        ],
        return => {
            desc => 'Stream of new removed target IDs',
            type => 'number'
        }
    }
);

sub batch_delete_items {
    my ($self, $client, $auth, $bucket_class, $bucket_id, $target_ids) = @_;

    my $e = new_editor(authtoken => $auth, xact => 1);
    return $e->die_event unless $e->checkauth;

    my $delete = "delete_container_${bucket_class}_bucket_item";
    my $search = "search_container_${bucket_class}_bucket_item";
    my $retrieve = "retrieve_container_${bucket_class}_bucket";
    my $column = "target_${bucket_class}";

    my $bucket = $e->$retrieve($bucket_id) or return $e->die_event;

    if ($bucket->owner ne $e->requestor->id) {
        return $e->die_event unless $e->allowed('DELETE_CONTAINER_ITEM');
    }

    for my $target_id (@$target_ids) {

        my $item = $e->$search({bucket => $bucket_id, $column => $target_id})->[0];
        next unless $item;

        return $e->die_event unless $e->$delete($item);
        $client->respond($target_id);
    }

    $e->commit;
    return undef;
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
    method      => 'containers_batch_full_delete',
    api_name        => 'open-ils.actor.containers.full_delete',
    signature   => q/
        Completely removes the given containers, including content.
        @param authtoken The login session key
        @param class The container class
        @param An array of container ids
        @return Returns a hash of container ids, with the
                corresponding values being either true for
                success, 0 for no deletion, or an error Event
        /
);

__PACKAGE__->register_method(
    method      => 'containers_batch_full_delete',
    api_name        => 'open-ils.actor.containers.full_delete.override',
    signature   => q/
        Completely removes the given containers, including content and carousels.
        @param authtoken The login session key
        @param class The container class
        @param An array of container ids
        @return Returns a hash of container ids, with the
                corresponding values being either true for
                success, 0 for no deletion, or an error Event
        /
);

sub containers_batch_full_delete {
    my ($self, $conn, $authtoken, $class, $container_ids) = @_;

    my $method_name = 'open-ils.actor.container.full_delete';
    $method_name .= '.override' if ($self->api_name =~ /override/);

    my %results;
    for my $container_id (@$container_ids) {
        my $delete_method = $self->method_lookup($method_name);
        my ($result) = $delete_method->run($authtoken, $class, $container_id);
        $results{$container_id} = $result;
    }

    return \%results;
}

__PACKAGE__->register_method(
    method  => 'full_delete',
    api_name    => 'open-ils.actor.container.full_delete',
    notes       => "Complety removes a container including all attached items",
);  

__PACKAGE__->register_method(
    method  => 'full_delete',
    api_name    => 'open-ils.actor.container.full_delete.override',
    notes       => "Complety removes a container including all attached items, and any linked carousel.",
);  

sub full_delete {
    my( $self, $client, $authtoken, $class, $containerId ) = @_;
    my( $container, $evt);

    my $override = 0;
    $override = 1 if ($self->api_name =~ /override/);

    my $e = new_editor(xact=>1, authtoken=>$authtoken);
    return $e->event unless $e->checkauth;

    ( $container, $evt ) = $apputils->fetch_container_e($e, $containerId, $class);
    return $evt if $evt;

    my $owner;
    if( $container->owner ne $e->requestor->id ) {
        $owner = $e->retrieve_actor_user($container->owner)
            or return $e->die_event;
        return $e->event unless $e->allowed('DELETE_CONTAINER', $owner->home_ou);
    }

    my $items; my $carousels = [];

    my @s = ({bucket => $containerId}, {idlist=>1});

    if( $class eq 'copy' ) {
        $items = $e->search_container_copy_bucket_item(@s);
    }

    if( $class eq 'callnumber' ) {
        $items = $e->search_container_call_number_bucket_item(@s);
    }

    if( $class eq 'biblio' ) {
        $carousels = $e->search_container_carousel(@s); # same query
        $items = $e->search_container_biblio_record_entry_bucket_item(@s);
    }

    if( $class eq 'user') {
        $items = $e->search_container_user_bucket_item(@s);
    }

    if (@$carousels) {
        return OpenILS::Event->new('BUCKET_LINKED_TO_CAROUSEL') unless $override;
        # FIXME: move to pcrud personality so we can test the configured permission against the actual carousel owner
        if( $container->owner ne $e->requestor->id ) {
            return $e->event unless $e->allowed('ADMIN_CAROUSEL', $owner->home_ou);
        }
    }

    foreach (@$carousels) {
        return $e->event unless $e->delete_container_carousel( $e->retrieve_container_carousel($_) );
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
    method      => 'containers_batch_update',
    api_name        => 'open-ils.actor.containers.update',
    signature   => q/
        Updates the given containers.
        @param authtoken The login session key
        @param class The container class
        @param An array of containers
        @return Returns a hash of container ids, with the
                corresponding values being either true for
                success, 0 for no update, or an error Event
        /
);

__PACKAGE__->register_method(
    method      => 'container_update',
    api_name        => 'open-ils.actor.container.update',
    signature   => q/
        Updates the given container.
        @param authtoken The login session key
        @param class The container class
        @param container The container item
        @return true on success, 0 on no update, Event on error
        /
);

sub containers_batch_update {
    my ($self, $conn, $authtoken, $class, $containers) = @_;

    my %results;
    for my $container (@$containers) {
        my $update_method = $self->method_lookup('open-ils.actor.container.update');
        my ($result) = $update_method->run($authtoken, $class, $container);
        $results{$container->id} = $result;
    }

    return \%results;
}

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
    method      => 'containers_transfer',
    api_name        => 'open-ils.actor.containers.transfer',
    signature   => q/
        Updates the owner for the specified container containers.
        @param authtoken The login session key
        @param user The destination user ID
        @param class The container class
        @param containers An array of container IDs
        @return Returns a hash of container ids, with the
                corresponding values being either true for
                success, 0 for no update, or an error Event
        /
);

sub containers_transfer {
    my ($self, $conn, $authtoken, $target_user_id, $class, $container_ids) = @_;
    my $e = new_editor(authtoken=>$authtoken);
    return $e->event unless $e->checkauth;

    my $usr_home_ou_map = {};
    my $get_cached_home_ou = sub {
        my $usr_id = shift;
        unless (exists $usr_home_ou_map->{$usr_id}) {
            my $usr = $e->retrieve_actor_user($usr_id)
                or return $e->die_event;
            $usr_home_ou_map->{$usr_id} = $usr->home_ou;
        }
        return $usr_home_ou_map->{$usr_id};
    };

    # our master perm
    my $target_usr_home_ou = $get_cached_home_ou->($target_user_id);
    return $e->event unless $e->allowed('TRANSFER_CONTAINER', $target_usr_home_ou);
    
    my $containers;
    my $search_method;
    if ($class eq 'copy') { $search_method = 'search_container_copy_bucket';
    } elsif ($class eq 'callnumber') { $search_method = 'search_container_call_number_bucket';
    } elsif ($class eq 'biblio') { $search_method = 'search_container_biblio_record_entry_bucket';
    } elsif ($class eq 'user') { $search_method = 'search_container_user_bucket';
    } else { return $e->event; }
    
    $containers = $e->$search_method({id => $container_ids});
    return $e->event unless $containers;

    for my $container (@$containers) {
        if ($container->owner ne $e->requestor->id) {
            my $owner_ou = $get_cached_home_ou->($container->owner)
                or return $e->die_event;
            # checks against original owner
            return $e->event unless $e->allowed('TRANSFER_CONTAINER', $owner_ou) &&
                $e->allowed('UPDATE_CONTAINER', $owner_ou);
            # check against target owner + one at the beginning of the method
            return $e->event unless $e->allowed('UPDATE_CONTAINER', $target_usr_home_ou);
        }

        # See if we have a collision with the owner/name/btype constraint
        my $existing_container = $e->$search_method({
            owner => $target_user_id,
            name => $container->name,
            btype => $container->btype
        })->[0];

        if ($existing_container) {
            # Generate a new unique name
            my $base_name = $container->name;
            my $counter = 1;
            my $new_name;
            do {
                $new_name = sprintf("%s (%d)", $base_name, $counter++);
                $existing_container = $e->$search_method({
                    owner => $target_user_id,
                    name => $new_name,
                    btype => $container->btype
                })->[0];
            } while ($existing_container);

            $container->name($new_name);
        }

        $container->owner($target_user_id);
    }

    my $update_method = $self->method_lookup('open-ils.actor.containers.update');
    my ($result) = $update_method->run($authtoken, $class, $containers);
    return $result;
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

sub batch_create_message {
    my $self = shift;
    my $client = shift;
    my $ses = shift;
    my $c_id = shift;
    my $pen = shift;
    my $msg = shift;

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

    $max = scalar(@users);
    $count = 0;
    $client->respond({ ord => $stage, max => $max, count => $count, stage => 'NOTE_ADD' });

    my $chunk = int($max / 10) || 1;
    for my $item (@$contents) {
        my $aum = Fieldmapper::actor::usr_message->new;

        # copy the message created in
        # the interface for the current user.
        $aum->create_date('now');
        $aum->sending_lib($e->requestor->ws_ou);
        $aum->title($msg->title);
        $aum->usr($item->target_user);
        $aum->message($msg->message);
        $aum->pub($msg->pub);
        $aum->isnew(1);

        $e->create_actor_usr_message($aum) or return $e->die_event;

        # create the penalty associated
        # with the new message.
        #(Silent notes have silent penalties)
        my $ausp = Fieldmapper::actor::user_standing_penalty->new;

        $ausp->org_unit($pen->org_unit);
        $ausp->standing_penalty($pen->standing_penalty);
        $ausp->usr_message($aum->id);
        $ausp->staff($pen->staff);
        $ausp->set_date($pen->set_date);
        $ausp->usr($item->target_user);

        $e->create_actor_user_standing_penalty($ausp) or return $e->die_event;

        $count++;
        $client->respond({ ord => $stage, max => $max, count => $count, stage => 'MESSAGE_CREATE' })
            unless ($count % $chunk);
    }

    $e->commit;

    return { stage => 'COMPLETE' };
}

__PACKAGE__->register_method(
    method  => "batch_create_message",
    api_name    => "open-ils.actor.container.user.batch_create_message",
    ctype       => 'user',
    perms       => {
            home_ou     => 'UPDATE_USER', # field -> perm means "test this perm with field as context OU", both old and new
    },
    signature => {
        desc => 'Creates a message for each user in a bucket',
        params => [{
            desc => 'Session key', type => 'string',
            desc => 'User container id',
            desc => 'Usr standing penalty item. This will be duplicated for each user in the bucket.',
            desc => 'Usr message item. This will be duplicated for each user in the bucket.',
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
    $max = int(scalar(@keys));
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

__PACKAGE__->register_method(
    method  => "add_container_user_share",
    api_name    => "open-ils.actor.container.user_share.create",
    signature => {
        desc => "Add a user share to a container",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Container class (biblio, callnumber, copy, user)", type => "string"},
            {desc => "Container ID", type => "number"},
            {desc => "User ID to share with", type => "number"},
        ],
        return => {
            desc => "1 on success, Event on error",
        }
    }
);

sub add_container_user_share {
    my($self, $conn, $auth, $container_class, $container_id, $user_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $meth = "retrieve_$ctypes{$container_class}";
    my $container = $e->$meth($container_id)
        or return $e->die_event;

    if ($container->owner ne $e->requestor->id) {
        return $e->die_event unless $e->allowed("ADMIN_CONTAINER_${container_class}_USER_SHARE", $e->requestor->home_ou);
    }

    my $map = Fieldmapper::permission::usr_object_perm_map->new;
    $map->usr($user_id);
    $map->perm($e->retrieve_permission_perm_list({code => "VIEW_CONTAINER"})->id);
    $map->object_type($jtypes{$container_class});
    $map->object_id($container_id);

    $e->create_permission_usr_object_perm_map($map) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method  => "remove_container_user_share",
    api_name    => "open-ils.actor.container.user_share.delete",
    signature => {
        desc => "Remove a user share from a container",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Container class (biblio, callnumber, copy, user)", type => "string"},
            {desc => "Container ID", type => "number"},
            {desc => "User ID to remove share from", type => "number"},
        ],
        return => {
            desc => "1 on success, Event on error",
        }
    }
);

sub remove_container_user_share {
    my($self, $conn, $auth, $container_class, $container_id, $user_id) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $meth = "retrieve_$ctypes{$container_class}";
    my $container = $e->$meth($container_id)
        or return $e->die_event;

    if ($container->owner ne $e->requestor->id) {
        return $e->die_event unless $e->allowed("ADMIN_CONTAINER_${container_class}_USER_SHARE", $e->requestor->home_ou);
    }

    my $map = $e->search_permission_usr_object_perm_map({
        usr => $user_id,
        object_type => $jtypes{$container_class},
        object_id => $container_id
    })->[0] or return $e->die_event;

    $e->delete_permission_usr_object_perm_map($map) or return $e->die_event;
    $e->commit;
    return 1;
}

__PACKAGE__->register_method(
    method  => "list_container_user_shares",
    api_name    => "open-ils.actor.container.user_share.retrieve",
    signature => {
        desc => "List user shares for a container",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Container class (biblio, callnumber, copy, user)", type => "string"},
            {desc => "Container ID", type => "number"},
            {desc => "Optional permission code to filter with", type => "string"},
        ],
        return => {
            desc => "Array of user IDs with shares on the container, Event on error",
        }
    }
);

sub list_container_user_shares {
    my($self, $conn, $auth, $container_class, $container_id, $perm_code) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    my $meth = "retrieve_$ctypes{$container_class}";
    my $container = $e->$meth($container_id)
        or return $e->die_event;

    if ($container->owner ne $e->requestor->id) {
        return $e->die_event unless $e->allowed('VIEW_CONTAINER_' . uc($ttypes{ ${container_class} }) . '_USER_SHARE', $e->requestor->home_ou);
    }

    my $search = {
        object_type => $jtypes{$container_class},
        object_id => $container_id
    };

    if ($perm_code) {
         $search->{'perm'} = $e->search_permission_perm_list({code => "$perm_code"})->[0]->id;
    }

    my $maps = $e->search_permission_usr_object_perm_map($search);

    return [map { $_->usr } @$maps];
}

__PACKAGE__->register_method(
    method  => "update_container_user_shares",
    api_name    => "open-ils.actor.container.update_record_bucket_user_share_mapping",
    signature => {
        desc => "Update user shares for multiple containers (removes all existing shares and (re-)adds new ones.",
        params => [
            {desc => "Authentication token", type => "string"},
            {desc => "Array of Container IDs", type => "array"},
            {desc => "Array of User IDs to share with", type => "array"},
            {desc => "Optional permission code to work with. Defauls to VIEW_CONTAINER", type => "string"},
        ],
        return => {
            desc => "1 on success, Event on error",
        }
    }
);

sub update_container_user_shares {
    my($self, $conn, $auth, $container_ids, $user_ids, $perm_code) = @_;
    my $e = new_editor(xact=>1, authtoken=>$auth);
    return $e->die_event unless $e->checkauth;

    if (!$perm_code) {
        $perm_code = 'VIEW_CONTAINER';
    }
    my $container_perm = $e->search_permission_perm_list({code => "$perm_code"})->[0]->id;

    my $retrieve_method;
    my $admin_perm;
    my $object_type;
    if ($self->api_name =~ 'update_record_bucket_user_share_mapping') {
        $retrieve_method = 'retrieve_container_biblio_record_entry_bucket';
        $admin_perm = 'ADMIN_CONTAINER_BIBLIO_RECORD_ENTRY_USER_SHARE';
        $object_type = 'cbreb';
    }

    foreach my $container_id (@$container_ids) {
        my $container = $e->$retrieve_method($container_id)
            or return $e->die_event;

        if ($container->owner ne $e->requestor->id) {
            return $e->die_event unless $e->allowed($admin_perm, $e->requestor->home_ou);
        }

        # Remove existing shares
        my $existing_maps = $e->search_permission_usr_object_perm_map({
            object_type => $object_type,
            object_id => $container_id,
            perm => $container_perm
        });
        foreach my $map (@$existing_maps) {
            $e->delete_permission_usr_object_perm_map($map) or return $e->die_event;
        }

        # Add new shares
        foreach my $user_id (@$user_ids) {
            my $map = Fieldmapper::permission::usr_object_perm_map->new;
            $map->usr($user_id);
            $map->perm($container_perm);
            $map->object_type($object_type);
            $map->object_id($container_id);
            $e->create_permission_usr_object_perm_map($map) or return $e->die_event;
        }
    }

    $e->commit;
    return 1;
}

1;


