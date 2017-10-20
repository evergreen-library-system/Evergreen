--Upgrade Script for 2.12.6 to 2.12.7
\set eg_version '''2.12.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.12.7', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1078', :eg_version); -- csharp/bshum/gmcharlt

-- The following billing types would not have been automatically added
-- in upgrade scripts between versions 1.2 and 1.4 (early 2009).  We
-- add them here.  It's okay if they fail, so this should probably be 
-- run outside a transaction if added to the version-upgrade scripts.

INSERT INTO config.billing_type (id, name, owner)
    SELECT 7, 'Damaged Item', 1
    WHERE NOT EXISTS (SELECT 1 FROM config.billing_type WHERE name = 'Damaged Item');

INSERT INTO config.billing_type (id, name, owner)
    SELECT 8, 'Damaged Item Processing Fee', 1
    WHERE NOT EXISTS (SELECT 1 FROM config.billing_type WHERE name = 'Damaged Item Processing Fee');

INSERT INTO config.billing_type (id, name, owner)
    SELECT 9, 'Notification Fee', 1
    WHERE NOT EXISTS (SELECT 1 FROM config.billing_type WHERE name = 'Notification Fee');

COMMIT;
