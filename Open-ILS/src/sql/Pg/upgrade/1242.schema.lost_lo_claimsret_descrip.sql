BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1242', :eg_version);

-- Long Overdue
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
        'ui.circ.items_out.longoverdue',
'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
'or "Other/Special Circulations") the circulation '||
'should appear while checked out, and B. Whether the circulation should '||
'continue to appear in the "Other" tab when checked in with '||
'oustanding fines.  '||
'1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
'5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
WHERE NAME = 'ui.circ.items_out.longoverdue';

-- Lost
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
        'ui.circ.items_out.lost',
'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
'or "Other/Special Circulations") the circulation '||
'should appear while checked out, and B. Whether the circulation should '||
'continue to appear in the "Other" tab when checked in with '||
'oustanding fines.  '||
'1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
'5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
WHERE NAME = 'ui.circ.items_out.lost';

-- Claims Returned
UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext(
        'ui.circ.items_out.claimsreturned',
'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
'or "Other/Special Circulations") the circulation '||
'should appear while checked out, and B. Whether the circulation should '||
'continue to appear in the "Other" tab when checked in with '||
'oustanding fines.  '||
'1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
'5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
WHERE NAME = 'ui.circ.items_out.claimsreturned';

COMMIT;
