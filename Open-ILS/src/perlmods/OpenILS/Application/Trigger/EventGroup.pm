package OpenILS::Application::Trigger::EventGroup;
use OpenILS::Application::Trigger::Event;
use base 'OpenILS::Application::Trigger::Event';
use OpenSRF::EX qw/:try/;

use OpenSRF::Utils::Logger qw/:level/;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Trigger::ModRunner;

my $log = 'OpenSRF::Utils::Logger';

sub new {
    my $class = shift;
    my @ids = @_;
    $class = ref($class) || $class;

    my $editor = new_editor(xact=>1);

    my $self = bless {
        environment => {},
        events      => [
            map {
                ref($_) ?
                    do { $_->standalone(0); $_->editor($editor); $_ } :
                    OpenILS::Application::Trigger::Event->new($_, $editor)
            } @ids
        ],
        ids         => \@ids,
        editor      => $editor
    } => $class;


    $self->editor->xact_commit; # flush out those updates
    $self->editor->xact_begin;

    return $self;
}

sub react {
    my $self = shift;

    return $self if (defined $self->reacted);

    if ($self->valid) {
        $self->update_state( 'reacting') || die 'Unable to update event group state';
        $self->build_environment;

        try {
            $self->reacted(
                OpenILS::Application::Trigger::ModRunner::Reactor
                    ->new( $self->event->event_def->reactor, $self->environment )
                    ->run
                    ->final_result
            );
        } otherwise {
            $log->error( shift() );
            $self->update_state( 'error' ) || die 'Unable to update event group state';
        };

        if (defined $self->reacted) {
            $self->update_state( 'reacted' ) || die 'Unable to update event group state';
        } else {
            $self->update_state( 'error' ) || die 'Unable to update event group state';
        }
    } else {
        $self->{reacted} = undef;
    }
    return $self;
}

sub validate {
    my $self = shift;

    return $self if (defined $self->valid);

    $self->update_state( 'validating') || die 'Unable to update event group state';
    $self->editor->xact_begin;

    my @valid_events;
    try {
        for my $event ( @{ $self->events } ) {
            $event->validate;
            push @valid_events, $event if ($event->valid);
        }
        $self->valid(1) if (@valid_events);
        $self->{events} = \@valid_events;
        $self->editor->xact_commit;
    } otherwise {
        $log->error( shift() );
        $self->editor->xact_rollback;
        $self->update_state( 'error' ) || die 'Unable to update event group state';
    };

    return $self;
}
 
sub cleanedup {
    my $self = shift;
    return undef unless (ref $self);

    my $c = shift;
    $self->{cleanedup} = $c if (defined $c);
    return $self->{cleanedup};
}

sub reacted {
    my $self = shift;
    return undef unless (ref $self);

    my $r = shift;
    $self->{reacted} = $r if (defined $r);
    return $self->{reacted};
}

sub valid {
    my $self = shift;
    return undef unless (ref $self);

    my $v = shift;
    $self->{valid} = $v if (defined $v);
    return $self->{valid};
}

sub event {
    my $self = shift;
    return undef unless (ref $self);

    return $self->{events}[0];
}

sub events {
    my $self = shift;
    return undef unless (ref $self);

    return $self->{events};
}

sub ids {
    my $self = shift;
    return undef unless (ref $self);

    return $self->{ids};
}

sub environment {
    my $self = shift;
    return undef unless (ref $self);

    my $e = shift;
    $self->{environment} = $e if (defined $e);
    return $self->{environment};
}

sub editor {
    my $self = shift;
    return undef unless (ref $self);

    my $e = shift;
    $self->{editor} = $e if (defined $e);
    return $self->{editor};
}

sub unfind {
    my $self = shift;
    return undef unless (ref $self);

    die 'Cannot unfind a reacted event group' if (defined $self->reacted);

    $self->update_state( 'pending' ) || die 'Unable to update event group state';
    $self->{events} = undef;
    return $self;
}

sub update_state {
    my $self = shift;
    return undef unless ($self && ref $self);

    my $state = shift;
    return undef unless ($state);

    $self->editor->xact_begin || return undef;

    my @oks;
    for my $event ( @{ $self->events } ) {
        my $e = $self->editor->retrieve_action_trigger_event( $event->id );
        $e->start_time( 'now' ) unless $e->start_time;
        $e->update_time( 'now' );
        $e->update_process( $$ );
        $e->state( $state );
    
        $e->clear_start_time() if ($e->state eq 'pending');
    
        my $ok = $self->editor->update_action_trigger_event( $e );
        if ($ok) {
            push @oks, $ok;
        }
    }

    if (scalar(@oks) < scalar(@{ $self->ids })) {
        $self->editor->xact_rollback;
        return undef;
    } else {
        $ok = $self->editor->xact_commit;
    }

    if ($ok) {
        for my $event ( @{ $self->events } ) {
            my $updated = $self->editor->data;
            $event->start_time( $updated->start_time );
            $event->update_time( $updated->update_time );
            $event->update_process( $updated->update_process );
            $event->state( $updated->state );
        }
    }

    return $ok || undef;
}

sub build_environment {
    my $self = shift;
    my $env = $self->environment;

    $$evn{target} = [];
    $$evn{event} = [];
    for my $e ( @{ $self->events } ) {
        for my $evn_part ( keys %{ $e->environment } ) {
            if ($env_part eq 'target') {
                push @{ $$evn{target} }, $e->environment->{target};
            } elsif ($env_part eq 'event') {
                push @{ $$evn{event} }, $e->environment->{event};
            } else {
                $$evn{$evn_part} = $e->environment->{$evn_part};
            }
        }
    }

    return $self;
}

1;
