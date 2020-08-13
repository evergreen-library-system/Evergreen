
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1212', :eg_version); -- berick/sandbergja/gmcharlt

DELETE FROM actor.org_unit_setting
    WHERE name = 'ui.staff.angular_catalog.enabled';

DELETE FROM config.org_unit_setting_type_log 
    WHERE field_name = 'ui.staff.angular_catalog.enabled';

DELETE FROM config.org_unit_setting_type
    WHERE name = 'ui.staff.angular_catalog.enabled';

-- activate the stock hold-for-bib server print template
UPDATE config.print_template SET active = TRUE WHERE name = 'holds_for_bib';

COMMIT;
