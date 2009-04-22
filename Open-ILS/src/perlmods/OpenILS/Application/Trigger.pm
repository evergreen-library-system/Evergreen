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

sub create_active_events_for_object {
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
    my $defs = $editor->search_action_trigger_event_definition(
        { hook   => [ keys %hook_hash ],
          owner  => [ map { $_->{id} } @$orgs  ],
          active => 't'
        }
    );

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
    method   => 'create_active_events_for_object',
    api_level=> 1,
    stream   => 1,
    argc     => 3
);

sub create_event_for_object_and_def {
    my $self = shift;
    my $client = shift;
    my $definitions = shift;
    my $target = shift;
    my $location = shift;

    my $ident = $target->Identity;
    my $ident_value = $target->$ident();

    my @active = ($self->api_name =~ /inactive/o) ? () : ( active => 't' );

    my $editor = new_editor(xact=>1);

    my $orgs = $editor->json_query({ from => [ 'actor.org_unit_ancestors' => $location ] });
    my $defs = $editor->search_action_trigger_event_definition(
        { id => $definitions,
          owner  => [ map { $_->{id} } @$orgs  ],
          @active
        }
    );

    my $hooks = $editor->search_action_trigger_hook(
        { key       => [ map { $_->hook } @$defs ],
          core_type => $target->json_hint
        }
    );

    my %hook_hash = map { ($_->key, $_) } @$hooks;

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
    api_name => 'open-ils.trigger.event.autocreate.by_definition',
    method   => 'create_event_for_object_and_def',
    api_level=> 1,
    stream   => 1,
    argc     => 3
);
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.event.autocreate.by_definition.include_inactive',
    method   => 'create_event_for_object_and_def',
    api_level=> 1,
    stream   => 1,
    argc     => 3
);


# Retrieves events by object, or object type + filter
#  $object : a target object or object type (class hint)
#
#  $filter : an optional hash of filters ... top level keys:
#     event
#        filters on the atev objects, such as states or null-ness of timing
#        fields. contains the effective default of:
#          { state => 'pending' }
#        an example, which overrides the default, and will find
#        stale 'found' events:
#          { state => 'found', update_time => { '<' => 'yesterday' } }
#
#      event_def
#        filters on the atevdef object. contains the effective default of:
#          { active => 't' }
#
#      hook
#        filters on the hook object. no defaults, but there is a pinned,
#        unchangeable filter based on the passed hint or object type (see
#        $object above). an example for finding passive events:
#          { passive => 't' }
#
#     target
#        filters against the target field on the event. this can contain
#        either an array of target ids (if you passed an object type, and
#        not an object) or can contain a json_query that will return exactly
#        a list of target-type ids.  If you pass an object, the pkey value of
#        that object will be used as a filter in addition to the filter passed
#        in here.  example filter for circs of user 1234 that are open:
#          { select => { circ => ['id'] },
#            from => 'circ',
#            where => {
#              usr => 1234,
#              checkin_time => undef, 
#              '-or' => [
#                { stop_fines => undef },
#                { stop_fines => { 'not in' => ['LOST','LONGOVERDUE','CLAIMSRETURNED'] } }
#              ]
#            }

sub events_by_target {
    my $self = shift;
    my $client = shift;
    my $object = shift;
    my $filter = shift || {};
    my $flesh_fields = shift || {};
    my $flesh_depth = shift || 1;

    my $obj_class = ref($object) || _fm_class_by_hint($object);
    my $obj_hint = ref($object) ? _fm_hint_by_class(ref($object)) : $object;

    my $object_ident_field = $obj_class->Identity;

    my $query = {
        select => { atev => ["id"] },
        from   => {
            atev => {
                atevdef => {
                    field => "id",
                    fkey => "event_def",
                    join => {
                        ath => { field => "key", fkey => "hook" }
                    }
                }
            }
        },
        where  => {
            "+ath"  => { core_type => $obj_hint },
            "+atevdef" => { active => 't' },
            "+atev" => { state => 'pending' }
        },
        order_by => { "+atev" => [ 'run_time', 'add_time' ] },
        distinct => 1
    };


    # allow multiple 'target' filters
    $query->{where}->{'+atev'}->{'-and'} = [];

    # if we got a real object, filter on its pkey value
    if (ref($object)) { # pass an object, require that target
        push @{ $query->{where}->{'+atev'}->{'-and'} },
            { target => $object->$object_ident_field }
    }

    # we have a fancy complex target filter or a list of target ids
    if ($$filter{target}) {
        push @{ $query->{where}->{'+atev'}->{'-and'} },
            { target => {in => $$filter{target} } };
    }

    # pass no target filter or object, you get no events
    if (!@{ $query->{where}->{'+atev'}->{'-and'} }) {
        return undef; 
    }

    # any hook filters, other than the required core_type filter
    if ($$filter{hook}) {
        $query->{where}->{'+ath'}->{$_} = $$filter{hook}{$_}
            for (grep { $_ ne 'core_type' } keys %{$$filter{hook}});
    }

    # any event_def filters.  defaults to { active => 't' }
    if ($$filter{event_def}) {
        $query->{where}->{'+atevdef'}->{$_} = $$filter{event_def}{$_}
            for (keys %{$$filter{event_def}});
    }

    # any event filters.  defaults to { state => 'pending' }.
    # don't overwrite '-and' used for multiple target filters above
    if ($$filter{event}) {
        $query->{where}->{'+atev'}->{$_} = $$filter{event}{$_}
            for (grep { $_ ne '-and' } keys %{$$filter{event}});
    }

    my $e = new_editor();

    my $events = $e->json_query($query);

    $flesh_fields->{atev} = ['event_def'] unless $flesh_fields->{atev};

    for my $id (@$events) {
        my $event = $e->retrieve_action_trigger_event([
            $id->{id},
            {flesh => $flesh_depth, flesh_fields => $flesh_fields}
        ]);

        (my $meth = $obj_class) =~ s/^Fieldmapper:://o;
        $meth =~ s/::/_/go;
        $meth = 'retrieve_'.$meth;

        $event->target($e->$meth($event->target));
        $client->respond($event);
    }

    return undef;
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.events_by_target',
    method   => 'events_by_target',
    api_level=> 1,
    stream   => 1,
    argc     => 2
);
 
