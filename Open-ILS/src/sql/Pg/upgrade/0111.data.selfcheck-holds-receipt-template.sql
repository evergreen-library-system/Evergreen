BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0111');

INSERT INTO action_trigger.hook (key, core_type, description, passive) 
    VALUES (
        'format.selfcheck.holds',
        'ahr',
        'Formats holds for self-checkout receipt',
        TRUE
    );

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, group_field, granularity, template )
    VALUES (
        12,
        TRUE,
        1,
        'Self-Checkout Holds Receipt',
        'format.selfcheck.holds',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR hold IN target %]
        [%-
            SET idx = loop.count - 1;
            SET udata =  user_data.$idx
        -%]
        <li>
            <div>Title: [% hold.bib_rec.bib_record.simple_record.title %]</div>
            <div>Author: [% hold.bib_rec.bib_record.simple_record.author %]</div>
            <div>Pickup Location: [% hold.pickup_lib.name %]</div>
            <div>Status: 
                [%- IF udata.ready -%]
                    Ready for pickup
                [% ELSE %]
                    #[% udata.queue_position %] of [% udata.potential_copies %] copies.
                [% END %]
            </div>
        </li>
    [% END %]
    </ol>
</div>
$$
);


INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 12, 'bib_rec.bib_record.simple_record'),
    ( 12, 'pickup_lib'),
    ( 12, 'usr');

COMMIT;
