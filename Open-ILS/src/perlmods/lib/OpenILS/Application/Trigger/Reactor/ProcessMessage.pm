package OpenILS::Application::Trigger::Reactor::ProcessMessage;
use base 'OpenILS::Application::Trigger::Reactor';
use strict; use warnings;
use OpenSRF::Utils::Logger qw/:logger/;

sub ABOUT {
    return <<ABOUT;

The ProcessMessage Reactor Module simply processes the configured
message template.  The output is returned, or undef on error.

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;
    return $self->run_message_TT($env);
}

1;

