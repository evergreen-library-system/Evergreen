package OpenILS::Application::Trigger::Validator::Curbside;
use strict; use warnings;
use OpenILS::Application::AppUtils;
my $U = 'OpenILS::Application::AppUtils';

sub handler {
    my ($self, $env) = @_;
    my $org;

    # support a few different target types
    if ($env->{target}->isa('Fieldmapper::action::curbside')) {
        $org = $env->{target}->org;
    } elsif ($env->{target}->isa('Fieldmapper::action::hold_request')) {
        $org = $env->{target}->pickup_lib;
    } elsif ($env->{target}->isa('Fieldmapper::actor::usr')) {
        $org = $env->{target}->home_ou;
    } elsif ($env->{target}->isa('Fieldmapper::actor::org_unit')) {
        $org = $env->{target}->id;
    }

    return 0 unless (defined $org);

    $org = $org->id if ref($org); # somehow we got a fleshed org object on the target
    return $U->is_true(
        $U->ou_ancestor_setting_value($org, 'circ.curbside')
    );
}

1;
