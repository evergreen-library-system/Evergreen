BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0238');  -- senator

INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES (
        'format.acqcle.html',
        'acqcle',
        'Formats claim events into a voucher',
        TRUE
    );

INSERT INTO action_trigger.event_definition (
        id, active, owner, name, hook, group_field,
        validator, reactor, granularity, template
    ) VALUES (
        21,
        TRUE,
        1,
        'Claim Voucher',
        'format.acqcle.html',
        'claim',
        'NOOP_True',
        'ProcessTemplate',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET claim = target.0.claim -%]
<!-- This will need refined/prettified. -->
<div class="acq-claim-voucher">
    <h2>Claim: [% claim.id %] ([% claim.type.code %])</h2>
    <h3>Against: [%- helpers.get_li_attr("title", "", claim.lineitem_detail.lineitem.attributes) -%]</h3>
    <ul>
        [% FOR event IN target %]
        <li>
            Event type: [% event.type.code %]
            [% IF event.type.library_initiated %](Library initiated)[% END %]
            <br />
            Event date: [% event.event_date %]<br />
            Order date: [% event.claim.lineitem_detail.lineitem.purchase_order.order_date %]<br />
            Expected receive date: [% event.claim.lineitem_detail.lineitem.expected_recv_time %]<br />
            Initiated by: [% event.creator.family_name %], [% event.creator.first_given_name %] [% event.creator.second_given_name %]<br />
            Barcode: [% event.claim.lineitem_detail.barcode %]; Fund:
            [% event.claim.lineitem_detail.fund.code %]
            ([% event.claim.lineitem_detail.fund.year %])
        </li>
        [% END %]
    </ul>
</div>
$$
);


INSERT INTO action_trigger.environment (event_def, path) VALUES
    (21, 'claim'),
    (21, 'claim.type'),
    (21, 'claim.lineitem_detail'),
    (21, 'claim.lineitem_detail.fund'),
    (21, 'claim.lineitem_detail.lineitem.attributes'),
    (21, 'claim.lineitem_detail.lineitem.purchase_order'),
    (21, 'creator'),
    (21, 'type')
;

COMMIT;

