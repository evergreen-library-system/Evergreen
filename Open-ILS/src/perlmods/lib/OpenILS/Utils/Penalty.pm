package OpenILS::Utils::Penalty;
use strict; use warnings;
use DateTime;
use Data::Dumper;
use OpenSRF::EX qw(:try);
use OpenSRF::Utils::Cache;
use OpenILS::Utils::DateTime qw/:datetime/;
use OpenILS::Application::AppUtils;
use OpenSRF::Utils::Logger qw(:logger);
use OpenILS::Utils::CStoreEditor qw/:funcs/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Const qw/:const/;
my $U = "OpenILS::Application::AppUtils";


# calculate and update the well-known penalties
sub calculate_penalties {
    my($class, $e, $user_id, $context_org) = @_;

    my $commit = 0;
    unless($e) {
        $e = new_editor(xact =>1);
        $commit = 1;
    }

    my $penalties = $e->json_query({from => ['actor.calculate_system_penalties',$user_id, $context_org]});

    my $user = $e->retrieve_actor_user( $user_id );
    my @existing_penalties = grep { defined $_->{id} } @$penalties;
    my @wanted_penalties = grep { !defined $_->{id} } @$penalties;
    my @trigger_events;

    my %csp;
    for my $pen_obj (@wanted_penalties) {

        my $pen = Fieldmapper::actor::user_standing_penalty->new;
        $pen->$_($pen_obj->{$_}) for keys %$pen_obj;

        # let's see if this penalty is accounted for already
        my ($existing) = grep { 
                $_->{org_unit} == $pen_obj->{org_unit} and
                $_->{standing_penalty} == $pen_obj->{standing_penalty}
            } @existing_penalties;

        if($existing) { 
            # we have one of these already.  Leave it be, but remove it from the 
            # existing set so it's not deleted in the subsequent loop
            @existing_penalties = grep { $_->{id} ne $existing->{id} }  @existing_penalties;

        } else {

            # this is a new penalty
            $e->create_actor_user_standing_penalty($pen) or return $e->die_event;

            my $csp_obj = $csp{$pen->standing_penalty} || 
                $e->retrieve_config_standing_penalty( $pen->standing_penalty );

            # cache for later
            $csp{$pen->standing_penalty} = $csp_obj;

            push(@trigger_events, ['penalty.' . $csp_obj->name, $pen, $pen->org_unit]);
        }
    }

    # at this point, any penalties remaining in the existing 
    # penalty set are unaccounted for and should be removed
    for my $pen_obj (@existing_penalties) {
        my $pen = Fieldmapper::actor::user_standing_penalty->new;
        $pen->$_($pen_obj->{$_}) for keys %$pen_obj;
        $e->delete_actor_user_standing_penalty($pen) or return $e->die_event;
    }

    $e->commit if $commit;

    $U->create_events_for_hook($$_[0], $$_[1], $$_[2]) for @trigger_events;
    return undef;
}

# any penalties whose block_list has an item from @fatal_mask will be sorted
# into the fatal_penalties set.  Others will be sorted into the info_penalties set
sub retrieve_penalties {
    my($class, $e, $user_id, $context_org, @fatal_mask) = @_;

    my(@info, @fatal);
    my $penalties = $class->retrieve_usr_penalties($e, $user_id, $context_org);

    for my $p (@$penalties) {
        my $pushed = 0;
        if($p->standing_penalty->block_list) {
            for my $m (@fatal_mask) {
                if($p->standing_penalty->block_list =~ /$m/) {
                    push(@fatal, $p->standing_penalty);
                    $pushed = 1;
                    last;
                }
            }
        }
        push(@info, $p->standing_penalty) unless $pushed;
    }

    return {fatal_penalties => \@fatal, info_penalties => \@info};
}


# Returns a list of actor_user_standing_penalty objects
sub retrieve_usr_penalties {
    my($class, $e, $user_id, $context_org) = @_;

    return $e->search_actor_user_standing_penalty([
        {
            usr => $user_id, 
            org_unit => $U->get_org_full_path($context_org),
            '-or' => [
                {stop_date => undef},
                {stop_date => {'>' => 'now'}}
            ],
        },
        {flesh => 1, flesh_fields => {ausp => ['standing_penalty']}}
    ]);
}

1;


