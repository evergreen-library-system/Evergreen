package OpenILS::Application::Trigger::Validator::Acq::UserRequestCancelled;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Application::Trigger::Validator::Acq;

sub handler {
    my $self = shift;
    my $env = shift;
    return OpenILS::Application::Trigger::Validator::Acq::get_lineitem_from_req($self, $env)->state eq 'cancelled';
}

1;
