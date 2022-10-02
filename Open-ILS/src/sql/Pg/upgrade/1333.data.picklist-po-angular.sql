BEGIN;

SELECT evergreen.upgrade_deps_block_check('1333', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.acq.lineitem.history', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.lineitem.history',
        'Grid Config: Acq Lineitem History',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.po.history', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.po.history',
        'Grid Config: Acq PO History',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.po.edi_messages', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.po.edi_messages',
        'Grid Config: Acq PO EDI Messages',
        'cwst', 'label'
    )
), (
    'acq.lineitem.page_size', 'gui', 'integer',
    oils_i18n_gettext(
        'acq.lineitem.page_size',
        'ACQ Lineitem List Page Size',
        'cwst', 'label'
    )
), (
    'ui.staff.angular_acq_search.enabled', 'gui', 'bool',
    oils_i18n_gettext(
        'ui.staff.angular_acq_search.enabled',
        'Enable Experimental ACQ Selection/Purchase Search Interface Links',
        'cwst', 'label'
    )
);

INSERT INTO config.print_template
    (id, name, label, owner, active, locale, template)
VALUES (
    5, 'lineitem_worksheet', 'Lineitem Worksheet', 1, TRUE, 'en-US',
$TEMPLATE$
[%- 
  USE money=format('%.2f');
  USE date;
  SET li = template_data.lineitem;
  SET title = '';
  SET author = '';
  FOREACH attr IN li.attributes;
    IF attr.attr_type == 'lineitem_marc_attr_definition';
      IF attr.attr_name == 'title';
        title = attr.attr_value;
      ELSIF attr.attr_name == 'author';
        author = attr.attr_value;
      END;
    END;
  END;
-%]

<div class="wrapper">
    <div class="summary" style='font-size:110%; font-weight:bold;'>
        <div>Title: [% title.substr(0, 80) %][% IF title.length > 80 %]...[% END %]</div>
        <div>Author: [% author %]</div>
        <div>Item Count: [% li.lineitem_details.size %]</div>
        <div>Lineitem ID: [% li.id %]</div>
        <div>PO # : [% li.purchase_order %]</div>
        <div>Est. Price: [% money(li.estimated_unit_price) %]</div>
        <div>Open Holds: [% template_data.hold_count %]</div>
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
                <td style='padding:5px;'>[% IF detail.recv_time %]<span class="recv_time">[% date.format(helpers.format_date(detail.recv_time, staff_org_timezone), '%x %r', locale) %]</span>[% END %]</td>
                <td style='padding:5px;'>[% detail.note %]</td>
                <td style='padding:5px;'>[% detail.cancel_reason.label %]</td>
            </tr>
        [% END %]
        </tbody>
    </table>
</div>
$TEMPLATE$
);

INSERT INTO config.print_template
    (id, name, label, owner, active, locale, template)
VALUES (6, 'purchase_order', 'Purchase Order', 1, TRUE, 'en-US', 
$TEMPLATE$

[%- 
  USE date;
  USE String;
  USE money=format('%.2f');
  SET po = template_data.po;

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
  END;

  BLOCK get_li_order_attr_value;
    FOR attr IN li.attributes;
      IF attr.order_ident == 't';
        attr.attr_value;
        LAST;
      END;
    END;
  END;
-%]

<table style="width:100%">
  <thead>
    <tr>
      <th>PO#</th>
      <th>Line#</th>
      <th>ISBN / Item # / Charge Type</th>
      <th>Title</th>
      <th>Author</th>
      <th>Pub Info</th>
      <th>Quantity</th>
      <th>Unit Price</th>
      <th>Line Total</th>
    </tr>
  </thead>
  <tbody>
[% 
  SET subtotal = 0;
  FOR li IN po.lineitems;

    SET idval = '';
    IF vendnum != '';
      idval = PROCESS get_li_attr attr_name = 'vendor_num';
    END;
    IF !idval;
      idval = PROCESS get_li_order_attr_value;
    END;
-%]
    <tr>
      <td>[% po.id %]</td>
      <td>[% li.id %]</td>
      <td>[% idval %]</td>
      <td>[% PROCESS get_li_attr attr_name = 'title' %]</td>
      <td>[% PROCESS get_li_attr attr_name = 'author' %]</td>
      <td>
        <div>
          [% PROCESS get_li_attr attr_name = 'publisher' %], 
          [% PROCESS get_li_attr attr_name = 'pubdate' %]
        </div>
        <div>Edition: [% PROCESS get_li_attr attr_name = 'edition' %]</div>
      </td>
      [%- 
        SET count = li.lineitem_details.size;
        SET price = li.estimated_unit_price;
        SET itotal = (price * count);
      %]
      <td>[% count %]</td>
      <td>[% money(price) %]</td>
      <td>[% money(litotal) %]</td>
    </tr>
  [% END %]

  </tbody>
</table>



$TEMPLATE$
);


COMMIT;


