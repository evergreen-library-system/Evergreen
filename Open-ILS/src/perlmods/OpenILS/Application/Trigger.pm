package OpenILS::Application::Trigger;
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

    my $hooks = $editor->search_action_trigger_hook([
        { key       => $key,
          core_type => $target->json_hint
        },
        { idlist    => 1 }
    ]);

    my %hook_hash = map { ($_->id, $_) } @$hooks;

    my $orgs = $editor->json_query({ from => [ 'actor.org_unit_ancestors' => $location ] });
    my $defs = $editor->search_action_trigger_event_definition([
        { hook   => $hooks,
          owner  => [ map { $_->{id} } @$orgs ],
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
        $event->run_time( $date->strftime( '%G %T%z' ) );

        $event = $editor->create_action_trigger_event( $event );

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

sub run_events {
    my $self = shift;
    my $client = shift;
    my $events = shift; # expects events ready for reaction

    my $env = {};
    if (ref($events) eq 'ARRAY') {
        $$evn{target} = [];
        $$evn{event} = [];
        for my $e ( @$events ) {
            for my $evn_part ( keys %{ $e->environment } ) {
                if ($env_part eq 'target') {
                    push @{ $$evn{target} }, $e->environment->{target};
                } elsif ($env_part eq 'event') {
                    push @{ $$evn{event} }, $e->environment->{event};
                } else {
                    push @{ $$evn{$evn_part} }, $e->environment->{$evn_part};
                }
            }
        }
    } else {
        $env = $events->environment;
        $events = [$events];
    }

    my @event_list;
    for my $e ( @$events ) {
        next unless ($e->valid);
        push @event_list, $e;
    }

    $event_list[0]->react( $env );
    $event_list[0]->cleanup( $env );

    return {
        reacted   => $event_list[0]->reacted,
        cleanedup => $event_list[0]->cleanedup,
        events    => @event_list == 1 ? $event_list[0] : \@event_list
    };
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.event.run_validated',
    method   => 'fire_single_event',
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
            if (my $group = $event->event->event_def->group_field) {

                # split the grouping link steps
                my @steps = split '.', $group;

                # find the grouping object
                my $node = $event->target;
                $node = $node->$_() for ( @steps );

                # get the pkey value for the grouping object on this event
                my $node_ident = $node->Identity;
                my $ident_value = $node->$node_ident();

                # push this event onto the event+grouping_pkey_value stack
                $groups{$e->event->event_def->id}{$ident_value} ||= [];
                push @{ $groups{$e->event->event_def->id}{$ident_value} }, $e_id;
            } else {
                # it's a non-grouped event
                push @{ $groups{'*'} }, $e_id;
            }
        }
    }

    return \%groups;
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.event.found_by_group',
    method   => 'grouped_events',
    api_level=> 1
);


1;
