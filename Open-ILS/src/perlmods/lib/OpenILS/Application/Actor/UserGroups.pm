package OpenILS::Application::Actor::UserGroups;
use base 'OpenILS::Application';
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
use OpenSRF::EX qw(:try);
my $U = "OpenILS::Application::AppUtils";

sub initialize { return 1; }



__PACKAGE__->register_method(
    method => 'group_money_summary',
    api_name    => 'open-ils.actor.usergroup.members.balance_owed',
    authoritative => 1,
    signature   => q/
    /
);

sub group_money_summary {
    my($self, $conn, $auth, $group_id) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_USER');

    my $users = $e->search_actor_user(
        {usrgroup => $group_id, deleted => 'f'}, {idlist => 1});
    my @mous;

    for my $uid ( @$users ) {
        push @mous, @{$e->json_query(
            {
                select => {mous => ['usr', 'balance_owed']},
                from => 'mous',
                where => { usr => $uid }
            }
        )};
    }

    return \@mous;
}


__PACKAGE__->register_method(
    method => 'get_users_from_usergroup',
    api_name    => 'open-ils.actor.usergroup.members.retrieve',
    authoritative => 1,
    signature   => q/
        Returns a list of ids for users that are in the given usergroup
    /
);

sub get_users_from_usergroup {
    my( $self, $conn, $auth, $usergroup ) = @_;
    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_USER'); # XXX reley on editor perm
    return $e->search_actor_user(
        {usrgroup => $usergroup, deleted => 'f'}, {idlist => 1});
}



__PACKAGE__->register_method(
    method => 'get_address_members',
    api_name    => 'open-ils.actor.address.members',
    signature   => q/
        Returns a list of ids for users that link to the given address
        @param auth
        @param addrid The address id
    /
);

sub get_address_members {
    my( $self, $conn, $auth, $addrid ) = @_;

    my $e = new_editor(authtoken=>$auth);
    return $e->event unless $e->checkauth;
    return $e->event unless $e->allowed('VIEW_USER'); # XXX reley on editor perm

    my $ad = $e->retrieve_actor_user_address($addrid) or return $e->event;
    my $ma = $e->search_actor_user(
        {mailing_address => $addrid, deleted => 'f'}, {idlist => 1});
    my $ba = $e->search_actor_user(
        {billing_address => $addrid, deleted => 'f'}, {idlist => 1});

    my @list = (@$ma, @$ba, $ad->usr);
    my %dedup = map { $_ => 1 } @list;
    return [ keys %dedup ];
}



__PACKAGE__->register_method(
    method  => 'reset_group',
    api_name    => 'open-ils.actor.usergroup.new',
    signature   => q/
        Gives the requested user a new empty usergroup.  
        @param auth The auth token
        @param userid The id of the user who needs the new usergroup
        @param leader If true, this user will be marked as the group leader
    /
);

sub reset_group {
    my( $self, $conn, $auth, $userid, $leader ) = @_;

    my $e = new_editor(authtoken=>$auth, xact=>1);
    return $e->die_event unless $e->checkauth;
    return $e->die_event unless $e->allowed('UPDATE_USER'); # XXX reley on editor perm

    my $user = $e->retrieve_actor_user($userid) or return $e->die_event;

    # ask for a new group id
    my $groupid = $U->storagereq('open-ils.storage.actor.user.group_id.new');

    $user->usrgroup($groupid);
    $user->master_account('t') if $leader;

    $e->update_actor_user($user) or return $e->die_event;
    $e->commit;
    return $groupid;
}




1;
