BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0094');

INSERT INTO action_trigger.hook (key, core_type, description, passive) 
    VALUES (
        'format.selfcheck.checkout',
        'circ',
        'Formats circ objects for self-checkout receipt',
        TRUE
    );

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, group_field, granularity, template )
    VALUES (
        10,
        TRUE,
        1,
        'Self-Checkout Receipt',
        'format.selfcheck.checkout',
        'NOOP_True',
        'ProcessTemplate',
        'usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.usr -%]
[%- SET lib = target.0.circ_lib -%]
[%- SET lib_addr = target.0.circ_lib.billing_address -%]
[%- SET hours = lib.hours_of_operation -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <div>[% lib.name %]</div>
    <div>[% lib_addr.street1 %] [% lib_addr.street2 %]</div>
    <div>[% lib_addr.city %], [% lib_addr.state %] [% lb_addr.post_code %]</div>
    <div>[% lib.phone %]</div>
    <br/>

    [% user.family_name %], [% user.first_given_name %]
    <ol>
    [% FOR circ IN target %]
        [%-
            SET idx = loop.count - 1;
            SET user_data =  EventProcessor.findEvent( event.$idx ).environment.user_data 
        -%]
        <li>
            <div>[% helpers.get_copy_bib_basics(circ.target_copy.id).title %]</div>
            <div>Barcode: [% circ.target_copy.barcode %]</div>
            [% IF user_data.renewal_failure %]
                <div style='color:red;'>Renewal Failed</div>
            [% ELSE %]
                <div>Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]</div>
            [% END %]
        </li>
    [% END %]
    </ol>
    
    <div>
        Library Hours
        [%- BLOCK format_time; date.format(time _ ' 1/1/1000', format='%I:%M %p'); END -%]
        <div>
            Monday 
            [% PROCESS format_time time = hours.dow_0_open %] 
            [% PROCESS format_time time = hours.dow_0_close %] 
        </div>
        <div>
            Tuesday 
            [% PROCESS format_time time = hours.dow_1_open %] 
            [% PROCESS format_time time = hours.dow_1_close %] 
        </div>
        <div>
            Wednesday 
            [% PROCESS format_time time = hours.dow_2_open %] 
            [% PROCESS format_time time = hours.dow_2_close %] 
        </div>
        <div>
            Thursday
            [% PROCESS format_time time = hours.dow_3_open %] 
            [% PROCESS format_time time = hours.dow_3_close %] 
        </div>
        <div>
            Friday
            [% PROCESS format_time time = hours.dow_4_open %] 
            [% PROCESS format_time time = hours.dow_4_close %] 
        </div>
        <div>
            Saturday
            [% PROCESS format_time time = hours.dow_5_open %] 
            [% PROCESS format_time time = hours.dow_5_close %] 
        </div>
        <div>
            Sunday 
            [% PROCESS format_time time = hours.dow_6_open %] 
            [% PROCESS format_time time = hours.dow_6_close %] 
        </div>
    </div>
</div>
$$
);


INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( 10, 'target_copy'),
    ( 10, 'circ_lib.billing_address'),
    ( 10, 'circ_lib.hours_of_operation'),
    ( 10, 'usr');

COMMIT;
