package OpenILS::Application::Trigger::Event;
use strict; use warnings;
use OpenSRF::EX qw/:try/;

use OpenSRF::Utils::Logger qw/:logger/;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Trigger::ModRunner;

my $log = 'OpenSRF::Utils::Logger';

sub new {
    my $class = shift;
    my $id = shift;
    my $editor = shift;
    $class = ref($class) || $class;

    return $id if (ref($id) && ref($id) == $class);

    my $standalone = $editor ? 0 : 1;
    $editor ||= new_editor();

    my $self = bless { id => $id, editor => $editor, standalone => $standalone } => $class;

    return $self->init()
}

sub init {
    my $self = shift;
    my $id = shift;

    return $self if ($self->event);

    $self->id( $id ); 
    $self->environment( {} ); 

    if (!$self->id) {
        $log->error("No Event ID provided");
        die "No Event ID provided";
    }

    return $self if (!$self->id);

    $self->event(
        $self->editor->retrieve_action_trigger_event([
            $self->id, {
                flesh => 2,
                flesh_fields => {
                    atev    => [ qw/event_def/ ],
                    atevdef => [ qw/hook env params/ ]
                }
            }
        ])
    );

    if ($self->event->state eq 'valid') {
        $self->valid(1);
    } elsif ($self->event->state eq 'invalid') {
        $self->valid(0);
    } elsif ($self->event->state eq 'reacting') {
        $self->valid(1);
    } elsif ($self->event->state eq 'reacted') {
        $self->valid(1);
        $self->reacted(1);
    } elsif ($self->event->state eq 'cleaning') {
        $self->valid(1);
        $self->reacted(1);
    } elsif ($self->event->state eq 'complete') {
        $self->valid(1);
        $self->reacted(1);
        $self->cleanedup(1);
    } elsif ($self->event->state eq 'error') {
        $self->valid(0);
        $self->reacted(0);
        $self->cleanedup(0);
    }


    $self->update_state('found') || die 'Unable to update event state';

    my $class = $self->_fm_class_by_hint( $self->event->event_def->hook->core_type );
    
    my $meth = "retrieve_" . $class;
    $meth =~ s/Fieldmapper:://;
    $meth =~ s/::/_/;
    
    $self->target( $self->editor->$meth( $self->event->target ) );

    return $self;
}

