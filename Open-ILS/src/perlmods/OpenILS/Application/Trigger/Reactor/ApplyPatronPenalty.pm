package OpenILS::Application::Trigger::Reactor::ApplyPatronPenalty;
use base 'OpenILS::Application::Trigger::Reactor';
use strict; use warnings;
use Error qw/:try/;
use OpenILS::Const qw/:const/;
use OpenILS::Utils::Fieldmapper;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::AppUtils;
my $U = "OpenILS::Application::AppUtils";


sub ABOUT {
    return <<ABOUT;
    
    Applies a standing penalty to a patron.  If there is a template, the template is 
    used as the value for the note

    Required named (with labels) environment variables:
        "user" -- User object fleshed into the environment
        "context_org" -- Org unit object fleshed into the environment

    Note: Using named env variables with a grouped event definition where the 
        env vars may be different depending on the target produces undefined behavior.
        Don't use this reactor if more than one User or Org Unit object may be 
        referenced accross the set of target objects.

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;

    my $pname = $$env{params}{standing_penalty};
    my $user = $$env{environment}{user};
    my $context_org = $$env{environment}{context_org};

    unless($pname and ref $user and ref $context_org) {
        $logger->error("ApplyPatronPenalty: missing parameters");
        return 0;
    }

    my $e = new_editor(xact => 1);

    my $ptype = $e->search_config_standing_penalty({name => $pname})->[0];

    unless($ptype) {
        $logger->error("ApplyPatronPenalty: invalid penalty name '$pname'");
        $e->rollback;
        return 0;
    }

    $context_org = (defined $ptype->org_depth) ?
        $U->org_unit_ancestor_at_depth($context_org->id, $ptype->org_depth) :
        $context_org->id;

    # apply the penalty
    my $penalty = Fieldmapper::actor::usr_standing_penalty->new;
    $penalty->usr($user->id);
    $penalty->org_unit($context_org);
    $penalty->standing_penalty($ptype->id);
    $penalty->note($self->run_TT($env));

    unless($e->create_actor_user_standing_penalty($penalty)) {
        $e->rollback;
        return 0;
    }

    $e->commit;
    return 1;
}

1;
