BEGIN;

--SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

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
);

INSERT INTO config.print_template
    (id, name, label, owner, active, locale, template)
VALUES (
    4, 'lineitem_worksheet', 'Lineitem Worksheet', 1, TRUE, 'en-US',
$TEMPLATE$
[%- 
  USE money=format('%.2f');
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

<div>Title: [% title.substr(0, 80) %][% IF title.length > 80 %]...[% END %]</div>
<div>Author: [% author %]</div>
<div>Item Count: [% li.lineitem_details.size %]</div>
<div>Lineitem ID: [% li.id %]</div>
<div>PO # : [% li.purchase_order%]</div>
<div>Est. Price: [% money(li.estimated_unit_price) %]</div>

$TEMPLATE$
);

INSERT INTO config.print_template
    (id, name, label, owner, active, locale, template)
VALUES (5, 'purchase_order', 'Purchase Order', 1, TRUE, 'en-US', 
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


