BEGIN;

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
