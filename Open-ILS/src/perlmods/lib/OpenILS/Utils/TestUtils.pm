package OpenILS::Utils::TestUtils;
use base "OpenILS::Utils::Cronscript";

# The purpose of this module is to consolidate common routines that may
# be used by the integration tests in src/perlmods/live_t/

use strict; use warnings;

my $apputils = 'OpenILS::Application::AppUtils';

sub register_workstation {
    my ($self,$name,$lib) = (shift,shift,shift);
    my $resp = $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.workstation.register',
        $self->authtoken, $name, $lib);
    return $resp;
}

sub do_checkout {
    my ($self,$args) = (shift,shift);
    my $resp = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.checkout.full', $self->authtoken, $args);
    return $resp;
}

sub do_checkin {
    my ($self,$args) = (shift,shift);
    my $resp = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.checkin', $self->authtoken, $args );
    return $resp;
}

sub do_checkin_override {
    my ($self,$args) = (shift,shift);
    my $resp = $apputils->simplereq(
        'open-ils.circ',
        'open-ils.circ.checkin.override', $self->authtoken, $args );
    return $resp;
}

1;
