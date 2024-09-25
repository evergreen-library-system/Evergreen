BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE config.ui_staff_portal_page_entry
ADD COLUMN url_newtab boolean;

COMMIT;
