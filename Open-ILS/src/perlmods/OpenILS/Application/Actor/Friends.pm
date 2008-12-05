package OpenILS::Application::Actor::Friends;
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenILS::Utils::Fieldmapper;
my $U = "OpenILS::Application::AppUtils";

# ----------------------------------------------------------------
# Shared Friend utilities.  Thar be no methods published here...
# ----------------------------------------------------------------

# export these fields for friend display
my @keep_user_fields = qw/id usrname first_given_name second_given_name family_name alias/;

my $out_links_query = {
    select => {cubi => ['target_user']}, 
    from => {
        cub => {
            cubi => {field => 'bucket', fkey => 'id'}
        }
    }, 
    where => {
        '+cub' => {btype => 'folks', owner => undef}
    }
};

my $in_links_query = { 
    select => {cub =>  ['owner'] }, 
    from => {
        cub => {
            cubi => {field => 'bucket', fkey => 'id'}
        }
    }, 
    where => {
        '+cubi' => {target_user => undef}, 
        '+cub' => {btype => 'folks'}
    }
};

my $perm_check_query = { 
    select => {cub =>  ['btype'] }, 
    from => {
        cub => {
            cubi => {field => 'bucket', fkey => 'id'}
        }
    }, 
    limit => 1
};

sub retrieve_friends {
    my($self, $e, $user_id) = @_;

    # users I have links to
    $out_links_query->{where}->{'+cub'}->{owner} = $user_id;
    my @out_linked = map {$_->{target_user}} @{$e->json_query($out_links_query)};

    # users who link to me
    $in_links_query->{where}->{'+cubi'}->{target_user} = $user_id;
    my @in_linked = map {$_->{owner}} @{$e->json_query($in_links_query)};

    # determine which users are confirmed, pending outbound 
    # requests, and pending inbound requests
    my @confirmed;
    my @pending_out;
    my @pending_in;

    for my $out_link (@out_linked) {
        if(grep {$_ == $out_link} @in_linked) {
            push(@confirmed, $out_link);
        } else {
            push(@pending_out, $out_link);
        }
    }

    for my $in_link (@in_linked) {
        push(@pending_in, $in_link)
            unless grep {$_ == $in_link} @confirmed;
    }

    return {
        confirmed => $self->load_linked_user_perms($e, $user_id, @confirmed),
        pending_out => $self->load_linked_user_perms($e, $user_id, @pending_out),
        pending_in => $self->load_linked_user_perms($e, $user_id, @pending_in)
    };
}

# given a base user and set of linked users, returns the trimmed linked user
# records, plus the perms (by name) each user has been granted
sub load_linked_user_perms {
    my($self, $e, $user_id, @users) = @_;
    my $items = [];
    my $select = {select => {au => \@keep_user_fields}};

    for my $d_user (@users) {

        # fetch all of the bucket items linked from base user to 
        # delegate user with the folks: prefix on the bucket type
        $perm_check_query->{where} = {
            '+cubi' => {target_user => $d_user},
            '+cub' => {btype => {like => 'folks:%'}, owner => $user_id}
        };

        push(@$items, {
                user => $e->retrieve_actor_user([$d_user, $select]),
                permissions => [ 
                    # trim the folks: prefix from the bucket type
                    map {substr($_->{btype}, 6)} @{$e->json_query($perm_check_query)} 
                ]
            }
        );
    }
    return $items;
}


my $direct_links_query = { 
    select => {cub =>  ['id'] }, 
    from => {
        cub => {
            cubi => {field => 'bucket', fkey => 'id'}
        }
    }, 
    where => {
        '+cubi' => {target_user => undef}, 
        '+cub' => {btype => 'folks', owner => undef}
    },
    limit => 1
};

sub confirmed_friends {
    my($self, $e, $user1_id, $user2_id) = @_;

    $direct_links_query->{where}->{'+cub'}->{owner} = $user1_id;
    $direct_links_query->{where}->{'+cubi'}->{target_user} = $user2_id;

    if($e->json_query($direct_links_query)->[0]) {
        
        $direct_links_query->{where}->{'+cub'}->{owner} = $user2_id;
        $direct_links_query->{where}->{'+cubi'}->{target_user} = $user1_id;
        return 1 if $e->json_query($direct_links_query)->[0];
    }

    return 0;
}



# returns 1 if delegate_user is allowed to perform 'perm' for base_user
sub friend_perm_allowed {
    my($self, $e, $base_user_id, $delegate_user_id, $perm) = @_;
    return 0 unless $self->confirmed_friends($base_user_id, $delegate_user_id);
    $perm_check_query->{where} = {
        '+cubi' => {target_user => $delegate_user_id},
        '+cub' => {btype => "folks:$perm", owner => $base_user_id}
    };
    return 1 if $e->json_query($perm_check_query)->[0];
    return 0;
}

sub apply_friend_perm {
    my($self, $e, $base_user_id, $delegate_user_id, $perm) = @_;

    my $bucket = $e->search_container_user_bucket(
        {owner => $base_user_id, btype => "folks:$perm"})->[0];

    if($bucket) {
        # is the permission already set?
        return undef if $e->search_container_user_bucket_item(
            {bucket => $bucket->id, target_user => $delegate_user_id})->[0];

    } else {
        # make sure the perm-specific bucket exists for this user
        $bucket = Fieldmapper::container::user_bucket->new;
        $bucket->owner($base_user_id);
        $bucket->btype("folks:$perm");
        $bucket->name("folks:$perm");
        $e->create_container_user_bucket($bucket) or return $e->die_event;
    }

    my $item = Fieldmapper::container::user_bucket_item->new;
    $item->bucket($bucket->id);
    $item->target_user($delegate_user_id);
    $e->create_container_user_bucket_item($item) or return $e->die_event;
    return undef;
}

23;
