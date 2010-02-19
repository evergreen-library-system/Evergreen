package OpenILS::Application::Trigger::Validator::Acq;
use strict; use warnings;
use OpenSRF::Utils::Logger qw/:logger/;

sub UserRequestOrdered {
    my $self = shift;
    my $env = shift;
    return get_lineitem_from_req($self, $env)->state eq 'on-order';
}

sub UserRequestReceived {
    my $self = shift;
    my $env = shift;
    return get_lineitem_from_req($self, $env)->state eq 'received';
}

sub UserRequestCancelled {
    my $self = shift;
    my $env = shift;
    return get_lineitem_from_req($self, $env)->state eq 'cancelled';
}

sub get_lineitem_from_req {
    my($self, $env) = @_;
    my $req = $env->{target};
    return (ref $env->{target}->lineitem) ? 
        $env->{target}->lineitem : 
        $self->editor->retrieve_acq_lineitem($$env->{target}->lineitem);
}

1;
