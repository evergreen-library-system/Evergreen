package OpenILS::Application::Trigger::Validator;
use strict; use warnings;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Logger qw/:logger/;
sub fourty_two { return 42 }
sub NOOP_True { return 1 }
sub NOOP_False { return 0 }

sub CircIsOpen {
    my $self = shift;
    my $env = shift;

    return defined($env->{target}->checkin_time) ? 0 : 1;
}

sub CircIsOverdue {
    my $self = shift;
    my $env = shift;
    my $circ = $env->{target};

    return 0 if $circ->checkin_time;
    return 0 if $circ->stop_fines and not $circ->stop_fines =~ /MAXFINES|LONGOVERDUE/;

    my $due_date = DateTime::Format::ISO8601->new->parse_datetime(clense_ISO8601($circ->due_date));
    return 0 if $due_date < DateTime->now;

    return 1;
}

sub HoldIsAvailable {
    my $self = shift;
    my $env = shift;

    my $t = $env->{target}->transit;

    die "Transit object exists, but is not fleshed.  Add 'transit' to the environment in order to use this Validator."
        if ($t && !ref($t));

    if ($t) {
        return (defined($env->{target}->capture_time) && defined($t->dest_recv_time)) ? 1 : 0;
    }

    return defined($env->{target}->capture_time) ? 1 : 0;
}

1;
