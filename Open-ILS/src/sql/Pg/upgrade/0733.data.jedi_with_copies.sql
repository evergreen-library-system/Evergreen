

-- XXX
-- Template update included here for reference only.
-- The stock JEDI template is not updated here (see WHERE clause)
-- We do update the environment, though, for easier local template 
-- updating.  No env fields are removed (that aren't otherwise replaced).
--

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0733', :eg_version);

UPDATE action_trigger.event_definition SET template =
$$[%- USE date -%]
[%# start JEDI document 
  # Vendor specific kludges:
  # BT      - vendcode goes to NAD/BY *suffix*  w/ 91 qualifier
  # INGRAM  - vendcode goes to NAD/BY *segment* w/ 91 qualifier (separately)
  # BRODART - vendcode goes to FTX segment (lineitem level)
-%]
[%- 
IF target.provider.edi_default.vendcode && target.provider.code == 'BRODART';
    xtra_ftx = target.provider.edi_default.vendcode;
END;
-%]
[%- BLOCK big_block -%]
{
   "recipient":"[% target.provider.san %]",
   "sender":"[% target.ordering_agency.mailing_address.san %]",
   "body": [{
     "ORDERS":[ "order", {
        "po_number":[% target.id %],
        "date":"[% date.format(date.now, '%Y%m%d') %]",
        "buyer":[
            [%   IF   target.provider.edi_default.vendcode && (target.provider.code == 'BT' || target.provider.name.match('(?i)^BAKER & TAYLOR'))  -%]
                {"id-qualifier": 91, "id":"[% target.ordering_agency.mailing_address.san _ ' ' _ target.provider.edi_default.vendcode %]"}
            [%- ELSIF target.provider.edi_default.vendcode && target.provider.code == 'INGRAM' -%]
                {"id":"[% target.ordering_agency.mailing_address.san %]"},
                {"id-qualifier": 91, "id":"[% target.provider.edi_default.vendcode %]"}
            [%- ELSE -%]
                {"id":"[% target.ordering_agency.mailing_address.san %]"}
            [%- END -%]
        ],
        "vendor":[
            [%- # target.provider.name (target.provider.id) -%]
            "[% target.provider.san %]",
            {"id-qualifier": 92, "id":"[% target.provider.id %]"}
        ],
        "currency":"[% target.provider.currency_type %]",
                
        "items":[
        [%- FOR li IN target.lineitems %]
        {
            "line_index":"[% li.id %]",
            "identifiers":[   [%-# li.isbns = helpers.get_li_isbns(li.attributes) %]
            [% FOR isbn IN helpers.get_li_isbns(li.attributes) -%]
                [% IF isbn.length == 13 -%]
                {"id-qualifier":"EN","id":"[% isbn %]"},
                [% ELSE -%]
                {"id-qualifier":"IB","id":"[% isbn %]"},
                [%- END %]
            [% END %]
                {"id-qualifier":"IN","id":"[% li.id %]"}
            ],
            "price":[% li.estimated_unit_price || '0.00' %],
            "desc":[
                {"BTI":"[% helpers.get_li_attr_jedi('title',     '', li.attributes) %]"},
                {"BPU":"[% helpers.get_li_attr_jedi('publisher', '', li.attributes) %]"},
                {"BPD":"[% helpers.get_li_attr_jedi('pubdate',   '', li.attributes) %]"},
                {"BPH":"[% helpers.get_li_attr_jedi('pagination','', li.attributes) %]"}
            ],
            [%- ftx_vals = []; 
                FOR note IN li.lineitem_notes; 
                    NEXT UNLESS note.vendor_public == 't'; 
                    ftx_vals.push(note.value); 
                END; 
                IF xtra_ftx;           ftx_vals.unshift(xtra_ftx); END; 
                IF ftx_vals.size == 0; ftx_vals.unshift('');       END;  # BT needs FTX+LIN for every LI, even if it is an empty one
            -%]

            "free-text":[ 
                [% FOR note IN ftx_vals -%] "[% note %]"[% UNLESS loop.last %], [% END %][% END %] 
            ],            
            "quantity":[% li.lineitem_details.size %],
            "copies" : [
                [%- IF 1 -%]
                [%- FOR lid IN li.lineitem_details;
                        fund = lid.fund.code;
                        item_type = lid.circ_modifier;
                        callnumber = lid.cn_label;
                        owning_lib = lid.owning_lib.shortname;
                        location = lid.location;
    
                        # when we have real copy data, treat it as authoritative
                        acp = lid.eg_copy_id;
                        IF acp;
                            item_type = acp.circ_modifier;
                            callnumber = acp.call_number.label;
                            location = acp.location.name;
                        END -%]
                {   [%- IF fund %] "fund" : "[% fund %]",[% END -%]
                    [%- IF callnumber %] "call_number" : "[% callnumber %]", [% END -%]
                    [%- IF item_type %] "item_type" : "[% item_type %]", [% END -%]
                    [%- IF location %] "copy_location" : "[% location %]", [% END -%]
                    [%- IF owning_lib %] "owning_lib" : "[% owning_lib %]", [% END -%]
                    [%- #chomp %]"copy_id" : "[% lid.id %]" }[% ',' UNLESS loop.last %]
                [% END -%]
                [%- END -%]
             ]
        }[% UNLESS loop.last %],[% END %]
        [%-# TODO: lineitem details (later) -%]
        [% END %]
        ],
        "line_items":[% target.lineitems.size %]
     }]  [%# close ORDERS array %]
   }]    [%# close  body  array %]
}
[% END %]
[% tempo = PROCESS big_block; helpers.escape_json(tempo) %]
$$
WHERE id = 23 AND FALSE; -- DON'T PERFORM THE UPDATE


-- add copy-related fields to the environment if they're not already there.
DO $$
BEGIN
    PERFORM 1 
        FROM action_trigger.environment 
        WHERE 
            event_def = 23 AND 
            path = 'lineitems.lineitem_details.owning_lib';
    IF NOT FOUND THEN
        INSERT INTO action_trigger.environment (event_def, path) 
            VALUES (23, 'lineitems.lineitem_details.owning_lib'); 
    END IF;

    PERFORM 1 
        FROM action_trigger.environment 
        WHERE 
            event_def = 23 AND 
            path = 'lineitems.lineitem_details.fund';
    IF NOT FOUND THEN
        INSERT INTO action_trigger.environment (event_def, path) 
            VALUES (23, 'lineitems.lineitem_details.fund'); 
    END IF;

    PERFORM 1 
        FROM action_trigger.environment 
        WHERE 
            event_def = 23 AND 
            path = 'lineitems.lineitem_details.location';
    IF NOT FOUND THEN
        INSERT INTO action_trigger.environment (event_def, path) 
            VALUES (23, 'lineitems.lineitem_details.location'); 
    END IF;

    PERFORM 1 
        FROM action_trigger.environment 
        WHERE 
            event_def = 23 AND 
            path = 'lineitems.lineitem_details.eg_copy_id.location';
    IF NOT FOUND THEN
        INSERT INTO action_trigger.environment (event_def, path) 
            VALUES (23, 'lineitems.lineitem_details.eg_copy_id.location'); 
    END IF;

    PERFORM 1 
        FROM action_trigger.environment 
        WHERE 
            event_def = 23 AND 
            path = 'lineitems.lineitem_details.eg_copy_id.call_number';
    IF NOT FOUND THEN
        INSERT INTO action_trigger.environment (event_def, path) 
            VALUES (23, 'lineitems.lineitem_details.eg_copy_id.call_number'); 
    END IF;



    -- remove redundant entry
    DELETE FROM action_trigger.environment 
        WHERE event_def = 23 AND path = 'lineitems.lineitem_details'; 

END $$;

COMMIT;

