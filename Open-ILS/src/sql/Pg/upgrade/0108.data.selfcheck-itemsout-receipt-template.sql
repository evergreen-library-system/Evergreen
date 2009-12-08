BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0108');

INSERT INTO action_trigger.hook (key, core_type, description, passive) 
    VALUES (
        'format.selfcheck.items_out',
        'circ',
        'Formats items out for self-checkout receipt',
        TRUE
    );

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, group_field, granularity, template )
    VALUES (
        11,
        TRUE,
        1,
        'Self-Checkout Items Out Receipt',
        'format.selfcheck.items_out',
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
    [% FOR circ IN target %]
        <li>
            <div>[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]</div>
            <div>Barcode: [% circ.target_copy.barcode %]</div>
            <div>Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]</div>
        </li>
    [% END %]
    </ol>
</div>
$$
);


INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 11, 'target_copy'),
    ( 11, 'circ_lib.billing_address'),
    ( 11, 'circ_lib.hours_of_operation'),
    ( 11, 'usr');

COMMIT;
