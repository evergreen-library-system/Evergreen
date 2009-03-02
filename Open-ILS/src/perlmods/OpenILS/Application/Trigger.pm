package OpenILS::Application::Trigger;
use strict; use warnings;
use OpenILS::Application;
use base qw/OpenILS::Application/;

use OpenSRF::EX qw/:try/;

use OpenSRF::AppSession;
use OpenSRF::Utils::SettingsClient;
use OpenSRF::Utils::Logger qw/:level/;
use OpenSRF::Utils qw/:datetime/;

use DateTime;
use DateTime::Format::ISO8601;

use OpenILS::Utils::Fieldmapper;
use OpenILS::Utils::CStoreEditor q/:funcs/;
use OpenILS::Application::Trigger::Event;
use OpenILS::Application::Trigger::EventGroup;


my $log = 'OpenSRF::Utils::Logger';

sub initialize {}
sub child_init {}

sub create_events_for_object {
    my $self = shift;
    my $client = shift;
    my $key = shift;
    my $target = shift;
    my $location = shift;

    my $ident = $target->Identity;
    my $ident_value = $target->$ident();

    my $editor = new_editor(xact=>1);

    my $hooks = $editor->search_action_trigger_hook(
        { key       => $key,
          core_type => $target->json_hint
        }
    );

    my %hook_hash = map { ($_->key, $_) } @$hooks;

    my $orgs = $editor->json_query({ from => [ 'actor.org_unit_ancestors' => $location ] });
    my $defs = $editor->search_action_trigger_event_definition([
        { hook   => [ keys %hook_hash ],
          owner  => [ map { $_->{id} } @$orgs  ],
          active => 't'
        },
        { idlist => 1 }
    ]);

    for my $def ( @$defs ) {

        my $date = DateTime->now;

        if ($hook_hash{$def->hook}->passive eq 'f') {

            if (my $dfield = $def->delay_field) {
                if ($target->$dfield()) {
                    $date = DateTime::Format::ISO8601->new->parse_datetime( clense_ISO8601($target->$dfield) );
                } else {
                    next;
                }
            }

            $date->add( seconds => interval_to_seconds($def->delay) );
        }

        my $event = Fieldmapper::action_trigger::event->new();
        $event->target( $ident_value );
        $event->event_def( $def->id );
        $event->run_time( $date->strftime( '%F %T%z' ) );

        $editor->create_action_trigger_event( $event );

        $client->respond( $event->id );
    }

    $editor->commit;

    return undef;
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.event.autocreate',
    method   => 'create_events_for_object',
    api_level=> 1,
    stream   => 1,
    argc     => 3
);


sub fire_single_event {
    my $self = shift;
    my $client = shift;
    my $event_id = shift;

    my $e = OpenILS::Application::Trigger::Event->new($event_id);

    if ($e->validate->valid) {
        $e->react->cleanup;
    }

    return {
        valid     => $e->valid,
        reacted   => $e->reacted,
        cleanedup => $e->cleanedup,
        event     => $e->event
    };
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.event.fire',
    method   => 'fire_single_event',
    api_level=> 1,
    argc     => 1
);

sub fire_event_group {
    my $self = shift;
    my $client = shift;
    my $events = shift;

    my $e = OpenILS::Application::Trigger::EventGroup->new(@$events);

    if ($e->validate->valid) {
        $e->react->cleanup;
    }

    return {
        valid     => $e->valid,
        reacted   => $e->reacted,
        cleanedup => $e->cleanedup,
        events    => $e->events
    };
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.event_group.fire',
    method   => 'fire_event_group',
    api_level=> 1,
    argc     => 1
);

sub pending_events {
    my $self = shift;
    my $client = shift;

    my $editor = new_editor();

    return $editor->search_action_trigger_event([
        { state => 'pending', run_time => {'<' => 'now'} },
        { idlist=> 1 }
    ]);
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.event.find_pending',
    method   => 'pending_events',
    api_level=> 1
);


sub grouped_events {
    my $self = shift;
    my $client = shift;

    my ($events) = $self->method_lookup('open-ils.trigger.event.find_pending')->run();

    my %groups = ( '*' => [] );

    for my $e_id ( @$events ) {
        my $e = OpenILS::Application::Trigger::Event->new($e_id);
        if ($e->validate->valid) {
            if (my $group = $e->event->event_def->group_field) {

                # split the grouping link steps
                my @steps = split '.', $group;

                # find the grouping object
                my $node = $e->target;
                $node = $node->$_() for ( @steps );

                # get the pkey value for the grouping object on this event
                my $node_ident = $node->Identity;
                my $ident_value = $node->$node_ident();

                # push this event onto the event+grouping_pkey_value stack
                $groups{$e->event->event_def->id}{$ident_value} ||= [];
                push @{ $groups{$e->event->event_def->id}{$ident_value} }, $e;
            } else {
                # it's a non-grouped event
                push @{ $groups{'*'} }, $e;
            }
        }
    }

    return \%groups;
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.event.find_pending_by_group',
    method   => 'grouped_events',
    api_level=> 1
);

sub run_all_events {
    my $self = shift;
    my $client = shift;

    my ($groups) = $self->method_lookup('open-ils.trigger.event.find_pending_by_group')->run();

    for my $def ( %$groups ) {
        if ($def eq '*') {
            for my $event ( @{ $$groups{'*'} } ) {
                $client->respond(
                    $self
                        ->method_lookup('open-ils.trigger.event.fire')
                        ->run($event)
                );
            }
        } else {
            my $defgroup = $$groups{$def};
            for my $ident ( keys %$defgroup ) {
                $client->respond(
                    $self
                        ->method_lookup('open-ils.trigger.event_group.fire')
                        ->run($$defgroup{$ident})
                );
            }
        }
    }
                
            
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.event.run_all_pending',
    method   => 'run_all_events',
    api_level=> 1
);


1;
