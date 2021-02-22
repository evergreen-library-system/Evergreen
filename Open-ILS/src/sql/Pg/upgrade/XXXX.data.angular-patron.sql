
BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version); 

/*
INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.catalog.results.count', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.catalog.results.count',
        'Catalog Results Page Size',
        'cwst', 'label'
    )
);

eg.circ.patron.holds.prefetch

eg.grid.circ.patron.holds

holds_for_patron print template

items out print template
*/

-- insert then update for easier iterative development tweaks
/*
INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('items_out', 'Patron Items Out', 1, TRUE, 'en-US', 'text/html', '');
*/

UPDATE config.print_template SET template = $TEMPLATE$
[% 
	USE date;
	circulations = template_data.circulations;
%]
<div>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You have the following items:</div>
  <hr/>
  <ol>
  [% FOR checkout IN circulations %]
    <li>
      <div>[% checkout.title %]</div>
      <div>
	    [% IF checkout.copy %]Barcode: [% checkout.copy.barcode %][% END %]
		Due: [% date.format(helpers.format_date(checkout.dueDate, staff_org_timezone), '%x %r') %]
      </div>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>[% staff_org.name %] [% date.format(date.now, '%x %r') %]</div>
  <div>You were helped by [% staff.first_given_name %]</div>
  <br/>
</div>
$TEMPLATE$ WHERE name = 'items_out';

COMMIT;


