package OpenILS::Application::Actor::Friends;
use strict; use warnings;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenSRF::Utils::Logger q/$logger/;
my $U = "OpenILS::Application::AppUtils";

# ----------------------------------------------------------------
# Shared Friend utilities.  Thar be no methods published here...
# ----------------------------------------------------------------

# export these fields for friend display
my @keep_user_fields = qw/usrname first_given_name second_given_name family_name alias/;

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


sub retrieve_friends {
    my($self, $e, $user_id) = @_;

    # users I have links to
    $out_links_query->{where}->{'+cub'}->{owner} = $user_id;
    my @out_linked = map {$_->{target_user}} @{$e->json_query($out_links_query)};

    # users who link to me
    $in_links_query->{where}->{'+cubi'}->{target_user} = $user_id;
    my @in_linked = map {$_->{owner}} @{$e->json_query($in_links_query)};

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

    my $select = {select => {au => \@keep_user_fields}};

    my $confirmed = (@confirmed) ? 
        $e->search_actor_user([{id => \@confirmed}, $select]) : [];

    my $pending_out = (@pending_out) ?
        $e->search_actor_user([{id => \@pending_out}, $select]) : [];

    my $pending_in = (@pending_in) ? 
        $e->search_actor_user([{id => \@pending_in}, $select]) : [];

    return {
        confirmed => $confirmed,
        pending_out => $pending_out,
        pending_in =>$pending_in
    };
}

23;
