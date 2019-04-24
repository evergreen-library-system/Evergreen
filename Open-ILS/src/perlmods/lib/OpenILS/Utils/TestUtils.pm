package OpenILS::Utils::TestUtils;
use base "OpenILS::Utils::Cronscript";

# The purpose of this module is to consolidate common routines that may
# be used by the integration tests in src/perlmods/live_t/

use strict; use warnings;

my $apputils = 'OpenILS::Application::AppUtils';

sub find_workstation {
    my ($self,$name,$lib) = (shift,shift,shift);
    my $resp = $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.workstation.list',
        $self->authtoken,
        $lib
    );
    if ($resp->{$lib}) {
        return scalar(grep {$_->name() eq $name} @{$resp->{$lib}});
    }
    return 0;
}

sub register_workstation {
    my ($self,$name,$lib) = (shift,shift,shift);
    my $resp = $apputils->simplereq(
        'open-ils.actor',
        'open-ils.actor.workstation.register',
        $self->authtoken, $name, $lib);
    return $resp;
}

sub find_or_register_workstation {
    my ($self,$name,$lib) = (shift,shift,shift);
    my $workstation = $self->find_workstation($name, $lib);
    if (!$workstation) {
	$workstation = $self->register_workstation($name, $lib);
    }
    return $workstation;
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
