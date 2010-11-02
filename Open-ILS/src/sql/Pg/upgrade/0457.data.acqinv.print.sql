BEGIN;

INSERT INTO config.upgrade_log VALUES ('0457');

UPDATE action_trigger.event_definition SET template = $$[% FILTER collapse %]
[%- SET invoice = target -%]
<!-- This lacks general refinement -->
<div class="acq-invoice-voucher">
    <h1>Invoice</h1>
    <div>
        <strong>No.</strong> [% invoice.inv_ident %]
        [% IF invoice.inv_type %]
            / <strong>Type:</strong>[% invoice.inv_type %]
        [% END %]
    </div>
    <div>
        <dl>
            [% BLOCK ent_with_address %]
            <dt>[% ent_label %]: [% ent.name %] ([% ent.code %])</dt>
            <dd>
                [% IF ent.addresses.0 %]
                    [% SET addr = ent.addresses.0 %]
                    [% addr.street1 %]<br />
                    [% IF addr.street2 %][% addr.street2 %]<br />[% END %]
                    [% addr.city %],
                    [% IF addr.county %] [% addr.county %], [% END %]
                    [% IF addr.state %] [% addr.state %] [% END %]
                    [% IF addr.post_code %][% addr.post_code %][% END %]<br />
                    [% IF addr.country %] [% addr.country %] [% END %]
                [% END %]
                <p>
                    [% IF ent.phone %] Phone: [% ent.phone %]<br />[% END %]
                    [% IF ent.fax_phone %] Fax: [% ent.fax_phone %]<br />[% END %]
                    [% IF ent.url %] URL: [% ent.url %]<br />[% END %]
                    [% IF ent.email %] E-mail: [% ent.email %] [% END %]
                </p>
            </dd>
            [% END %]
            [% INCLUDE ent_with_address
                ent = invoice.provider
                ent_label = "Provider" %]
            [% INCLUDE ent_with_address
                ent = invoice.shipper
                ent_label = "Shipper" %]
            <dt>Receiver</dt>
            <dd>
                [% invoice.receiver.name %] ([% invoice.receiver.shortname %])
            </dd>
            <dt>Received</dt>
            <dd>
                [% helpers.format_date(invoice.recv_date) %] by
                [% invoice.recv_method %]
            </dd>
            [% IF invoice.note %]
                <dt>Note</dt>
                <dd>
                    [% invoice.note %]
                </dd>
            [% END %]
        </dl>
    </div>
    <ul>
        [% FOR entry IN invoice.entries %]
            <li>
                [% IF entry.lineitem %]
                    Title: [% helpers.get_li_attr(
                        "title", "", entry.lineitem.attributes
                    ) %]<br />
                    Author: [% helpers.get_li_attr(
                        "author", "", entry.lineitem.attributes
                    ) %]
                [% END %]
                [% IF entry.purchase_order %]
                    (PO: [% entry.purchase_order.name %])
                [% END %]<br />
                Invoice item count: [% entry.inv_item_count %]
                [% IF entry.phys_item_count %]
                    / Physical item count: [% entry.phys_item_count %]
                [% END %]
                <br />
                [% IF entry.cost_billed %]
                    Cost billed: [% entry.cost_billed %]
                    [% IF entry.billed_per_item %](per item)[% END %]
                    <br />
                [% END %]
                [% IF entry.actual_cost %]
                    Actual cost: [% entry.actual_cost %]<br />
                [% END %]
                [% IF entry.amount_paid %]
                    Amount paid: [% entry.amount_paid %]<br />
                [% END %]
                [% IF entry.note %]Note: [% entry.note %][% END %]
            </li>
        [% END %]
        [% FOR item IN invoice.items %]
            <li>
                [% IF item.inv_item_type %]
                    Item Type: [% item.inv_item_type %]<br />
                [% END %]
                [% IF item.title %]Title/Description:
                    [% item.title %]<br />
                [% END %]
                [% IF item.author %]Author: [% item.author %]<br />[% END %]
                [% IF item.purchase_order %]PO: [% item.purchase_order %]<br />[% END %]
                [% IF item.note %]Note: [% item.note %]<br />[% END %]
                [% IF item.cost_billed %]
                    Cost billed: [% item.cost_billed %]<br />
                [% END %]
                [% IF item.actual_cost %]
                    Actual cost: [% item.actual_cost %]<br />
                [% END %]
                [% IF item.amount_paid %]
                    Amount paid: [% item.amount_paid %]<br />
                [% END %]
            </li>
        [% END %]
    </ul>
    <div>
        Amounts spent per fund:
        <table>
        [% FOR blob IN user_data %]
            <tr>
                <th style="text-align: left;">[% blob.fund.code %] ([% blob.fund.year %]):</th>
                <td>$[% blob.total %]</td>
            </tr>
        [% END %]
        </table>
    </div>
</div>
[% END %]$$ WHERE id = 22;

COMMIT;
