package OpenILS::Application::Trigger::ModLoader;
use UNIVERSAL::require;

sub prefix { return 'OpenILS::Application::Trigger' }

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    my $mod_thing = shift;
    return undef unless ($mod_thing);

    my $self = bless {
        mod_thing => $mod_thing,
        module => $mod_thing->module(),
        handler => 'handler'
    } => $class;

    return $self->load;
}

sub loaded {
    my $self = shift;
    return undef unless (ref $self);

    my $l = shift;
    $self->{loaded} = $l if (defined $l);
    return $self->{loaded};
}

sub handler {
    my $self = shift;
    return undef unless (ref $self);

    my $h = shift;
    $self->{handler} = $h if $h;
    return $self->{handler};
}

sub module {
    my $self = shift;
    return undef unless (ref $self);

    my $m = shift;
    $self->{module} = $m if $m;
    return $self->{module};
}

sub load {
    my $self = shift;
    return undef unless (ref $self);

    my $m = shift || $self->module;
    my $h = shift || $self->handler;
    return 1 unless $m;

    my $loaded = $m->use;

    if (!$loaded) {
        $builtin_m = $self->prefix . "::$m";
        $loaded = $builtin_m->use;

        if (!$loaded) {
            if ($m =~ /::/o) {
                ($h = $m) =~ s/^.+::([^:]+)$/$1/o;
                $m =~ s/^(.+)::[^:]+$/$1/o;

                $loaded = $m->use;

                if (!$loaded) {
                    $h =  $self->handler;
                    $builtin_m = $self->prefix . "::$m";
                    $loaded = $m->use;

                    $m = $builtin_m if ($loaded);
                }
            } else {
                $loaded = $m->use;
            }
        } else {
            $m = $builtin_m;
        }
    }

    if ($loaded) {
        $self->module( $m );
        $self->handler( $h );
    }

    $self->loaded($loaded);
    return $self;
}

package OpenILS::Application::Trigger::ModRunner;
use base 'OpenILS::Application::Trigger::ModLoader';

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    my $m = shift;
    my $e = shift || {};

    my $self = $class->SUPER::new( $m );
    return undef unless ($self && $self->loaded);

    $self->environment( $e );
    return $self;
}

sub pass {
    my $old = shift;
    return undef unless (ref $old);

    my $class = ref($old);
    my $m = shift;

    my $self = $class->SUPER::new( $m );
    return undef unless ($self && $self->loaded);

    $self->environment( $old->environment );
    return $self;
}

sub environment {
    my $self = shift;
    return undef unless (ref $self);

    my $e = shift;
    $self->{environment} = $e if (defined $e);
    return $self->{environment};
}

sub final_result {
    my $self = shift;
    return undef unless (ref $self);

    my $r = shift;
    $self->{final_result} = $r if (defined $r);
    return $self->{final_result};
}

sub run {
    my $self = shift;
    return undef unless (ref $self && $self->loaded);

    $self->environment( shift );

    my $m = $self->module;
    my $h = $self->handler;
    my $e = $self->environment;
    $self->final_result( $m->$h( $e ) );

    return $self;
};

package OpenILS::Application::Trigger::ModRunner::Collector;
use base 'OpenILS::Application::Trigger::ModRunner';
sub prefix { return 'OpenILS::Application::Trigger::Collector' }

package OpenILS::Application::Trigger::ModRunner::Validator;
use base 'OpenILS::Application::Trigger::ModRunner';
sub prefix { return 'OpenILS::Application::Trigger::Validator' }

package OpenILS::Application::Trigger::ModRunner::Reactor;
use base 'OpenILS::Application::Trigger::ModRunner';
sub prefix { return 'OpenILS::Application::Trigger::Reactor' }

package OpenILS::Application::Trigger::ModRunner::Cleanup;
use base 'OpenILS::Application::Trigger::ModRunner';
sub prefix { return 'OpenILS::Application::Trigger::Cleanup' }

package OpenILS::Application::Trigger::ModStackRunner;
use base 'OpenILS::Application::Trigger::ModRunner';

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    my $m = shift;
    $m = [$m] unless (ref($m) =~ /ARRAY/o);

    my $e = shift || {};

    my $self = bless {
        runners => []
    } => $class;

    for my $mod ( @$m ) {
        my $r = $self->SUPER::new( $m );
        return undef unless ($r && $r->loaded);
        push @{$self->{runners}}, $r;
    }

    $self->loaded(1);

    return $self;
}

sub pass {
    my $old = shift;
    return undef unless (ref $old);

    my $class = ref($old);
    my $m = shift;

    my $self = $class->new( $m );
    return undef unless ($self && $self->loaded);

    $self->environment( $old->environment );
    return $self;
}

sub run {
    my $self = shift;
    return undef unless (ref $self && $self->loaded);

    $self->environment( shift );
    my $e = $self->environment;

    for my $r (@{$self->{runners}}) {
        my $m = $r->module;
        my $h = $r->handler;
        $r->final_result( $m->$h( $e ) );
    }

    return $self;
};

1;
