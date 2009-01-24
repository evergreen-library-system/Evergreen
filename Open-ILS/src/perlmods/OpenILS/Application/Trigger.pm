package OpenILS::Application::Trigger;
use OpenILS::Application;
use base qw/OpenILS::Application/;

use OpenSRF::EX qw/:try/;

use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:level/;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Trigger::ModRunner;


my $log = 'OpenSRF::Utils::Logger';

sub initialize {}
sub child_init {}

sub build_env {
    my $event = shift;
    my $environment = shift || {};
    my $cstore = new_editor();

    my $def = $cstore->retrieve_action_trigger_event_definition( $event->event_def );
    my $hook = $cstore->retrieve_action_trigger_hook( $def->hook );
    my $class = _fm_class_by_hint( $hook->core_type );

    my $meth = "retreive_" . $class;
    $meth =~ s/Fieldmapper:://;
    $meth =~ s/::/_/;

    my $target = $cstore->$meth( $event->target );
    $$environment{target} = $target;
    $$environment{event} = $event->to_bare_hash;

    my @env_list = $cstore->search_action_trigger_environment( { event_def => $event->event_def } );
    my @param_list = $cstore->search_action_trigger_params( { event_def => $event->event_def } );

    $$environment{params}{ $_->param } = eval $_->value for ( @param_list );

    for my $e ( @env_list ) {
        my (@label, @path);
        @path = split('.', $e->path) if ($e->path);
        @label = split('.', $e->label) if ($e->label);

        my $collector = $e->collector;
        _object_by_path( $cstore, $target, $collector, \@label, $environment, @path );
    }

    return $environment;
}

sub _fm_class_by_hint {
    my $hint = shift;

    my ($class) = grep {
        OpenILS::Utils::Fieldmapper->publish_fieldmapper->{$_}->{hint} eq $hint
    } keys %{ OpenILS::Utils::Fieldmapper->publish_fieldmapper };

    return $class;
}

sub _object_by_path {
    my $cstore = shift;
    my $context = shift;
    my $collector = shift;
    my $label = shift;
    my $env = shift;
    my @path = @_;

    my $step = shift(@path);
    
    my $fhint = OpenILS::Utils::Fieldmapper->publish_fieldmapper->{$context->class_name}{links}{$step}{class};
    my $fclass = _fm_class_by_hint( $fhint );

    my $ffield = OpenILS::Utils::Fieldmapper->publish_fieldmapper->{$context->class_name}{links}{$step}{key};
    my $rtype = OpenILS::Utils::Fieldmapper->publish_fieldmapper->{$context->class_name}{links}{$step}{reltype};

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

    my $obj = $cstore->$meth( { $ffield => $context->$lfield() } );

    if (@path) {

        my $obj_list = [];
        if (!$multi) {
            $obj_list = [$obj] if ($obj);
        } else {
            $obj_list = $obj;
        }

        _object_by_path( $cstore, $_, $collector, $label, $env, @path ) for (@$obj_list);

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
                        ->final_result;
            }

            if (!$multi) {
                $obj = $new_obj_list[0];
            } else {
                $obj = \@new_obj_list;
            }
        }

        if ($label) {
            my $node = $env;
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
