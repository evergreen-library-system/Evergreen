package OpenILS::Application::Trigger::Validator;
use strict; use warnings;
use DateTime;
use DateTime::Format::ISO8601;
use OpenSRF::Utils qw/:datetime/;
use OpenSRF::Utils::Logger qw/:logger/;
use OpenILS::Const qw/:const/;
sub fourty_two { return 42 }
sub NOOP_True { return 1 }
sub NOOP_False { return 0 }

sub CircIsOpen {
    my $self = shift;
    my $env = shift;

    return defined($env->{target}->checkin_time) ? 0 : 1;
}

sub MaxPassiveDelayAge {
    my $self = shift;
    my $env = shift;
    my $target = $env->{target};
    my $delay_field = $env->{event}->event_def->delay_field;

    my $delay_field_ts = DateTime::Format::ISO8601->new->parse_datetime(clense_ISO8601($target->$delay_field()));
    $delay_field_ts->add( seconds => interval_to_seconds( $env->{params}->{max_delay_age} ) );

    return 0 if $delay_field_ts > DateTime->now;
    return 1;
}

sub CircIsOverdue {
    my $self = shift;
    my $env = shift;
    my $circ = $env->{target};

    return 0 if $circ->checkin_time;
    return 0 if $circ->stop_fines and not $circ->stop_fines =~ /MAXFINES|LONGOVERDUE/;

    my $due_date = DateTime::Format::ISO8601->new->parse_datetime(clense_ISO8601($circ->due_date));
    return 0 if $due_date > DateTime->now;

    return 1;
}

sub HoldIsAvailable {
    my $self = shift;
    my $env = shift;

    my $hold = $env->{target};

    return 1 if 
        !$hold->cancel_time and
        $hold->capture_time and 
        $hold->current_copy and
        $hold->current_copy->status == OILS_COPY_STATUS_ON_HOLDS_SHELF;

    return 0;
}

1;
