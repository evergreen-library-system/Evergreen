package OpenILS::Utils::Penalty;
use strict; use warnings;
use DateTime;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Cache;
use OpenSRF::Utils qw/:datetime/;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw/:const/;
my $U = "OpenILS::Application::AppUtils";


# calculate and update the well-known penalties
sub calculate_penalties {
    my($class, $e, $user_id, $user) = @_;

    $user = $user || $e->retrieve_actor_user($user_id);
    $user_id = $user->id;
    my $grp_id = (ref $user->profile) ? $user->profile->id : $user->profile;

    my $penalties = $e->search_actor_user_standing_penalty({usr => $user_id});
    my $stats = $class->collect_user_stats($e, $user_id);
    my $overdue = $stats->{overdue};
    my $mon_owed = $stats->{money_owed};
    my $thresholds = $class->get_group_penalty_thresholds($e, $grp_id);

    $logger->info("patron $user_id in group $grp_id has $overdue overdue circulations and owes $mon_owed");

    for my $thresh (@$thresholds) {
        my $evt;

        if($thresh->penalty == OILS_PENALTY_PATRON_EXCEEDS_FINES) {
            $evt = $class->check_apply_penalty(
                $e, $user_id, $penalties, OILS_PENALTY_PATRON_EXCEEDS_FINES, $thresh->threshold, $mon_owed);
            return $evt if $evt;
        }

        if($thresh->penalty == OILS_PENALTY_PATRON_EXCEEDS_OVERDUE_COUNT) {
            $evt = $class->check_apply_penalty(
                $e, $user_id, $penalties, OILS_PENALTY_PATRON_EXCEEDS_OVERDUE_COUNT, $thresh->threshold, $overdue);
            return $evt if $evt;
        }
    }
}

# if a given penalty does not already exist in the DB, this creates it.  
# If it does exist and should not, this removes it.
sub check_apply_penalty {
    my($class, $e, $user_id, $all_penalties, $penalty_id, $threshold, $value) = @_;
    my ($existing) = grep { $_->standing_penalty == $penalty_id } @$all_penalties;

    # penalty threshold has been exceeded and needs to be added
    if($value >= $threshold and not $existing) {
        my $newp = Fieldmapper::actor::user_standing_penalty->new;
        $newp->standing_penalty($penalty_id);
        $newp->usr($user_id);
        $e->create_actor_user_standing_penalty($newp) or return $e->die_event;

    # patron is within penalty range and existing penalty must be removed
    } elsif($value < $threshold and $existing) {
        $e->delete_actor_user_standing_penalty($existing)
            or return $e->die_event;
    }

    return undef;
}


sub collect_user_stats {
    my($class, $e, $user_id) = @_;

    my $stor_ses = $U->start_db_session();
	my $money_owed = $stor_ses->request(
        'open-ils.storage.actor.user.total_owed', $user_id)->gather(1);
    my $checkouts = $stor_ses->request(
	    'open-ils.storage.actor.user.checked_out.count', $user_id)->gather(1);
	$U->rollback_db_session($stor_ses);

    return {
        overdue => $checkouts->{overdue} || 0, 
        money_owed => $money_owed || 0
    };
}

# get the ranged set of penalties for a give group
# XXX this could probably benefit from a stored proc
sub get_group_penalty_thresholds {
    my($class, $e, $grp_id) = @_;
    my @thresholds;
    my $cur_grp = $grp_id;
    do {
        my $thresh = $e->search_permission_grp_penalty_threshold({grp => $cur_grp});
        for my $t (@$thresh) {
            push(@thresholds, $t) unless (grep { $_->name eq $t->name } @thresholds);
        }
    } while(defined ($cur_grp = $e->retrieve_permission_grp_tree($cur_grp)->parent));
    
    return \@thresholds;
}


# any penalties whose block_list has an item from @fatal_mask will be sorted
# into the fatal_penalties set.  Others will be sorted into the info_penalties set
sub retrieve_penalties {
    my($class, $e, $user_id, @fatal_mask) = @_;

    my $penalties = $e->search_actor_user_standing_penalty([
        {usr => $user_id},
        {flesh => 1, flesh_fields => {ausp => ['standing_penalty']}}
    ]);

    my(@info, @fatal);
    for my $p (@$penalties) {
        my $pushed = 0;
        if($p->standing_penalty->block_list) {
            for my $m (@fatal_mask) {
                if($p->standing_penalty->block_list =~ /$m/) {
                    push(@fatal, $p->name);
                    $pushed = 1;
                }
            }
        }
        push(@info, $p->name) unless $pushed;
    }

    return {fatal_penalties => \@fatal, info_penalties => \@info};
}

1;
