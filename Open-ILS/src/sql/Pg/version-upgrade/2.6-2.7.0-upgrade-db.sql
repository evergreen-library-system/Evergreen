--Upgrade Script for 2.6 to 2.7.0
\set eg_version '''2.7.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.7.0', :eg_version);
-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0884', :eg_version);

UPDATE container.biblio_record_entry_bucket_type
SET label = oils_i18n_gettext(
	'bookbag',
	'Book List',
	'cbrebt',
	'label'
) WHERE code = 'bookbag';

UPDATE container.user_bucket_type
SET label = oils_i18n_gettext(
	'folks:pub_book_bags.view',
	'List Published Book Lists',
	'cubt',
	'label'
) WHERE code = 'folks:pub_book_bags.view';

UPDATE container.user_bucket_type
SET label = oils_i18n_gettext(
	'folks:pub_book_bags.add',
	'Add to Published Book Lists',
	'cubt',
	'label'
) WHERE code = 'folks:pub_book_bags.add';

UPDATE action_trigger.hook
SET description = oils_i18n_gettext(
	'container.biblio_record_entry_bucket.csv',
	'Produce a CSV file representing a book list',
	'ath',
	'description'
) WHERE key = 'container.biblio_record_entry_bucket.csv';

UPDATE action_trigger.reactor
SET description = oils_i18n_gettext(
	'ContainerCSV',
	'Facilitates producing a CSV file representing a book list by introducing an "items" variable into the TT environment, sorted as dictated according to user params',
	'atr',
	'description'
)
WHERE module = 'ContainerCSV';

UPDATE action_trigger.event_definition
SET template = REPLACE(template, 'bookbag', 'book list'),
name = 'Book List CSV'
WHERE name = 'Bookbag CSV';

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
	'opac.patron.temporary_list_warn',
	'Present a warning dialog to the patron when a patron adds a book to a temporary book list.',
	'coust',
	'description'
) WHERE name = 'opac.patron.temporary_list_warn';

UPDATE config.usr_setting_type
SET label = oils_i18n_gettext(
	'opac.default_list',
	'Default list to use when adding to a list',
	'cust',
	'label'
),
description = oils_i18n_gettext(
	'opac.default_list',
	'Default list to use when adding to a list',
	'cust',
	'description'
) WHERE name = 'opac.default_list';


SELECT evergreen.upgrade_deps_block_check('0885', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes(
    bibid BIGINT[],
    ouid INT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[]
) RETURNS TABLE(id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT) AS $$
    WITH RECURSIVE ou_depth AS (
        SELECT COALESCE(
            $3,
            (
                SELECT depth
                FROM actor.org_unit_type aout
                    INNER JOIN actor.org_unit ou ON ou_type = aout.id
                WHERE ou.id = $2
            )
        ) AS depth
    ), descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ad ON (ad.id = ou.id),
                ou_depth
        WHERE ad.depth = ou_depth.depth
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ), anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
        WHERE ou.id = $2
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ), descendants as (
        SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id)
    )

    SELECT ua.id, ua.name, ua.label_sortkey, MIN(ua.rank) AS rank FROM (
        SELECT acn.id, aou.name, acn.label_sortkey,
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN descendants AS aou ON (acp.circ_lib = aou.id)
        WHERE acn.record = ANY ($1)
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
            AND CASE WHEN ('exclude_invisible_acn' = ANY($7)) THEN
                EXISTS (
                    SELECT 1
                    FROM asset.opac_visible_copies
                    WHERE copy_id = acp.id AND record = acn.record
                ) ELSE TRUE END
        GROUP BY acn.id, acp.status, aou.name, acn.label_sortkey, aou.id
        WINDOW w AS (
            ORDER BY
                COALESCE(
                    CASE WHEN aou.id = $2 THEN -20000 END,
                    CASE WHEN aou.id = $6 THEN -10000 END,
                    (SELECT distance - 5000
                        FROM actor.org_unit_descendants_distance($6) as x
                        WHERE x.id = aou.id AND $6 IN (
                            SELECT q.id FROM actor.org_unit_descendants($2) as q)),
                    (SELECT e.distance FROM actor.org_unit_descendants_distance($2) as e WHERE e.id = aou.id),
                    1000
                ),
                evergreen.rank_cp_status(acp.status)
        )
    ) AS ua
    GROUP BY ua.id, ua.name, ua.label_sortkey
    ORDER BY rank, ua.name, ua.label_sortkey
    LIMIT ($4 -> 'acn')::INT
    OFFSET ($5 -> 'acn')::INT;
$$ LANGUAGE SQL STABLE ROWS 10;

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes
    ( bibid BIGINT, ouid INT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, pref_lib INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[] )
    RETURNS TABLE (id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT)
    AS $$ SELECT * FROM evergreen.ranked_volumes(ARRAY[$1],$2,$3,$4,$5,$6,$7) $$ LANGUAGE SQL STABLE;


SELECT evergreen.upgrade_deps_block_check('0886', :eg_version);

INSERT INTO config.copy_status
(id, name, holdable, opac_visible, copy_active, restrict_copy_delete)
VALUES (17, 'Lost and Paid', FALSE, FALSE, FALSE, TRUE);

INSERT INTO config.org_unit_setting_type
(name, grp, label, description, datatype)
VALUES
('circ.use_lost_paid_copy_status',
 'circ',
 oils_i18n_gettext('circ.use_lost_paid_copy_status',
     'Use Lost and Paid copy status',
     'coust', 'label'),
 oils_i18n_gettext('circ.use_lost_paid_copy_status',
     'Use Lost and Paid copy status when lost or long overdue billing is paid',
     'coust', 'description'),
 'bool');


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0888', :eg_version);

DROP VIEW acq.lineitem_summary;

CREATE VIEW acq.lineitem_summary AS
    SELECT 
        li.id AS lineitem, 
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
            WHERE lineitem = li.id
        ) AS item_count,
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
            WHERE recv_time IS NOT NULL AND lineitem = li.id
        ) AS recv_count,
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
                JOIN acq.cancel_reason acqcr ON (acqcr.id = lid.cancel_reason)
            WHERE acqcr.keep_debits IS FALSE AND lineitem = li.id
        ) AS cancel_count,
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
                JOIN acq.cancel_reason acqcr ON (acqcr.id = lid.cancel_reason)
            WHERE acqcr.keep_debits IS TRUE AND lineitem = li.id
        ) AS delay_count,
        (
            SELECT COUNT(lid.id) 
            FROM acq.lineitem_detail lid
                JOIN acq.fund_debit debit ON (lid.fund_debit = debit.id)
            WHERE NOT debit.encumbrance AND lineitem = li.id
        ) AS invoice_count,
        (
            SELECT COUNT(DISTINCT(lid.id)) 
            FROM acq.lineitem_detail lid
                JOIN acq.claim claim ON (claim.lineitem_detail = lid.id)
            WHERE lineitem = li.id
        ) AS claim_count,
        (
            SELECT (COUNT(lid.id) * li.estimated_unit_price)::NUMERIC(8,2)
            FROM acq.lineitem_detail lid
            WHERE lid.cancel_reason IS NULL AND lineitem = li.id
        ) AS estimated_amount,
        (
            SELECT SUM(debit.amount)::NUMERIC(8,2)
            FROM acq.lineitem_detail lid
                JOIN acq.fund_debit debit ON (lid.fund_debit = debit.id)
            WHERE debit.encumbrance AND lineitem = li.id
        ) AS encumbrance_amount,
        (
            SELECT SUM(debit.amount)::NUMERIC(8,2)
            FROM acq.lineitem_detail lid
                JOIN acq.fund_debit debit ON (lid.fund_debit = debit.id)
            WHERE NOT debit.encumbrance AND lineitem = li.id
        ) AS paid_amount

        FROM acq.lineitem AS li;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0889', :eg_version);

-- Update ACQ cancel reason names, but only those that 
-- have not already been locally modified from stock values.

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Invalid ISBN', 'acqcr', 'label')
    WHERE id = 1 AND label = 'invalid_isbn';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Postpone', 'acqcr', 'label')
    WHERE id = 2 AND label = 'postpone';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Delivered but Lost', 'acqcr', 'label')
    WHERE id = 3 AND label = 'delivered_but_lost';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Deleted', 'acqcr', 'label')
    WHERE id = 1002 AND label = 'Deleted';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Changed', 'acqcr', 'label')
    WHERE id = 1003 AND label = 'Changed';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: No Action', 'acqcr', 'label')
    WHERE id = 1004 AND label = 'No action';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Accepted without amendment', 'acqcr', 'label')
    WHERE id = 1005 AND label = 'Accepted without amendment';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Not Accepted', 'acqcr', 'label')
    WHERE id = 1007 AND label = 'Not accepted';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Canceled: Not Found', 'acqcr', 'label')
    WHERE id = 1010 AND label = 'Not found';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Accepted with amendment', 'acqcr', 'label')
    WHERE id = 1024 AND label = 'Accepted with amendment, no confirmation required';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Split Quantity', 'acqcr', 'label')
    WHERE id = 1211 AND label = 'Split quantity';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Ordered Quantity', 'acqcr', 'label')
    WHERE id = 1221 AND label = 'Ordered quantity';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Pieces Delivered', 'acqcr', 'label')
    WHERE id = 1246 AND label = 'Pieces delivered';

UPDATE acq.cancel_reason 
    SET label = oils_i18n_gettext(1,'Delayed: Backorder', 'acqcr', 'label')
    WHERE id = 1283 AND label = 'Backorder quantity';

-- action/trigger additions
-- All following changes are only applied where the source data matches
-- the stock data.  IOW, if a template has been locally modified, 
-- it's left unchanged.

DO $$
BEGIN
    -- avoid collisions by testing for the presence of the 
    -- desired environment addition.

    PERFORM 1 FROM action_trigger.environment
        WHERE event_def = 4 AND path = 'lineitems.cancel_reason';
    IF NOT FOUND THEN 
        INSERT INTO action_trigger.environment (event_def, path) 
            VALUES (4, 'lineitems.cancel_reason');
    END IF;

    PERFORM 1 FROM action_trigger.environment
        WHERE event_def = 14 AND path = 'cancel_reason';
    IF NOT FOUND THEN 
        INSERT INTO action_trigger.environment (event_def, path) 
            VALUES ( 14, 'cancel_reason' );
    END IF;

    PERFORM 1 FROM action_trigger.environment
        WHERE event_def = 14 AND path = 'lineitem_details.cancel_reason';
    IF NOT FOUND THEN 
        INSERT INTO action_trigger.environment (event_def, path) 
            VALUES ( 14, 'lineitem_details.cancel_reason' );
    END IF;
END $$;

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

<h2>Purchase Order: [% target.name %] ([% target.id %])</h2>
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
      <th>Delayed / Canceled</th>
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
    <td>[% li.cancel_reason.label %]</td>
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
WHERE id = 4 AND template = 
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

<h2>Purchase Order: [% target.name %] ([% target.id %])</h2>
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
$$;

-- lineitem worksheet
UPDATE action_trigger.event_definition SET template =
$$
[%- USE date -%]
[%- SET li = target; -%]
<div class="wrapper">
    <div class="summary" style='font-size:110%; font-weight:bold;'>

        <div>Title: [% helpers.get_li_attr("title", "", li.attributes) %]</div>
        <div>Author: [% helpers.get_li_attr("author", "", li.attributes) %]</div>
        <div class="count">Item Count: [% li.lineitem_details.size %]</div>
        <div class="lineid">Lineitem ID: [% li.id %]</div>
        <div>Open Holds: [% helpers.bre_open_hold_count(li.eg_bib_id) %]</div>
        [% IF li.cancel_reason.label %]
        <div>[% li.cancel_reason.label %]</div>
        [% END %]

        [% IF li.distribution_formulas.size > 0 %]
            [% SET forms = [] %]
            [% FOREACH form IN li.distribution_formulas; forms.push(form.formula.name); END %]
            <div>Distribution Formulas: [% forms.join(',') %]</div>
        [% END %]

        [% IF li.lineitem_notes.size > 0 %]
            Lineitem Notes:
            <ul>
                [%- FOR note IN li.lineitem_notes -%]
                    <li>
                    [% IF note.alert_text %]
                        [% note.alert_text.code -%] 
                        [% IF note.value -%]
                            : [% note.value %]
                        [% END %]
                    [% ELSE %]
                        [% note.value -%] 
                    [% END %]
                    </li>
                [% END %]
            </ul>
        [% END %]
    </div>
    <br/>
    <table>
        <thead>
            <tr>
                <th>Branch</th>
                <th>Barcode</th>
                <th>Call Number</th>
                <th>Fund</th>
                <th>Shelving Location</th>
                <th>Recd.</th>
                <th>Notes</th>
                <th>Delayed / Canceled</th>
            </tr>
        </thead>
        <tbody>
        <!-- set detail.owning_lib from fm object to org name -->
        [% FOREACH detail IN li.lineitem_details %]
            [% detail.owning_lib = detail.owning_lib.shortname %]
        [% END %]

        [% FOREACH detail IN li.lineitem_details.sort('owning_lib') %]
            [% 
                IF detail.eg_copy_id;
                    SET copy = detail.eg_copy_id;
                    SET cn_label = copy.call_number.label;
                ELSE; 
                    SET copy = detail; 
                    SET cn_label = detail.cn_label;
                END 
            %]
            <tr>
                <!-- acq.lineitem_detail.id = [%- detail.id -%] -->
                <td style='padding:5px;'>[% detail.owning_lib %]</td>
                <td style='padding:5px;'>[% IF copy.barcode   %]<span class="barcode"  >[% detail.barcode   %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF cn_label %]<span class="cn_label" >[% cn_label  %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF detail.fund %]<span class="fund">[% detail.fund.code %] ([% detail.fund.year %])</span>[% END %]</td>
                <td style='padding:5px;'>[% copy.location.name %]</td>
                <td style='padding:5px;'>[% IF detail.recv_time %]<span class="recv_time">[% detail.recv_time %]</span>[% END %]</td>
                <td style='padding:5px;'>[% detail.note %]</td>
                <td style='padding:5px;'>[% detail.cancel_reason.label %]</td>
            </tr>
        [% END %]
        </tbody>
    </table>
</div>
$$
WHERE id = 14 AND template = 
$$
[%- USE date -%]
[%- SET li = target; -%]
<div class="wrapper">
    <div class="summary" style='font-size:110%; font-weight:bold;'>

        <div>Title: [% helpers.get_li_attr("title", "", li.attributes) %]</div>
        <div>Author: [% helpers.get_li_attr("author", "", li.attributes) %]</div>
        <div class="count">Item Count: [% li.lineitem_details.size %]</div>
        <div class="lineid">Lineitem ID: [% li.id %]</div>
        <div>Open Holds: [% helpers.bre_open_hold_count(li.eg_bib_id) %]</div>

        [% IF li.distribution_formulas.size > 0 %]
            [% SET forms = [] %]
            [% FOREACH form IN li.distribution_formulas; forms.push(form.formula.name); END %]
            <div>Distribution Formulas: [% forms.join(',') %]</div>
        [% END %]

        [% IF li.lineitem_notes.size > 0 %]
            Lineitem Notes:
            <ul>
                [%- FOR note IN li.lineitem_notes -%]
                    <li>
                    [% IF note.alert_text %]
                        [% note.alert_text.code -%] 
                        [% IF note.value -%]
                            : [% note.value %]
                        [% END %]
                    [% ELSE %]
                        [% note.value -%] 
                    [% END %]
                    </li>
                [% END %]
            </ul>
        [% END %]
    </div>
    <br/>
    <table>
        <thead>
            <tr>
                <th>Branch</th>
                <th>Barcode</th>
                <th>Call Number</th>
                <th>Fund</th>
                <th>Shelving Location</th>
                <th>Recd.</th>
                <th>Notes</th>
            </tr>
        </thead>
        <tbody>
        <!-- set detail.owning_lib from fm object to org name -->
        [% FOREACH detail IN li.lineitem_details %]
            [% detail.owning_lib = detail.owning_lib.shortname %]
        [% END %]

        [% FOREACH detail IN li.lineitem_details.sort('owning_lib') %]
            [% 
                IF detail.eg_copy_id;
                    SET copy = detail.eg_copy_id;
                    SET cn_label = copy.call_number.label;
                ELSE; 
                    SET copy = detail; 
                    SET cn_label = detail.cn_label;
                END 
            %]
            <tr>
                <!-- acq.lineitem_detail.id = [%- detail.id -%] -->
                <td style='padding:5px;'>[% detail.owning_lib %]</td>
                <td style='padding:5px;'>[% IF copy.barcode   %]<span class="barcode"  >[% detail.barcode   %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF cn_label %]<span class="cn_label" >[% cn_label  %]</span>[% END %]</td>
                <td style='padding:5px;'>[% IF detail.fund %]<span class="fund">[% detail.fund.code %] ([% detail.fund.year %])</span>[% END %]</td>
                <td style='padding:5px;'>[% copy.location.name %]</td>
                <td style='padding:5px;'>[% IF detail.recv_time %]<span class="recv_time">[% detail.recv_time %]</span>[% END %]</td>
                <td style='padding:5px;'>[% detail.note %]</td>
            </tr>
        [% END %]
        </tbody>
    </table>
</div>
$$;


COMMIT;
