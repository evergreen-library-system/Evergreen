BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0312'); --atz

UPDATE action_trigger.event_definition SET template =
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
            "identifiers":[   [%-# li.isbns = helpers.get_li_isbns(li.attributes) %]
            [% FOR isbn IN helpers.get_li_isbns(li.attributes) -%]
                [% IF isbn.length == 13 -%]
                {"id-qualifier":"EN","id":"[% isbn %]"},
                [% ELSE -%]
                {"id-qualifier":"IB","id":"[% isbn %]"},
                [%- END %]
            [% END %]
                {"id-qualifier":"SA","id":"[% li.id %]"}
            ],
            "price":[% li.estimated_unit_price || '0.00' %],
            "desc":[
                {"BTI":"[% helpers.get_li_attr('title',     '', li.attributes) %]"}, 
                {"BPU":"[% helpers.get_li_attr('publisher', '', li.attributes) %]"},
                {"BPD":"[% helpers.get_li_attr('pubdate',   '', li.attributes) %]"},
                {"BPH":"[% helpers.get_li_attr('pagination','', li.attributes) %]"}
            ],
            "quantity":[% li.lineitem_details.size %]
        }[% UNLESS loop.last %],[% END %]
        [%-# TODO: lineitem details (later) -%]
        [% END %]
        ],
        "line_items":[% target.lineitems.size %]
     }]  [% # close ORDERS array %]
   }]    [% # close  body  array %]
}
[% END %]
[% tempo = PROCESS big_block; helpers.escape_json(tempo) %]
$$
WHERE id = 23;

COMMIT;
