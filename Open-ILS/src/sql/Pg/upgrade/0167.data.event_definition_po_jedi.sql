BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0167');

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, cleanup_success, cleanup_failure, delay, delay_field, group_field, template) VALUES (23, true, 1, 'PO JEDI', 'format.po.jedi', 'NOOP_True', 'ProcessTemplate', NULL, NULL, '00:05:00', NULL, NULL,
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
            "price":[% helpers.get_li_attr('estimated_price', '', li.attributes) %],
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
);

/*
// API : additional party identification -- supplier’s code for library acct or dept (EAN code) 
// IA  : internal vendor number (vendor profile number)
// VA  : VAT registered number.... TODO

BUYER id-qualifier:
 9  = EAN - location number -- not the same as EAN-13 barcode
31B = US book trade SANs (Standard Address Numbers aka EDItEUR code) - TRANSLATOR DEFAULT!
91  = Assigned by supplier or supplier’s agent
92  = Assigned by buyer

ITEM id-qualifier (Item number type, coded):
EN = EAN-13 article number - 13 digit barcode
IB = ISBN (International Standard Book   Number)
IM = ISMN (International Standard Music  Number)
IS = ISSN (International Standard Serial Number): use only in a continuation order message coded 22C in BGM DE 1001, to identify the series to which the order applies
MF = manufacturer’s article number
SA = supplier’s article number
*/


INSERT INTO action_trigger.environment (event_def, path) VALUES 
  (23, 'lineitems.attributes'), 
  (23, 'lineitems.lineitem_details'), 
  (23, 'lineitems.lineitem_notes'), 
  (23, 'ordering_agency.mailing_address'), 
  (23, 'provider');

-- The environment insert has to happen here because it relies on subquerying the user-editable field "name" to
-- provide the FK.  Outside of this transaction, we cannot be sure the user hasn't changed the name to something else.

COMMIT;

