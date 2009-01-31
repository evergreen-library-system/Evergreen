package OpenILS::Application::Trigger::Event;
use OpenSRF::EX qw/:try/;

use OpenSRF::Utils::Logger qw/:level/;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Trigger::ModRunner;

my $log = 'OpenSRF::Utils::Logger';

sub new {
    my $class = shift;
    my $id = shift;
    $class = ref($class) || $class;

    my $self = bless { id => $id, editor => new_editor() } => $class;

    return $self->init()
}

sub init {
    my $self = shift;
    my $id = shift;

    return $self if ($self->event);

    $self->id( $id ); 
    $self->environment( {} ); 

    return $self if (!$self->id);

    $self->event(
        $self->editor->retrieve_action_trigger_event([
            $self->id, {
                flesh => 2,
                flesh_fields => {
                    atev    => [ 'event_def' ],
                    atevdef => [ 'hook' ]
                }
            }
        ])
    );

    my $class = $self->_fm_class_by_hint( $self->event->event_def->hook->core_type );
    
    my $meth = "retreive_" . $class;
    $meth =~ s/Fieldmapper:://;
    $meth =~ s/::/_/;
    
    $self->target( $self->editor->$meth( $self->event->target ) );

    return $self;
}

sub cleanup {
    my $self = shift;

    if (defined $self->reacted) {
        $self->update_state( 'cleaning') || die 'Unable to update event state';
        try {
            my $cleanup = $self->reacted ? $self->event->event_def->cleanup_success : $self->event->event_def->cleanup_failure;
            $self->cleanedup(
                OpenILS::Application::Trigger::ModRunner::Cleanup
                    ->new( $cleanup, $self->environment )
                    ->run
                    ->final_result
            );
        } otherwise {
            $log->error( shift() );
            $self->update_state( 'error' ) || die 'Unable to update event state';
        };

        if ($self->cleanedup) {
            $self->update_state( 'complete' ) || die 'Unable to update event state';
        } else {
            $self->update_state( 'error' ) || die 'Unable to update event state';
        }

    } else {
        $self->{cleanedup} = undef;
    }
    return $self;
}

sub react {
    my $self = shift;

    if ($self->valid) {
        if ($self->event->event_def->group_field) { # can't react individually to a grouped definition
            $self->{reacted} = undef;
        } else {
            $self->update_state( 'reacting') || die 'Unable to update event state';
            try {
                $self->reacted(
                    OpenILS::Application::Trigger::ModRunner::Reactor
                        ->new( $self->event->event_def->reactor, $self->environment )
                        ->run
                        ->final_result
                );
            } otherwise {
                $log->error( shift() );
                $self->update_state( 'error' ) || die 'Unable to update event state';
            };

            if (defined $self->reacted) {
                $self->update_state( 'reacted' ) || die 'Unable to update event state';
            } else {
                $self->update_state( 'error' ) || die 'Unable to update event state';
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
        $self->update_state( 'validating') || die 'Unable to update event state';
        try {
            $self->valid(
                OpenILS::Application::Trigger::ModRunner::Validator
                    ->new( $self->event->event_def->validator, $self->environment )
                    ->run
                    ->final_result
            );
        } otherwise {
            $log->error( shift() );
            $self->update_state( 'error' ) || die 'Unable to update event state';
        };

        if (defined $self->valid) {
            if ($self->valid) {
                $self->update_state( 'valid' ) || die 'Unable to update event state';
            } else {
                $self->update_state( 'invalid' ) || die 'Unable to update event state';
            }
        } else {
            $self->update_state( 'error' ) || die 'Unable to update event state';
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

sub update_state {
    my $self = shift;
    return undef unless ($self && ref $self);

    my $state = shift;
    return undef unless ($state);

    $self->editor->xact_begin || return undef;

    my $e = $self->editor->retrieve_action_trigger_event( $self->id );
    $e->update_time( 'now' );
    $e->update_process( $$ );
    $e->state( $state );
    $self->editor->update_action_trigger_event( $e );

    return $self->editor->xact_commit || undef;
}

sub build_environment {
    my $self = shift;
    return $self if ($self->environment->{complete});

    $self->update_state( 'collecting') || die 'Unable to update event state';

    try {
   
        $self->environment->{target} = $self->target;
        $self->environment->{event} = $self->event;
        $self->environment->{template} = $self->event->event_def->template;
    
        my @env_list = $self->editor->search_action_trigger_environment( { event_def => $self->event->event_def } );
        my @param_list = $self->editor->search_action_trigger_params( { event_def => $self->event->event_def } );
    
        $self->environment->{params}{ $_->param } = eval $_->value for ( @param_list );
    
        for my $e ( @env_list ) {
            my (@label, @path);
            @path = split('.', $e->path) if ($e->path);
            @label = split('.', $e->label) if ($e->label);
    
            $self->_object_by_path( $self->event->target, $e->collector, \@label, \@path );
        }
    
        $self->environment->{complete} = 1;
    } otherwise {
        $log->error( shift() );
        $self->update_state( 'error' ) || die 'Unable to update event state';
    };

    if ($self->environment->{complete}) {
        $self->update_state( 'collected' ) || die 'Unable to update event state';
    } else {
        $self->update_state( 'error' ) || die 'Unable to update event state';
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
                    OpenILS::Application::Trigger::ModRunner::Collector
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
