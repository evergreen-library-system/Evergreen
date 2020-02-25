package OpenILS::Application::Trigger::Event;
use strict; use warnings;
use OpenSRF::EX qw/:try/;
use OpenSRF::Utils::JSON;
use OpenSRF::Utils::Logger qw/$logger/;
use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Trigger::ModRunner;
use Safe;

my $log = 'OpenSRF::Utils::Logger';

sub invalidate {
    my $class = shift;
    my @events = @_;

    # if called as an instance method
    unshift(@events,$class) if ref($class);

    my $e = new_editor();
    $e->xact_begin;

    map {
        $_->editor($e);
        $_->standalone(0);
        $_->update_state('invalid');
    } @events;

    $e->commit;

    return @events;
}

sub new {
    my $class = shift;
    my $id = shift;
    my $editor = shift;
    my $nochanges = shift; # no guarantees, yet...
    $class = ref($class) || $class;

    my $standalone = $editor ? 0 : 1;
    $editor ||= new_editor();

    if (ref($id) && ref($id) eq $class) {
        $id->environment->{EventProcessor} = $id
             if ($id->environment->{complete}); # in case it came over an opensrf tube
        $id->editor( $editor );
        $id->standalone( $standalone );
        return $id;
    }

    my $self = bless { id => $id, editor => $editor, standalone => $standalone, nochanges => $nochanges } => $class;

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

    if ($self->standalone) {
        $self->editor->xact_begin || return undef;
    }

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

    if ($self->standalone) {
        $self->editor->xact_rollback || return undef;
    }

    $self->user_data(OpenSRF::Utils::JSON->JSON2perl( $self->event->user_data ))
        if (defined( $self->event->user_data ));

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

    unless ($self->nochanges) {
        $self->update_state('found') || die 'Unable to update event state';
    }

    my $class = $self->_fm_class_by_hint( $self->event->event_def->hook->core_type );
    
    my $meth = "retrieve_" . $class;
    $meth =~ s/Fieldmapper:://;
    $meth =~ s/::/_/;
    
    if ($self->standalone) {
        $self->editor->xact_begin || return undef;
    }

    $self->target( $self->editor->$meth( $self->event->target ) );

    if ($self->standalone) {
        $self->editor->xact_rollback || return undef;
    }

    unless ($self->target) {
        $self->update_state('invalid') unless $self->nochanges;
        $self->valid(0);
    }

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
            $log->error("Event cleanup failed with ". shift() );
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
            $log->error("Event validation failed with ". shift() );
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
 
sub revalidate_test {
    my $self = shift;

    if ($self->build_environment->environment->{complete}) {
        try {
            $self->valid(
                OpenILS::Application::Trigger::ModRunner::Validator->new(
                    $self->event->event_def->validator,
                    $self->environment
                )->run->final_result
            );
        } otherwise {
            $log->error("Event revalidation failed with ". shift());
        };

        return 1 if defined $self->valid and $self->valid;
        return 0;
    }

    $logger->error(
        "revalidate: could not build environment for event " .
        $self->event->id
    );
    return 0;
}
 
sub cleanedup {
    my $self = shift;
    return undef unless (ref $self);

    my $c = shift;
    $self->{cleanedup} = $c if (defined $c);
    return $self->{cleanedup};
}

sub user_data {
    my $self = shift;
    return undef unless (ref $self);

    my $r = shift;
    $self->{user_data} = $r if (defined $r);
    return $self->{user_data};
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

sub nochanges {
    # no guarantees, yet.
    my $self = shift;
    return undef unless (ref $self);

    my $e = shift;
    $self->{nochanges} = $e if (defined $e);
    return $self->{nochanges};
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
    $e->complete_time( 'now' ) if ($e->state eq 'complete');

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

my $current_environment;

sub build_environment {
    my $self = shift;
    return $self if ($self->environment->{complete});

    $self->update_state( 'collecting') || die 'Unable to update event state';

    try {
   
        my $compartment = new Safe;
        $compartment->permit(':default','require','dofile','caller');
        $compartment->share('$current_environment');

        $self->environment->{EventProcessor} = $self;
        $self->environment->{target} = $self->target;
        $self->environment->{event} = $self->event;
        $self->environment->{template} = $self->event->event_def->template;
        $self->environment->{usr_message}{template} = $self->event->event_def->message_template;
        $self->environment->{usr_message}{title} = $self->event->event_def->message_title;
        $self->environment->{user_data} = $self->user_data;

        $current_environment = $self->environment;

        $self->environment->{params}{ $_->param } = $compartment->reval($_->value) for ( @{$self->event->event_def->params} );
    
        for my $e ( @{$self->event->event_def->env} ) {
            my (@label, @path);
            @path = split(/\./, $e->path) if ($e->path);
            @label = split(/\./, $e->label) if ($e->label);
    
            $self->_object_by_path( $self->target, $e->collector, \@label, \@path );
        }

        if ($self->event->event_def->group_field) {
            my @group_path = split(/\./, $self->event->event_def->group_field);
            pop(@group_path); # the last part is a field, should not get fleshed
            my $group_object = $self->_object_by_path( $self->target, undef, [], \@group_path ) if (@group_path);
        }

        if ($self->event->event_def->message_usr_path and $self->environment->{usr_message}{template}) {
            my @usr_path = split(/\./, $self->event->event_def->message_usr_path);
            $self->_object_by_path( $self->target, undef, [qw/usr_message usr/], \@usr_path );

            if ($self->event->event_def->message_library_path) {
                my @library_path = split(/\./, $self->event->event_def->message_library_path);
                $self->_object_by_path( $self->target, undef, [qw/usr_message sending_lib/], \@library_path );
            } else {
                $self->_object_by_path( $self->event->event_def, undef, [qw/usr_message sending_lib/], ['owner'] );
            }
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
        OpenILS::Application->publish_fieldmapper->{$_}->{hint} eq $hint
    } keys %{ OpenILS::Application->publish_fieldmapper };

    return $class;
}

my %_object_by_path_cache = ();
sub ClearObjectCache {
    for my $did ( keys %_object_by_path_cache ) {
        my $phash = $_object_by_path_cache{$did};
        for my $path ( keys %$phash ) {
            my $shash = $$phash{$path};
            for my $fhint ( keys %$shash ) {
                my $hhash = $$shash{$fhint};
                for my $step ( keys %$hhash ) {
                    my $fhash = $$hhash{$step};
                    for my $ffield ( keys %$fhash ) {
                        my $lhash = $$fhash{$ffield};
                        for my $lfield ( keys %$lhash ) {
                            delete $$lhash{$lfield};
                        }
                        delete $$fhash{$ffield};
                    }
                    delete $$hhash{$step};
                }
                delete $$shash{$fhint};
            }
            delete $$phash{$path};
        }
        delete $_object_by_path_cache{$did};
    }
}
        
sub _object_by_path {
    my $self = shift;
    my $context = shift;
    my $collector = shift;
    my $label = shift;
    my $path = shift;
    my $ed = shift;
    my $red = shift;

    my $outer = 0;
    if (!$ed) {
        $ed = new_editor(xact=>1);
        $outer = 1;
    }

    my $step = shift(@$path);

    my $fhint = OpenILS::Application->publish_fieldmapper->{$context->class_name}{links}{$step}{class};
    my $fclass = $self->_fm_class_by_hint( $fhint );

    OpenSRF::EX::ERROR->throw(
        "$step is not a field on ".$context->class_name."  Please repair the environment.")
        unless $fhint;

    my $ffield = OpenILS::Application->publish_fieldmapper->{$context->class_name}{links}{$step}{key};
    my $rtype = OpenILS::Application->publish_fieldmapper->{$context->class_name}{links}{$step}{reltype};

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
    $meth =~ s/::/_/g;

    my $obj = $context->$step(); 

    $logger->debug(
        sprintf "_object_by_path(): meth=%s, obj=%s, multi=%s, step=%s, lfield=%s",
        map {defined($_)? $_ : ''} ($meth,  $obj,   $multi,   $step,   $lfield)
    );

    if (!ref $obj) {

        my $lval = $context->$lfield();

        if(defined $lval) {

            my $def_id = $self->event->event_def->id;
            my $str_path = join('.', @$path);

            my @params = (($multi) ? { $ffield => $lval } : $lval);
            @params = ([@params], {substream => 1}) if $meth =~ /^search/;

            $obj = $_object_by_path_cache{$def_id}{$str_path}{$fhint}{$step}{$ffield}{$lval} ||
                (
                    (grep /cstore/, @{
                        OpenILS::Application->publish_fieldmapper->{$fclass}{controller}
                    }) ? $ed : ($red ||= new_rstore_editor(xact=>1))
                )->$meth(@params);

            $_object_by_path_cache{$def_id}{$str_path}{$fhint}{$step}{$ffield}{$lval} ||= $obj;
        }
    }

    if (@$path) {

        my $obj_list = [];
        if (!$multi) {
            $obj_list = [$obj] if ($obj);
        } else {
            $obj_list = $obj;
        }

        for (@$obj_list) {
            my @path_clone = @$path;
            $self->_object_by_path( $_, $collector, $label, \@path_clone, $ed, $red );
        }

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
            my $i = 0; my $max = scalar(@$label) - 1;
            for (; $i < $max; $i++) {
                my $part = $$label[$i];
                $$node{$part} ||= {};
                $node = $$node{$part};
            }
            $$node{$$label[-1]} = $obj;
        } else {
            $obj = $$obj[0] if $rtype eq 'might_have' and ref($obj) eq 'ARRAY';
            $context->$step( $obj ) if ($obj);
        }
    }

    if ($outer) {
        $ed->rollback;
        $red->rollback if $red;
    }
    return $obj;
}

1;