sub _fm_hint_by_class {
    my $class = shift;
    return Fieldmapper->publish_fieldmapper->{$class}->{hint};
}

sub _fm_class_by_hint {
    my $hint = shift;

    my ($class) = grep {
        Fieldmapper->publish_fieldmapper->{$_}->{hint} eq $hint
    } keys %{ Fieldmapper->publish_fieldmapper };

    return $class;
}

sub create_batch_events {
    my $self = shift;
    my $client = shift;
    my $key = shift;
    my $location_field = shift; # where to look for event_def.owner filtering ... circ_lib, for instance, where hook.core_type = circ
    my $filter = shift || {};

    my $active = ($self->api_name =~ /active/o) ? 1 : 0;
    if ($active && !keys(%$filter)) {
        $log->info("Active batch event creation requires a target filter but none was supplied to create_batch_events");
        return undef;
    }

    return undef unless ($key && $location_field);

    my $editor = new_editor(xact=>1);
    my $hooks = $editor->search_action_trigger_hook(
        { passive => $active ? 'f' : 't', key => $key }
    );

    my %hook_hash = map { ($_->key, $_) } @$hooks;

    my $defs = $editor->search_action_trigger_event_definition(
        { hook   => [ keys %hook_hash ], active => 't' },
    );

    for my $def ( @$defs ) {

        my $date = DateTime->now->subtract( seconds => interval_to_seconds($def->delay) );

        # we may need to do some work to backport this to 1.2
        $filter->{ $location_field } = { 'in' =>
            {
                select  => { aou => [{ column => 'id', transform => 'actor.org_unit_descendants', result_field => 'id' }] },
                from    => 'aou',
                where   => { id => $def->owner }
            }
        };

        my $run_time = 'now';
        if ($active) {
            $run_time = 
                DateTime
                    ->now
                    ->add( seconds => interval_to_seconds($def->delay) )
                    ->strftime( '%F %T%z' );
        } else {
            $filter->{ $def->delay_field } = {
                '<=' => DateTime
                    ->now
                    ->subtract( seconds => interval_to_seconds($def->delay) )
                    ->strftime( '%F %T%z' )
            };
        }

        my $class = _fm_class_by_hint($hook_hash{$def->hook}->core_type);

	# filter where this target has an event (and it's pending, for active hooks)
	$$filter{'-and'} = [] if (!exists($$filter{'-and'}));
	push @{ $filter->{'-and'} }, {
		'-not-exists' => {
			from  => 'atev',
			where => {
				event_def => $def->id,
				target    => { '=' => { '+' . $hook_hash{$def->hook}->core_type => $class->Identity } },
				($active ? (state  => 'pending') : ())
			}
		}
	};

        $class =~ s/^Fieldmapper:://o;
        $class =~ s/::/_/go;

        my $method = 'search_'. $class;
        my $objects = $editor->$method( $filter );

        for my $o (@$objects) {

            my $ident = $o->Identity;

            my $event = Fieldmapper::action_trigger::event->new();
            $event->target( $o->$ident() );
            $event->event_def( $def->id );
            $event->run_time( $run_time );

            $editor->create_action_trigger_event( $event );

            $client->respond( $event->id );
        }
    }

    $editor->commit;

    return undef;
}
__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.passive.event.autocreate.batch',
    method   => 'create_batch_events',
    api_level=> 1,
    stream   => 1,
    argc     => 2
);

__PACKAGE__->register_method(
    api_name => 'open-ils.trigger.active.event.autocreate.batch',
    method   => 'create_batch_events',
    api_level=> 1,
    stream   => 1,
    argc     => 2
);


sub fire_single_event {
    my $self = shift;
    my $client = shift;
    my $event_id = shift;

    my $e = OpenILS::Application::Trigger::Event->new($event_id);

    if ($e->validate->valid) {
        $e->react->cleanup;
    }

    $e->editor->disconnect;

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

    $e->editor->disconnect;

    return {
        valid     => $e->valid,
        reacted   => $e->reacted,
        cleanedup => $e->cleanedup,
        events    => [map { $_->event } @{$e->events}]
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

    return $editor->search_action_trigger_event(
        [{ state => 'pending', run_time => {'<' => 'now'} }, { order_by => { atev => [ qw/run_time add_time/] } }]
        { idlist=> 1 }
    );
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
                my @steps = split /\./, $group;

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
        $e->editor->disconnect;
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
