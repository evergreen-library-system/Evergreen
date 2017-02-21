BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- The following billing types would not have been automatically added
-- in upgrade scripts between versions 1.2 and 1.4 (early 2009).  We
-- add them here.  It's okay if they fail, so this should probably be 
-- run outside a transaction if added to the version-upgrade scripts.

INSERT INTO config.billing_type (id, name, owner) VALUES
    ( 7, oils_i18n_gettext(7, 'Damaged Item', 'cbt', 'name'), 1);
INSERT INTO config.billing_type (id, name, owner) VALUES
    ( 8, oils_i18n_gettext(8, 'Damaged Item Processing Fee', 'cbt', 'name'), 1);
INSERT INTO config.billing_type (id, name, owner) VALUES
    ( 9, oils_i18n_gettext(9, 'Notification Fee', 'cbt', 'name'), 1);

COMMIT;
