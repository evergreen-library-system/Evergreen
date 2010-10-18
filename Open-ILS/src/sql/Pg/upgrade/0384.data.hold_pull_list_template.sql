BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0384');

INSERT INTO action_trigger.hook (key,core_type,description,passive) 
    VALUES (   
        'ahr.format.pull_list',
        'ahr', 
        oils_i18n_gettext(
            'ahr.format.pull_list',
            'Format holds pull list for printing',
            'ath',
            'description'
        ), 
        FALSE
    );

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        35,
        TRUE,
        1,
        'Holds Pull List',
        'ahr.format.pull_list',
        'NOOP_True',
        'ProcessTemplate',
        'pickup_lib',
        'print-on-demand',
$$
[%- USE date -%]
<style>
    table { border-collapse: collapse; } 
    td { padding: 5px; border-bottom: 1px solid #888; } 
    th { font-weight: bold; }
</style>
[% 
    # Sort the holds into copy-location buckets
    # In the main print loop, sort each bucket by callnumber before printing
    SET holds_list = [];
    SET loc_data = [];
    SET current_location = target.0.current_copy.location.id;
    FOR hold IN target;
        IF current_location != hold.current_copy.location.id;
            SET current_location = hold.current_copy.location.id;
            holds_list.push(loc_data);
            SET loc_data = [];
        END;
        SET hold_data = {
            'hold' => hold,
            'callnumber' => hold.current_copy.call_number.label
        };
        loc_data.push(hold_data);
    END;
    holds_list.push(loc_data)
%]
<table>
    <thead>
        <tr>
            <th>Title</th>
            <th>Author</th>
            <th>Shelving Location</th>
            <th>Call Number</th>
            <th>Barcode</th>
            <th>Patron</th>
        </tr>
    </thead>
    <tbody>
    [% FOR loc_data IN holds_list  %]
        [% FOR hold_data IN loc_data.sort('callnumber') %]
            [% 
                SET hold = hold_data.hold;
                SET copy_data = helpers.get_copy_bib_basics(hold.current_copy.id);
            %]
            <tr>
                <td>[% copy_data.title | truncate %]</td>
                <td>[% copy_data.author | truncate %]</td>
                <td>[% hold.current_copy.location.name %]</td>
                <td>[% hold.current_copy.call_number.label %]</td>
                <td>[% hold.current_copy.barcode %]</td>
                <td>[% hold.usr.card.barcode %]</td>
            </tr>
        [% END %]
    [% END %]
    <tbody>
</table>
$$
);

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES
        (35, 'current_copy.location'),
        (35, 'current_copy.call_number'),
        (35, 'usr.card'),
        (35, 'pickup_lib')
;

-- DELETE FROM config.upgrade_log WHERE version = 'tmp'; DELETE FROM action_trigger.event WHERE event_def IN (35); DELETE FROM action_trigger.environment WHERE event_def IN (35); DELETE FROM action_trigger.event_definition WHERE id IN (35); DELETE FROM action_trigger.hook WHERE key IN ( 'ahr.format.pull_list' );

COMMIT;

