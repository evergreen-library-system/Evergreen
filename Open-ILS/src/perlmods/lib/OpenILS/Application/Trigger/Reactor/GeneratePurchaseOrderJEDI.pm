package OpenILS::Application::Trigger::Reactor::GeneratePurchaseOrderJEDI;
use base 'OpenILS::Application::Trigger::Reactor';
use strict; use warnings;
use OpenSRF::Utils::Logger qw/:logger/;

sub ABOUT {
    return <<ABOUT;

Generates PO JEDI (JSON EDI) output for subsequent processing and EDI delivery

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;
    return 1 if $self->run_TT($env);
    return 0;
}

1;