sub cleanup {
    my $self = shift;
    my $env = shift || $self->environment;

    return $self if (defined $self->cleanedup);

    if (defined $self->reacted) {
        $self->update_state( 'cleaning') || die 'Unable to update event state';
        try {
            my $cleanup = $self->reacted ? $self->event->event_def->cleanup_success : $self->event->event_def->cleanup_failure;
            if($cleanup) {
                $self->cleanedup(
                    OpenILS::Application::Trigger::ModRunner::Cleanup
                        ->new( $cleanup, $env)
                        ->run
                        ->final_result
                );
            } else {
                $self->cleanedup(1);
            }
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
    my $env = shift || $self->environment;

    return $self if (defined $self->reacted);

    if ($self->valid) {
        if ($self->event->event_def->group_field) { # can't react individually to a grouped definition
            $self->{reacted} = undef;
        } else {
            $self->update_state( 'reacting') || die 'Unable to update event state';
            try {
                $self->reacted(
                    OpenILS::Application::Trigger::ModRunner::Reactor
                        ->new( $self->event->event_def->reactor, $env )
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

sub unfind {
    my $self = shift;
    return undef unless (ref $self);

    die 'Cannot unfind a reacted event' if (defined $self->reacted);

    $self->update_state( 'pending' ) || die 'Unable to update event state';
    $self->{id} = undef;
    $self->{event} = undef;
    $self->{environment} = undef;
    return $self;
}

sub target {
    my $self = shift;
    return undef unless (ref $self);

    my $t = shift;
    $self->{target} = $t if (defined $t);
    return $self->{target};
}

sub standalone {
    my $self = shift;
    return undef unless (ref $self);

    my $t = shift;
    $self->{standalone} = $t if (defined $t);
    return $self->{standalone};
}

sub update_state {
    my $self = shift;
    return undef unless ($self && ref $self);

    my $state = shift;
    return undef unless ($state);

    my $fields = shift;

    if ($self->standalone) {
        $self->editor->xact_begin || return undef;
    }

    my $e = $self->editor->retrieve_action_trigger_event( $self->id );
    if (!$e) {
        $log->error( "Could not retrieve object ".$self->id." for update" ) if (!$e);
        return undef;
    }

    if ($fields && ref($fields)) {
        $e->$_($$fields{$_}) for (keys %$fields);
    }

    $log->info( "Retrieved object ".$self->id." for update" );
    $e->start_time( 'now' ) unless $e->start_time;
    $e->update_time( 'now' );
    $e->update_process( $$ );
    $e->state( $state );

    $e->clear_start_time() if ($e->state eq 'pending');

    my $ok = $self->editor->update_action_trigger_event( $e );
    if (!$ok) {
        $self->editor->xact_rollback if ($self->standalone);
        $log->error( "Update of event ".$self->id." failed" );
        return undef;
    } else {
        $e = $self->editor->data;
        $e = $self->editor->retrieve_action_trigger_event( $e ) if (!ref($e));
        if (!$e) {
            $log->error( "Update of event ".$self->id." did not return an object" );
            return undef;
        }
        $log->info( "Update of event ".$e->id." suceeded" );
        $ok = $self->editor->xact_commit if ($self->standalone);
    }

    if ($ok) {
        $self->event->start_time( $e->start_time );
        $self->event->update_time( $e->update_time );
        $self->event->update_process( $e->update_process );
        $self->event->state( $e->state );
    }

    return $ok || undef;
}

sub build_environment {
    my $self = shift;
    return $self if ($self->environment->{complete});

    $self->update_state( 'collecting') || die 'Unable to update event state';

    try {
   
        $self->environment->{target} = $self->target;
        $self->environment->{event} = $self->event;
        $self->environment->{template} = $self->event->event_def->template;

        $self->environment->{params}{ $_->param } = eval $_->value for ( @{$self->event->event_def->params} );
    
        for my $e ( @{$self->event->event_def->env} ) {
            my (@label, @path);
            @path = split(/\./, $e->path) if ($e->path);
            @label = split(/\./, $e->label) if ($e->label);
    
            $self->_object_by_path( $self->target, $e->collector, \@label, \@path );
        }

        if ($self->event->event_def->group_field) {
            my @group_path = split(/\./, $self->event->event_def->group_field);
            my $group_object = $self->_object_by_path( $self->target, undef, [], \@group_path );
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
    if ($rtype ne 'has_a') {
        $meth = 'search_';
        $multi = 1;
        $lfield = $context->Identity;
    }

    $meth .= $fclass;
    $meth =~ s/Fieldmapper:://;
    $meth =~ s/::/_/;

    my $ed = grep( /open-ils.cstore/, @{$fclass->Controller} ) ?
            $self->editor :
            new_rstore_editor();

    my $obj = $context->$step(); 

    if (!ref $obj) {
        $obj = $ed->$meth( 
            ($multi) ?
                { $ffield => $context->$lfield() } :
                $context->$lfield()
        );
    }

    if (@$path) {

        my $obj_list = [];
        if (!$multi || $rtype eq 'might_have') {
            $obj_list = [$obj] if ($obj);
        } else {
            $obj_list = $obj;
        }

        $self->_object_by_path( $_, $collector, $label, $path ) for (@$obj_list);

        $obj = $$obj_list[0] if (!$multi || $rtype eq 'might_have');
        $context->$step( $obj ) if ($obj && (!$label || !@$label));

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

        if ($label && @$label) {
            my $node = $self->environment;
            my $i = 0; my $max = scalar(@$label);
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
