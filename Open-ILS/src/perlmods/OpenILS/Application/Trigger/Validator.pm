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

    return 0 if (defined($env->{target}->checkin_time));
    return 0 if ($env->{params}->{max_delay_age} && !$self->MaxPassiveDelayAge($env));

    if ($env->{params}->{min_target_age}) {
        $env->{params}->{target_age_field} = 'xact_start';
        return 0 if (!$self->MinPassiveTargetAge($env));
    }

    return 1;
}

sub MaxPassiveDelayAge {
    my $self = shift;
    my $env = shift;
    my $target = $env->{target};
    my $delay_field = $env->{event}->event_def->delay_field;

    my $delay_field_ts = DateTime::Format::ISO8601->new->parse_datetime(clense_ISO8601($target->$delay_field()));

    # the cutoff date is the target timestamp + the delay + the max_delay_age
    # This is also true for negative delays. For example:
    #    due_date + "-3 days" + "1 day" == -2 days old.
    $delay_field_ts
        ->add( seconds => interval_to_seconds( $env->{event}->event_def->delay ) )
        ->add( seconds => interval_to_seconds( $env->{params}->{max_delay_age} ) );

    return 1 if $delay_field_ts > DateTime->now;
    return 0;
}

sub MinPassiveTargetAge {
    my $self = shift;
    my $env = shift;
    my $target = $env->{target};
    my $delay_field = $env->{params}->{target_age_field} || $env->{event}->event_def->delay_field;

    my $delay_field_ts = DateTime::Format::ISO8601->new->parse_datetime(clense_ISO8601($target->$delay_field()));

    # to get the minimum time that the target must have aged to, add the min age to the delay field
    $delay_field_ts->add( seconds => interval_to_seconds( $env->{params}->{min_target_age} ) );

    return 1 if $delay_field_ts <= DateTime->now;
    return 0;
}

sub CircIsOverdue {
    my $self = shift;
    my $env = shift;
    my $circ = $env->{target};

    return 0 if $circ->checkin_time;
    return 0 if $circ->stop_fines and not $circ->stop_fines =~ /MAXFINES|LONGOVERDUE/;
    return 0 if ($env->{params}->{max_delay_age} && !$self->MaxPassiveDelayAge($env));

    if ($env->{params}->{min_target_age}) {
        $env->{params}->{target_age_field} = 'xact_start';
        return 0 if (!$self->MinPassiveTargetAge($env));
    }

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
