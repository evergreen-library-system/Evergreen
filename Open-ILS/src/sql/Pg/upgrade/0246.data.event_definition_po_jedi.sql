BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0246');

UPDATE action_trigger.event_definition SET id=23, template = 
$$[%- USE date -%]
[%# start JEDI document -%]
[%- BLOCK big_block -%]
{
   "recipient":"[% target.provider.san %]",
   "sender":"[% target.ordering_agency.mailing_address.san %]",
   "body": [{
     "ORDERS":[ "order", {
        "po_number":[% target.id %],
        "date":"[% date.format(date.now, '%Y%m%d') %]",
        "buyer":[{
            [%- IF target.provider.edi_default.vendcode -%]
            "id":"[% target.ordering_agency.mailing_address.san _ ' ' _ target.provider.edi_default.vendcode %]", 
            "id-qualifier": 91
            [%- ELSE -%]
            "id":"[% target.ordering_agency.mailing_address.san %]"
            [%- END  -%]
        }],
        "vendor":[ 
            [%- # target.provider.name (target.provider.id) -%]
            "[% target.provider.san %]",
            {"id-qualifier": 92, "id":"[% target.provider.id %]"}
        ],
        "currency":"[% target.provider.currency_type %]",
        "items":[
        [% FOR li IN target.lineitems %]
        {
            "identifiers":[
                {"id-qualifier":"SA","id":"[% li.id %]"},
                {"id-qualifier":"IB","id":"[% helpers.get_li_attr('isbn', li.attributes) %]"}
            ],
            "price":[% helpers.get_li_attr('estimated_price', '', li.attributes) %],
            "desc":[
                {"BTI":"[% helpers.get_li_attr('title',     '', li.attributes) %]"}, 
                {"BPU":"[% helpers.get_li_attr('publisher', '', li.attributes) %]"},
                {"BPD":"[% helpers.get_li_attr('pubdate',   '', li.attributes) %]"},
                {"BPH":"[% helpers.get_li_attr('pagination','', li.attributes) %]"}
            ],
            "quantity":[% li.lineitem_details.size %]
        [%-# TODO: lineitem details (later) -%]
        }[% UNLESS loop.last %],[% END %]
        [% END %]
        ],
        "line_items":[% target.lineitems.size %]
     }]  [% # close ORDERS array %]
   }]    [% # close  body  array %]
}
[% END %]
[% tempo = PROCESS big_block; helpers.escape_json(tempo) %]
$$
WHERE name='PO JEDI' or id=23;  -- bring updated DB in line w/ baseline DB
                                -- nobody but devs will have the old 100+ id, and only atz put it in use
INSERT INTO action_trigger.environment (event_def, path) VALUES 
  (23, 'provider.edi_default');

-- Hope they haven't changed the name...

COMMIT;

