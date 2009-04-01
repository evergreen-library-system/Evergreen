package OpenILS::Application::Trigger::Reactor::ProcessTemplate;
use base 'OpenILS::Application::Trigger::Reactor';
use strict; use warnings;
use OpenSRF::Utils::Logger qw/:logger/;

sub ABOUT {
    return <<ABOUT;

The ProcessTemplate Reactor Module simply processes the configured template.
The output, like all processed templates, is stored in the event_output table.

ABOUT
}

sub handler {
    my $self = shift;
    my $env = shift;
    return 1 if $self->run_TT($env);
    return 0;
}

1;

