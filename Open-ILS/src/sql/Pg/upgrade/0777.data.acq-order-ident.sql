BEGIN;

SELECT evergreen.upgrade_deps_block_check('0777', :eg_version);

-- Listed here for reference / ease of access.  The update
-- is not applied here (see the WHERE clause).
UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
[%
    # extract some commonly used variables

    VENDOR_SAN = target.provider.san;
    VENDCODE = target.provider.edi_default.vendcode;
    VENDACCT = target.provider.edi_default.vendacct;
    ORG_UNIT_SAN = target.ordering_agency.mailing_address.san;

    # set the vendor / provider

    VENDOR_BT      = 0; # Baker & Taylor
    VENDOR_INGRAM  = 0;
    VENDOR_BRODART = 0;
    VENDOR_MW_TAPE = 0; # Midwest Tape
    VENDOR_RB      = 0; # Recorded Books
    VENDOR_ULS     = 0; # ULS

    IF    VENDOR_SAN == '1556150'; VENDOR_BT = 1;
    ELSIF VENDOR_SAN == '1697684'; VENDOR_BRODART = 1;
    ELSIF VENDOR_SAN == '1697978'; VENDOR_INGRAM = 1;
    ELSIF VENDOR_SAN == '2549913'; VENDOR_MW_TAPE = 1;
    ELSIF VENDOR_SAN == '1113984'; VENDOR_RB = 1;
    ELSIF VENDOR_SAN == '1699342'; VENDOR_ULS = 1;
    END;

    # if true, pass the PO name as a secondary identifier
    # RFF+LI:<name>/li_id
    INC_PO_NAME = 0;
    IF VENDOR_INGRAM;
        INC_PO_NAME = 1;
    END;

    # GIR configuration --------------------------------------

    INC_COPIES = 1; # copies on/off switch
    INC_FUND = 0;
    INC_CALLNUMBER = 0;
    INC_ITEM_TYPE = 1;
    INC_LOCATION = 0;
    INC_COLLECTION_CODE = 1;
    INC_OWNING_LIB = 1;
    INC_QUANTITY = 1;
    INC_COPY_ID = 0;

    IF VENDOR_BT;
        INC_CALLNUMBER = 1;
    END;

    IF VENDOR_BRODART;
        INC_FUND = 1;
    END;

    IF VENDOR_MW_TAPE;
        INC_FUND = 1;
        INC_COLLECTION_CODE = 0;
        INC_ITEM_TYPE = 0;
    END;

    # END GIR configuration ---------------------------------

-%]
[%- BLOCK big_block -%]
{
   "recipient":"[% VENDOR_SAN %]",
   "sender":"[% ORG_UNIT_SAN %]",
   "body": [{
     "ORDERS":[ "order", {

        "po_number":[% target.id %],

        [% IF INC_PO_NAME %]
        "po_name":"[% target.name | replace('\/', ' ') | replace('"', '\"') %]",
        [% END %]

        "date":"[% date.format(date.now, '%Y%m%d') %]",

        "buyer":[
            [% IF VENDOR_BT %]
                {"id-qualifier": 91, "id":"[% ORG_UNIT_SAN %] [% VENDCODE %]"}
            [% ELSE %]
                {"id":"[% ORG_UNIT_SAN %]"},
                {"id-qualifier": 91, "id":"[% VENDACCT %]"}
            [% END %]
        ],

        "vendor":[
            "[% VENDOR_SAN %]",
            {"id-qualifier": 92, "id":"[% target.provider.id %]"}
        ],

        "currency":"[% target.provider.currency_type %]",
                
        "items":[
        [%- FOR li IN target.lineitems %]
        {
            "line_index":"[% li.id %]",
            "identifiers":[   
            [%- 
                idval = '';
                idqual = 'EN'; # default ISBN/UPC/EAN-13
                ident_attr = helpers.get_li_order_ident(li.attributes);
                IF ident_attr;
                    idname = ident_attr.attr_name;
                    idval = ident_attr.attr_value;
                    IF idname == 'isbn' AND idval.length != 13;
                        idqual = 'IB';
                    ELSIF idname == 'issn';
                        idqual = 'IS';
                    END;
                ELSE;
                    idqual = 'IN';
                    idval = li.id;
                END -%]
                {"id-qualifier":"[% idqual %]","id":"[% idval %]"}
            ],
            "price":[% li.estimated_unit_price || '0.00' %],
            "desc":[
                {"BTI":"[% helpers.get_li_attr_jedi('title',     '', li.attributes) %]"},
                {"BPU":"[% helpers.get_li_attr_jedi('publisher', '', li.attributes) %]"},
                {"BPD":"[% helpers.get_li_attr_jedi('pubdate',   '', li.attributes) %]"},
                [% IF VENDOR_ULS -%]
                {"BEN":"[% helpers.get_li_attr_jedi('edition',   '', li.attributes) %]"},
                {"BAU":"[% helpers.get_li_attr_jedi('author',    '', li.attributes) %]"}
                [%- ELSE -%]
                {"BPH":"[% helpers.get_li_attr_jedi('pagination','', li.attributes) %]"}
                [%- END %]
            ],
            [%- ftx_vals = []; 
                FOR note IN li.lineitem_notes;
                    NEXT UNLESS note.vendor_public == 't'; 
                    ftx_vals.push(note.value); 
                END; 
                IF VENDOR_BRODART; # look for copy-level spec code
                    FOR lid IN li.lineitem_details;
                        IF lid.note;
                            spec_note = lid.note.match('spec code ([a-zA-Z0-9_])');
                            IF spec_note.0; ftx_vals.push(spec_note.0); END;
                        END;
                    END;
                END; 
                IF xtra_ftx;           ftx_vals.unshift(xtra_ftx); END; 

                # BT & ULS want FTX+LIN for every LI, even if empty
                IF ((VENDOR_BT OR VENDOR_ULS) AND ftx_vals.size == 0);
                    ftx_vals.unshift('');
                END;  
            -%]

            "free-text":[ 
                [% FOR note IN ftx_vals -%] "[% note %]"[% UNLESS loop.last %], [% END %][% END %] 
            ],            

            "quantity":[% li.lineitem_details.size %],

            [%- IF INC_COPIES -%]
            "copies" : [
                [%- compressed_copies = [];
                    FOR lid IN li.lineitem_details;
                        fund = lid.fund.code;
                        item_type = lid.circ_modifier;
                        callnumber = lid.cn_label;
                        owning_lib = lid.owning_lib.shortname;
                        location = lid.location;
                        collection_code = lid.collection_code;
    
                        # when we have real copy data, treat it as authoritative for some fields
                        acp = lid.eg_copy_id;
                        IF acp;
                            item_type = acp.circ_modifier;
                            callnumber = acp.call_number.label;
                            location = acp.location.name;
                        END ;


                        # collapse like copies into groups w/ quantity

                        found_match = 0;
                        IF !INC_COPY_ID; # INC_COPY_ID implies 1 copy per GIR
                            FOR copy IN compressed_copies;
                                IF  (fund == copy.fund OR (!fund AND !copy.fund)) AND
                                    (item_type == copy.item_type OR (!item_type AND !copy.item_type)) AND
                                    (callnumber == copy.callnumber OR (!callnumber AND !copy.callnumber)) AND
                                    (owning_lib == copy.owning_lib OR (!owning_lib AND !copy.owning_lib)) AND
                                    (location == copy.location OR (!location AND !copy.location)) AND
                                    (collection_code == copy.collection_code OR (!collection_code AND !copy.collection_code));

                                    copy.quantity = copy.quantity + 1;
                                    found_match = 1;
                                END;
                            END;
                        END;

                        IF !found_match;
                            compressed_copies.push({
                                fund => fund,
                                item_type => item_type,
                                callnumber => callnumber,
                                owning_lib => owning_lib,
                                location => location,
                                collection_code => collection_code,
                                copy_id => lid.id, # for INC_COPY_ID
                                quantity => 1
                            });
                        END;
                    END;
                    FOR copy IN compressed_copies;

                    # If we assume owning_lib is required and set, 
                    # it is safe to prepend each following copy field w/ a ","

                    # B&T EDI requires expected GIR fields to be 
                    # present regardless of whether a value exists.  
                    # some fields are required to have a value in ACQ, 
                    # though, so they are not forced into place below.

                 %]{[%- IF INC_OWNING_LIB AND copy.owning_lib %] "owning_lib":"[% copy.owning_lib %]"[% END -%]
                    [%- IF INC_FUND AND copy.fund %],"fund":"[% copy.fund %]"[% END -%]
                    [%- IF INC_CALLNUMBER AND (VENDOR_BT OR copy.callnumber) %],"call_number":"[% copy.callnumber %]"[% END -%]
                    [%- IF INC_ITEM_TYPE AND (VENDOR_BT OR copy.item_type) %],"item_type":"[% copy.item_type %]"[% END -%]
                    [%- IF INC_LOCATION AND copy.location %],"copy_location":"[% copy.location %]"[% END -%]
                    [%- IF INC_COLLECTION_CODE AND (VENDOR_BT OR copy.collection_code) %],"collection_code":"[% copy.collection_code %]"[% END -%]
                    [%- IF INC_QUANTITY %],"quantity":"[% copy.quantity %]"[% END -%]
                    [%- IF INC_COPY_ID %],"copy_id":"[% copy.copy_id %]" [% END %]}[% ',' UNLESS loop.last -%]
                [%- END -%] [%# FOR compressed_copies -%]
            ]
            [%- END -%] [%# IF INC_COPIES %]

        }[% UNLESS loop.last %],[% END -%]

        [% END %] [%# END lineitems %]
        ],
        "line_items":[% target.lineitems.size %]
     }]  [%# close ORDERS array %]
   }]    [%# close  body  array %]
}
[% END %]
[% tempo = PROCESS big_block; helpers.escape_json(tempo) %]
$$
WHERE ID = 23 AND FALSE; -- remove 'AND FALSE' to apply this update


-- lineitem worksheet
UPDATE action_trigger.event_definition SET template = 
$$
[%- USE date -%]
[%-
    # find a lineitem attribute by name and optional type
    BLOCK get_li_attr;
        FOR attr IN li.attributes;
            IF attr.attr_name == attr_name;
                IF !attr_type OR attr_type == attr.attr_type;
                    attr.attr_value;
                    LAST;
                END;
            END;
        END;
    END
-%]

<h2>Purchase Order [% target.id %]</h2>
<br/>
date <b>[% date.format(date.now, '%Y%m%d') %]</b>
<br/>

<style>
    table td { padding:5px; border:1px solid #aaa;}
    table { width:95%; border-collapse:collapse; }
    #vendor-notes { padding:5px; border:1px solid #aaa; }
</style>
<table id='vendor-table'>
  <tr>
    <td valign='top'>Vendor</td>
    <td>
      <div>[% target.provider.name %]</div>
      <div>[% target.provider.addresses.0.street1 %]</div>
      <div>[% target.provider.addresses.0.street2 %]</div>
      <div>[% target.provider.addresses.0.city %]</div>
      <div>[% target.provider.addresses.0.state %]</div>
      <div>[% target.provider.addresses.0.country %]</div>
      <div>[% target.provider.addresses.0.post_code %]</div>
    </td>
    <td valign='top'>Ship to / Bill to</td>
    <td>
      <div>[% target.ordering_agency.name %]</div>
      <div>[% target.ordering_agency.billing_address.street1 %]</div>
      <div>[% target.ordering_agency.billing_address.street2 %]</div>
      <div>[% target.ordering_agency.billing_address.city %]</div>
      <div>[% target.ordering_agency.billing_address.state %]</div>
      <div>[% target.ordering_agency.billing_address.country %]</div>
      <div>[% target.ordering_agency.billing_address.post_code %]</div>
    </td>
  </tr>
</table>

<br/><br/>
<fieldset id='vendor-notes'>
    <legend>Notes to the Vendor</legend>
    <ul>
    [% FOR note IN target.notes %]
        [% IF note.vendor_public == 't' %]
            <li>[% note.value %]</li>
        [% END %]
    [% END %]
    </ul>
</fieldset>
<br/><br/>

<table>
  <thead>
    <tr>
      <th>PO#</th>
      <th>ISBN or Item #</th>
      <th>Title</th>
      <th>Quantity</th>
      <th>Unit Price</th>
      <th>Line Total</th>
      <th>Notes</th>
    </tr>
  </thead>
  <tbody>

  [% subtotal = 0 %]
  [% FOR li IN target.lineitems %]

  <tr>
    [% count = li.lineitem_details.size %]
    [% price = li.estimated_unit_price %]
    [% litotal = (price * count) %]
    [% subtotal = subtotal + litotal %]
    [% 
        ident_attr = helpers.get_li_order_ident(li.attributes);
        SET ident_value = ident_attr.attr_value IF ident_attr;
    %]
    <td>[% target.id %]</td>
    <td>[% ident_value %]</td>
    <td>[% PROCESS get_li_attr attr_name = 'title' %]</td>
    <td>[% count %]</td>
    <td>[% price %]</td>
    <td>[% litotal %]</td>
    <td>
        <ul>
        [% FOR note IN li.lineitem_notes %]
            [% IF note.vendor_public == 't' %]
                <li>[% note.value %]</li>
            [% END %]
        [% END %]
        </ul>
    </td>
  </tr>
  [% END %]
  <tr>
    <td/><td/><td/><td/>
    <td>Subtotal</td>
    <td>[% subtotal %]</td>
  </tr>
  </tbody>
</table>

<br/>

Total Line Item Count: [% target.lineitems.size %]
$$
WHERE ID = 4; -- PO HTML

COMMIT;
