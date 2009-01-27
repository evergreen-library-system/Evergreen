package OpenILS::Application::Trigger::Event;
use OpenSRF::EX qw/:try/;

use OpenSRF::Utils::Logger qw/:level/;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Trigger::ModRunner;

my $log = 'OpenSRF::Utils::Logger';

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    my $id = shift;
    return undef unless ($id);

    my $cstore = new_editor();
    my $event = $cstore->retrieve_action_trigger_event( $id );
    return undef unless ($event);

    return bless { id => $id, event => $event, environment => {}, editor => $cstore } => $class;
}

sub cleanup {
    my $self = shift;

    if (defined $self->reacted) {
        $self->update_state( 'cleaning') || throw 'Unable to update event state';
        try {
            my $cleanup = $self->reacted ? $self->definition->cleanup_success : $self->definition->cleanup_failure;
            $self->cleanedup(
                OpenILS::Application::Trigger::ModRunner
                    ->new( $cleanup, $self->environment )
                    ->run
                    ->final_result
            );
        } otherwise {
            $log->error( shift() );
            $self->update_state( 'error' ) || throw 'Unable to update event state';
        };

        if ($self->cleanedup) {
            $self->update_state( 'complete' ) || throw 'Unable to update event state';
        } else {
            $self->update_state( 'error' ) || throw 'Unable to update event state';
        }

    } else {
        $self->{cleanedup} = undef;
    }
    return $self;
}

sub react {
    my $self = shift;

    if ($self->valid) {
        if ($self->definition->group_field) { # can't react individually to a grouped definition
            $self->{reacted} = undef;
        } else {
            $self->update_state( 'reacting') || throw 'Unable to update event state';
            try {
                $self->reacted(
                    OpenILS::Application::Trigger::ModRunner
                        ->new( $self->definition->reactor, $self->environment )
                        ->run
                        ->final_result
                );
            } otherwise {
                $log->error( shift() );
                $self->update_state( 'error' ) || throw 'Unable to update event state';
            };

            if (defined $self->reacted) {
                $self->update_state( 'reacted' ) || throw 'Unable to update event state';
            } else {
                $self->update_state( 'error' ) || throw 'Unable to update event state';
            }
        }
    } else {
        $self->{reacted} = undef;
    }
    return $self;
}

sub validate {
    my $self = shift;

    return $self if (defined $self->valid);

    if ($self->build_environment->environment->{complete}) {
        $self->update_state( 'validating') || throw 'Unable to update event state';
        try {
            $self->valid(
                OpenILS::Application::Trigger::ModRunner
                    ->new( $self->definition->validator, $self->environment )
                    ->run
                    ->final_result
            );
        } otherwise {
            $log->error( shift() );
            $self->update_state( 'error' ) || throw 'Unable to update event state';
        };

        if (defined $self->valid) {
            if ($self->valid) {
                $self->update_state( 'valid' ) || throw 'Unable to update event state';
            } else {
                $self->update_state( 'invalid' ) || throw 'Unable to update event state';
            }
        } else {
            $self->update_state( 'error' ) || throw 'Unable to update event state';
        }
    } else {
        $self->{valid} = undef
    }

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

    my $e = shift;
    $self->{event} = $e if (defined $e);
    return $self->{event};
}

