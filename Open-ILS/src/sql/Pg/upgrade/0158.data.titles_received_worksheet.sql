BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0158');  -- atz

INSERT INTO action_trigger.hook (key, core_type, description, passive) 
    VALUES (
        'format.acqli.html',
        'jub',
        'Formats lineitem worksheet for titles received',
        TRUE
    );

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, granularity, template)
    VALUES (
        14,
        TRUE,
        1,
        'Titles Received Lineitem Worksheet',
        'format.acqli.html',
        'NOOP_True',
        'ProcessTemplate',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET li = target; -%]
<div class="wrapper">
    <div class="summary">
        <div class="lineid">Lineitem ID: [% li.id %]</div>
        <div class="count"><span id="countno">[% li.lineitem_details.size %]</span> items</div>
        [% IF detail.recv_time %]<div class="dateformat">Expected: [% li.expected_recv_time %]</div>[% END %]
    </div>
    <table>
        <thead>
            <tr>
                <th>Title</th>
                <th>Recd.</th>
                <th>Barcode</th>
                <th>Call Number</th>
                <th>Distribution</th>
                <th>Notes</th>
            </tr>
        </thead>
        <tbody>
    [% FOREACH detail IN li.lineitem_details %]
            <tr>
                [% IF loop.first %]
                <td rowspan='[% li.lineitem_details.size %]'>
                 [%- helpers.get_li_attr("title", "", li.attributes) -%]
                </td>
                [% END %]
                <!-- acq.lineitem_detail.id = [%- detail.id -%] -->
                <td>[% IF detail.recv_time %]<span class="recv_time">[% detail.recv_time %]</span>[% END %]</td>
                <td>[% IF detail.barcode   %]<span class="barcode"  >[% detail.barcode   %]</span>[% END %]</td>
                <td>[% IF detail.cn_label  %]<span class="cn_label" >[% detail.cn_label  %]</span>[% END %]</td>
                <td>
                    ==&gt; [% detail.owning_lib.shortname %] ([% detail.owning_lib.name %])
                    [% IF detail.note %]( [% detail.note %] )[% END %]
                </td>
                <td>
                    [%- SET notelist = []             -%]
                    [%- FOR note IN li.lineitem_notes -%]
                    [%-     notelist.push(note.value) -%]
                    [%- END                           -%]
                    [%- notelist.join('<br/>')        -%]
                </td>
            </tr>
    [% END %]
        </tbody>
    </table>
</div>
$$
);


INSERT INTO action_trigger.environment (event_def, path) VALUES
    ( 14, 'attributes' ),
    ( 14, 'lineitem_details' ),
    ( 14, 'lineitem_details.owning_lib' ),
    ( 14, 'lineitem_notes' )
;

COMMIT;

