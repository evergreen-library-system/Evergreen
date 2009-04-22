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
    my($class, $e, $user_id, $context_org) = @_;

    my $rollback = 0;
    unless($e) {
        $e = new_editor(xact =>1);
        $rollback = 1;
    }

    my $penalties = $e->json_query({from => ['actor.calculate_system_penalties',$user_id, $context_org]});

    my $user = $e->retrieve_actor_user( $user_id );
    my $ses = OpenSRF::AppSession->create('open-ils.trigger') if (@$penalties);

    my %csp;
    for my $pen_obj (@$penalties) {

        next if grep { # leave duplicate penalties in place
            $_->{org_unit} == $pen_obj->{org_unit} and
            $_->{standing_penalty} == $pen_obj->{standing_penalty} and
            ($_->{id} || '') ne ($pen_obj->{id} || '') } @$penalties;

        my $pen = Fieldmapper::actor::user_standing_penalty->new;
        $pen->$_($pen_obj->{$_}) for keys %$pen_obj;

        if(defined $pen_obj->{id}) {
            $e->delete_actor_user_standing_penalty($pen) or return $e->die_event;

        } else {
            $e->create_actor_user_standing_penalty($pen) or return $e->die_event;

            my $csp_obj = $csp{$pen->standing_penalty} ||
                $e->retrieve_config_standing_penalty( $pen->standing_penalty );

            # cache for later
            $csp{$pen->standing_penalty} = $csp_obj;

            $ses->request(
                'open-ils.trigger.event.autocreate',
                'penalty.' . $csp_obj->name,
                $user,
                $pen->org_unit
            );
        }
    }

    $e->rollback if $rollback;
    return undef;
}

# any penalties whose block_list has an item from @fatal_mask will be sorted
# into the fatal_penalties set.  Others will be sorted into the info_penalties set
sub retrieve_penalties {
    my($class, $e, $user_id, $context_org, @fatal_mask) = @_;

    my $penalties = $e->search_actor_user_standing_penalty([
        {usr => $user_id, org_unit => $U->get_org_ancestors($context_org)},
        {flesh => 1, flesh_fields => {ausp => ['standing_penalty']}}
    ]);

    my(@info, @fatal);
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

1;