sub id {
    my $self = shift;
    return undef unless (ref $self);

    my $i = shift;
    $self->{id} = $i if (defined $i);
    return $self->{id};
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

sub target {
    my $self = shift;
    return undef unless (ref $self);

    my $t = shift;
    $self->{target} = $t if (defined $t);
    return $self->{target};
}

sub definition {
    my $self = shift;
    return undef unless (ref $self);

    my $d = shift;
    $self->{definition} = $d if (defined $d);
    return $self->{definition};
}

sub update_state {
    my $self = shift;
    return undef unless ($self && ref $self);

    my $state = shift || return undef;

    $self->editor->xact_begin || return undef;
    $self->event->update_time( 'now' );
    $self->event->update_process( $$ );
    $self->event->state( $state );
    $self->editor->update_action_trigger_event( $self->event );
    $self->editor->xact_commit || return undef;

}

sub build_environment {
    my $self = shift;
    return $self if ($self->environment->{complete});

    $self->update_state( 'collecting') || throw 'Unable to update event state';

    try {
        $self->definition( $self->editor->retrieve_action_trigger_event_definition( $self->event->event_def ) );
    
        $self->definition->hook( $self->editor->retrieve_action_trigger_hook( $self->definition->hook ) );
        $self->definition->validator( $self->editor->retrieve_action_trigger_validator( $self->definition->validator ) );
        $self->definition->reactor( $self->editor->retrieve_action_trigger_reactor( $self->definition->reactor ) );
        $self->definition->cleanup_success( $self->editor->retrieve_action_trigger_cleanup( $self->definition->cleanup_success ) ) if $self->definition->cleanup_success;
        $self->definition->cleanup_failure( $self->editor->retrieve_action_trigger_cleanup( $self->definition->cleanup_failure ) ) if $self->definition->cleanup_failure;
    
        my $class = $self->_fm_class_by_hint( $self->definition->hook->core_type );
    
        my $meth = "retreive_" . $class;
        $meth =~ s/Fieldmapper:://;
        $meth =~ s/::/_/;
    
        $self->target( $self->editor->$meth( $self->event->target ) );
        $self->environment->{target} = $self->target;
        $self->environment->{event} = $self->event->to_bare_hash;
        $self->environment->{template} = $self->definition->template;
    
        my @env_list = $self->editor->search_action_trigger_environment( { event_def => $self->event->event_def } );
        my @param_list = $self->editor->search_action_trigger_params( { event_def => $self->event->event_def } );
    
        $self->environment->{params}{ $_->param } = eval $_->value for ( @param_list );
    
        for my $e ( @env_list ) {
            my (@label, @path);
            @path = split('.', $e->path) if ($e->path);
            @label = split('.', $e->label) if ($e->label);
    
            my $collector = $e->collector;
            $self->_object_by_path( $target, $collector, \@label, \@path );
        }
    
        $self->environment->{complete} = 1;
    } otherwise {
        $log->error( shift() );
        $self->update_state( 'error' ) || throw 'Unable to update event state';
    };

    if ($self->environment->{complete})
        $self->update_state( 'collected' ) || throw 'Unable to update event state';
    } else {
        $self->update_state( 'error' ) || throw 'Unable to update event state';
    }

    return $self;
}

sub _fm_class_by_hint {
    my $self = shift;
    my $hint = shift;

    my ($class) = grep {
        Fieldmapper->publish_fieldmapper->{$_}->{hint} eq $hint
    } keys %{ Fieldmapper->publish_fieldmapper };

    return $class;
}

sub _object_by_path {
    my $self = shift;
    my $context = shift;
    my $collector = shift;
    my $label = shift;
    my $path = shift;

    my $step = shift(@$path);
    
    my $fhint = Fieldmapper->publish_fieldmapper->{$context->class_name}{links}{$step}{class};
    my $fclass = $self->_fm_class_by_hint( $fhint );

    my $ffield = Fieldmapper->publish_fieldmapper->{$context->class_name}{links}{$step}{key};
    my $rtype = Fieldmapper->publish_fieldmapper->{$context->class_name}{links}{$step}{reltype};

    my $meth = 'retrieve_';
    my $multi = 0;
    my $lfield = $step;
    if ($rtype eq 'has_many') {
        $meth = 'search_';
        $multi = 1;
        $lfield = $context->Identity;
    }

    $meth .= $fclass;
    $meth =~ s/Fieldmapper:://;
    $meth =~ s/::/_/;

    my $obj = $self->editor->$meth( { $ffield => $context->$lfield() } );

    if (@$path) {

        my $obj_list = [];
        if (!$multi) {
            $obj_list = [$obj] if ($obj);
        } else {
            $obj_list = $obj;
        }

        $self->_object_by_path( $_, $collector, $label, $path ) for (@$obj_list);

        $obj = $$obj_list[0] if (!$multi);
        $context->$step( $obj ) if ($obj && !$label);

    } else {

        if ($collector) {
            my $obj_list = [$obj] if ($obj && !$multi);
            $obj_list = $obj if ($multi);

            my @new_obj_list;
            for my $o ( @$obj_list ) {
                push @new_obj_list,
                    OpenILS::Application::Trigger::ModRunner
                        ->new( $collector, $o )
                        ->run
                        ->final_result
            }

            if (!$multi) {
                $obj = $new_obj_list[0];
            } else {
                $obj = \@new_obj_list;
            }
        }

        if ($label) {
            my $node = $self->environment;
            my $i = 0; my $max = scalar(@$label) - 1;
            for (; $i < $max; $i++) {
                my $part = $$label[$i];
                $$node{$part} ||= {};
                $node = $$node{$part};
            }
            $$node{$$label[-1]} = $obj;
        } else {
            $context->$step( $obj ) if ($obj);
        }
    }

    return $obj;
}

1;
