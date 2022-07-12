package OpenILS::Application::Trigger::EventGroup;
use strict; use warnings;
use OpenILS::Application::Trigger::Event;
use base 'OpenILS::Application::Trigger::Event';
use OpenSRF::EX qw/:try/;

use OpenSRF::Utils::Logger qw/$logger/;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Trigger::ModRunner;

my $log = 'OpenSRF::Utils::Logger';

sub new_impl {
    my $class = shift;
    my @ids = @{shift()};
    my $nochanges = shift;

    $class = ref($class) || $class;

    my $editor = new_editor(xact=>1);

    my $self = bless {
        environment => {},
        events      => [
            map {
                ref($_) ?
                    do { $_->standalone(0); $_->editor($editor); $_ } :
                    OpenILS::Application::Trigger::Event->new($_, $editor, $nochanges)
            } @ids
        ],
        ids         => [ map { ref($_) ? $_->id : $_ } @ids ],
        editor      => $editor
    } => $class;


    $self->editor->xact_commit; # flush out those updates
    $self->editor->xact_begin;

    return $self;
}

sub new_nochanges {
    my $class = shift;
    my @ids = @_;

    return new_impl($class, \@ids, 1);
}

sub new {
    my $class = shift;
    my @ids = @_;

    return new_impl($class, \@ids);
}

sub react {
    my $self = shift;

    return $self if (defined $self->reacted);

    if ($self->valid) {
        $self->update_state( 'reacting') || die 'Unable to update event group state';
        $self->build_environment;

        try {
            my $env = $self->environment;
            my $reactor = OpenILS::Application::Trigger::ModRunner::Reactor->new(
                $self->event->event_def->reactor,
                $env
            );

            $self->reacted( $reactor->run->final_result);

            if ($env->{usr_message}{usr} && $env->{usr_message}{template}) {
                my $message_template_output =
                    $reactor->pass('ProcessMessage')->run->final_result;

                if ($message_template_output) {
                    my $usr_message = Fieldmapper::actor::usr_message->new;
                    $usr_message->title( $env->{usr_message}{title} || $self->event->event_def->name );
                    $usr_message->message( $message_template_output );
                    $usr_message->usr( $env->{usr_message}{usr}->id );
                    $usr_message->sending_lib( $env->{usr_message}{sending_lib}->id );
                    $usr_message->pub('t');

                    if ($self->editor->xact_begin) {
                        if ($self->editor->create_actor_usr_message( $usr_message )) {
                            $self->editor->xact_commit;
                        } else {
                            $self->editor->xact_rollback;
                        }
                    }
                }
            }

        } otherwise {
            $log->error("Event reacting failed with ". shift() );
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
        $self->{ids} = [ map { $_->id } @valid_events ];
        $self->editor->xact_commit;
    } otherwise {
        $log->error("Event group validation failed with ". shift() );
        $self->editor->xact_rollback;
        $self->update_state( 'error' ) || die 'Unable to update event group state';
    };

    return $self;
}
 
sub revalidate_test {
    my $self = shift;

    $self->editor->xact_begin;

    my @valid_events;
    try {
        for my $event ( @{ $self->events } ) {
            push @valid_events, $event->id if $event->revalidate_test;
        }
        $self->editor->xact_rollback;
    } otherwise {
        $log->error("Event group validation failed with ". shift());
        $self->editor->xact_rollback;
    };

    return \@valid_events;
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

    return $self->{events}[0]->event;
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

    my $fields = shift;

    $self->editor->xact_begin || return undef;

    my @oks;
    my $ok;
    my $last_updated;
    for my $event ( @{ $self->events } ) {
        my $e = $self->editor->retrieve_action_trigger_event( $event->id );
        $e->start_time( 'now' ) unless $e->start_time;
        $e->update_time( 'now' );
        $e->update_process( $$ );
        $e->state( $state );

        $e->clear_start_time() if ($e->state eq 'pending');

        $e->complete_time('now')
            if ($e->state eq 'complete' && !$e->complete_time);

        if ($fields && ref($fields)) {
            $e->$_($$fields{$_}) for (keys %$fields);
        }

        my $ok = $self->editor->update_action_trigger_event( $e );
        if ($ok) {
            push @oks, $ok;
            $last_updated = $e->id;
        }
    }

    if (scalar(@oks) < scalar(@{ $self->ids })) {
        $self->editor->xact_rollback;
        return undef;
    } 

    my $updated = $self->editor->retrieve_action_trigger_event($last_updated);
    $ok = $self->editor->xact_commit;

    if ($ok) {
        for my $event ( @{ $self->events } ) {
            my $e = $event->event;
            $e->start_time( $updated->start_time );
            $e->update_time( $updated->update_time );
            $e->update_process( $updated->update_process );
            $e->state( $updated->state );
        }
    }

    return $ok || undef;
}

sub findEvent {
    my $self = shift;
    my $member = shift;

    $member = $member->id if (ref($member));

    my @list = grep { $member == $_->id } @{ $self->events };

    return shift(@list);
}

sub build_environment {
    my $self = shift;
    my $env = $self->environment;

    $$env{EventProcessor} = $self;
    $$env{target} = [];
    $$env{event} = [];
    $$env{user_data} = [];
    for my $e ( @{ $self->events } ) {
        for my $env_part ( keys %{ $e->environment } ) {
            next if ($env_part eq 'EventProcessor');
            if ($env_part eq 'target') {
                push @{ $$env{target} }, $e->environment->{target};
            } elsif ($env_part eq 'event') {
                push @{ $$env{event} }, $e->environment->{event};
            } elsif ($env_part eq 'user_data') {
                push @{ $$env{user_data} }, $e->environment->{user_data};
            } else {
                $$env{$env_part} = $e->environment->{$env_part};
            }
        }
    }

    return $self;
}

1;
