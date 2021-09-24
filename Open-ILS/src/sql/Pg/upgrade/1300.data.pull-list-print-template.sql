
BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

-- NOTE: If the template ID requires changing, beware it appears in
-- 3 places below.

INSERT INTO config.print_template 
    (id, name, locale, active, owner, label, template) 
VALUES (
    4, 'hold_pull_list', 'en-US', TRUE,
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    oils_i18n_gettext(4, 'Hold Pull List ', 'cpt', 'label'),
    ''
);

UPDATE config.print_template SET template = 
$TEMPLATE$
[%-
    USE date;
    SET holds = template_data;
    # template_data is an arry of wide_hold hashes.
-%]
<div>
  <style>
    #holds-pull-list-table td { 
      padding: 5px; 
      border: 1px solid rgba(0,0,0,.05);
    }
  </style>
  <table id="holds-pull-list-table">
    <thead>
      <tr>
        <th>Type</th>
        <th>Title</th>
        <th>Author</th>
        <th>Shelf Location</th>
        <th>Call Number</th>
        <th>Barcode/Part</th>
      </tr>
    </thead>
    <tbody>
      [% FOR hold IN holds %]
      <tr>
        <td>[% hold.hold_type %]</td>
        <td style="width: 30%">[% hold.title %]</td>
        <td style="width: 25%">[% hold.author %]</td>
        <td>[% hold.acpl_name %]</td>
        <td>[% hold.cn_full_label %]</td>
        <td>[% hold.cp_barcode %][% IF hold.p_label %]/[% hold.p_label %][% END %]</td>
      </tr>
      [% END %]
    </tbody>
  </table>
</div>
$TEMPLATE$ WHERE id = 4;

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.circ.holds.pull_list', 'gui', 'object', 
    oils_i18n_gettext(
        'circ.holds.pull_list',
        'Hold Pull List Grid Settings',
        'cwst', 'label'
    )
), (
    'circ.holds.pull_list.prefetch', 'gui', 'bool', 
    oils_i18n_gettext(
        'circ.holds.pull_list.prefetch',
        'Hold Pull List Prefetch Preference',
        'cwst', 'label'
    )
);

COMMIT;

