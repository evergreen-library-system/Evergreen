BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0262');

UPDATE action_trigger.event_definition SET template =
$$[%- USE date -%]
[%# start JEDI document -%]
[%- BLOCK big_block -%]
["order", {
    "po_number":[% target.id %],
    "date":"[% date.format(date.now, '%Y%m%d') %]",
    "buyer":[
        {"id":"[% target.ordering_agency.mailing_address.san %]",
         "reference":{"API":"[% target.ordering_agency.mailing_address.san %]"}}
    ],
    "vendor":[ 
        "[% target.provider.san %]", // [% target.provider.name %] ([% target.provider.id %])
        {"id-qualifier":"91", "reference":{"IA":"[% target.provider.id %]"}, "id":"[% target.provider.san %]"}
    ],
    "currency":"[% target.provider.currency_type %]",
    "items":[
        [% FOR li IN target.lineitems %]
        {
            "identifiers":[
                {"id-qualifier":"SA","id":"[% li.id %]"},
                {"id-qualifier":"IB","id":"[% helpers.get_li_attr('isbn', li.attributes) %]"}
            ],
            "price":[% li.estimated_unit_price || '0.00' %],
            "desc":[
                {"BTI":"[% helpers.get_li_attr('title',     '', li.attributes) %]"}, 
                {"BPU":"[% helpers.get_li_attr('publisher', '', li.attributes) %]"},
                {"BPD":"[% helpers.get_li_attr('pubdate',   '', li.attributes) %]"},
                {"BPH":"[% helpers.get_li_attr('pagination','', li.attributes) %]"}
            ],
            "quantity":[% li.lineitem_details.size %]
            [%-# TODO: lineitem details (later) -%]
        }[% UNLESS loop.last %],[% END -%]
        [%- END %]
    ],
    "line_items":[% target.lineitems.size %]
}]
[% END %]
[% tempo = PROCESS big_block; helpers.escape_json(tempo) %]
$$
WHERE id = 23;

COMMIT;

