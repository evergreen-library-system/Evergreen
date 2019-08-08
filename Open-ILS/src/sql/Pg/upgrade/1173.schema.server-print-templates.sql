BEGIN;

SELECT evergreen.upgrade_deps_block_check('1173', :eg_version);

CREATE TABLE config.print_template (
    id           SERIAL PRIMARY KEY,
    name         TEXT NOT NULL, -- programatic name
    label        TEXT NOT NULL, -- i18n
    owner        INT NOT NULL REFERENCES actor.org_unit (id),
    active       BOOLEAN NOT NULL DEFAULT FALSE,
    locale       TEXT REFERENCES config.i18n_locale(code) 
                 ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    content_type TEXT NOT NULL DEFAULT 'text/html',
    template     TEXT NOT NULL,
	CONSTRAINT   name_once_per_lib UNIQUE (owner, name),
	CONSTRAINT   label_once_per_lib UNIQUE (owner, label)
);

INSERT INTO config.print_template 
    (id, name, locale, active, owner, label, template) 
VALUES (
    1, 'patron_address', 'en-US', FALSE,
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    oils_i18n_gettext(1, 'Address Label', 'cpt', 'label'),
$TEMPLATE$
[%-
    SET patron = template_data.patron;
    SET addr = template_data.address;
-%]
<div>
  <div>
    [% patron.first_given_name %] 
    [% patron.second_given_name %] 
    [% patron.family_name %]
  </div>
  <div>[% addr.street1 %]</div>
  [% IF addr.street2 %]<div>[% addr.street2 %]</div>[% END %]
  <div>
    [% addr.city %], [% addr.state %] [% addr.post_code %]
  </div>
</div>
$TEMPLATE$
);

INSERT INTO config.print_template 
    (id, name, locale, active, owner, label, template) 
VALUES (
    2, 'holds_for_bib', 'en-US', FALSE,
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    oils_i18n_gettext(2, 'Holds for Bib Record', 'cpt', 'label'),
$TEMPLATE$
[%-
    USE date;
    SET holds = template_data;
    # template_data is an arry of wide_hold hashes.
-%]
<div>
  <div>Holds for record: [% holds.0.title %]</div>
  <hr/>
  <style>#holds-for-bib-table td { padding: 5px; }</style>
  <table id="holds-for-bib-table">
    <thead>
      <tr>
        <th>Request Date</th>
        <th>Patron Barcode</th>
        <th>Patron Last</th>
        <th>Patron Alias</th>
        <th>Current Item</th>
      </tr>
    </thead>
    <tbody>
      [% FOR hold IN holds %]
      <tr>
        <td>[% 
          date.format(helpers.format_date(
            hold.request_time, staff_org_timezone), '%x %r', locale) 
        %]</td>
        <td>[% hold.ucard_barcode %]</td>
        <td>[% hold.usr_family_name %]</td>
        <td>[% hold.usr_alias %]</td>
        <td>[% hold.cp_barcode %]</td>
      </tr>
      [% END %]
    </tbody>
  </table>
  <hr/>
  <div>
    [% staff_org.shortname %] 
    [% date.format(helpers.current_date(client_timezone), '%x %r', locale) %]
  </div>
  <div>Printed by [% staff.first_given_name %]</div>
</div>
<br/>

$TEMPLATE$
);

-- Allow for 1k stock templates
SELECT SETVAL('config.print_template_id_seq'::TEXT, 1000);

INSERT INTO permission.perm_list (id, code, description) 
VALUES (611, 'ADMIN_PRINT_TEMPLATE', 
    oils_i18n_gettext(611, 'Modify print templates', 'ppl', 'description'));

COMMIT;

