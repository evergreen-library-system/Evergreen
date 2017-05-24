--Upgrade Script for 2.11.4 to 2.11.5
\set eg_version '''2.11.5'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.11.5', :eg_version);
-- Evergreen DB patch XXXX.data.fix_long_overdue_perm.sql
--
-- Update permission 549 to have a "code" value that matches what
-- the Perl code references
--


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1037', :eg_version); -- jeff

-- For some time now, the database seed data / upgrade scripts have created
-- a permission with id 549 and code COPY_STATUS_LONGOVERDUE.override, while
-- the Perl code references a permission with code
-- COPY_STATUS_LONG_OVERDUE.override
--
-- Below, we attempt to handle at least three possible database states:
--
-- 1) no corrective action has been taken, permission exists with id 549 and
--    code COPY_STATUS_LONGOVERDUE.override
--
-- 2) permission with id 549 has already been updated to have code
--    COPY_STATUS_LONG_OVERDUE.override
--
-- 3) new permission with unknown id and code COPY_STATUS_LONG_OVERDUE.override
--    has been added, and potentially assigned to users/groups
--
-- In the case of 3, users and groups may have been assigned both perm id 549
-- and the local permission of unknown id.
--
-- The desired end result is that we should have a permission.perm_list
-- entry with id 549 and code COPY_STATUS_LONG_OVERDUE.override,
-- any locally-created permission with that same code but a different id
-- is deleted, and any users or groups that had been granted that locally-created
-- permission (by id) have been granted permission id 549 if not already granted.
--
-- If for some reason the permission at id 549 has an unexpected value for "code",
-- the end result of this upgrade script should be a no-op.

-- grant permission 549 to any group that
-- has a potentially locally-added perm
-- with code COPY_STATUS_LONG_OVERDUE.override
WITH new_grp_perms AS (
SELECT grp, 549 AS perm, depth, grantable
FROM permission.grp_perm_map pgpm
JOIN permission.perm_list ppl ON ppl.id = pgpm.perm
WHERE ppl.code = 'COPY_STATUS_LONG_OVERDUE.override'
-- short circuit if perm id 549 exists and doesn't have the expected code
AND EXISTS (SELECT 1 FROM permission.perm_list ppl WHERE ppl.id = 549 and ppl.code = 'COPY_STATUS_LONGOVERDUE.override')
-- don't try to assign perm 549 if already assigned
AND NOT EXISTS (SELECT 1 FROM permission.grp_perm_map pgpm2 WHERE pgpm2.grp = pgpm.grp AND pgpm2.perm = 549)
)
INSERT INTO permission.grp_perm_map
(grp, perm, depth, grantable)
SELECT grp, perm, depth, grantable
FROM new_grp_perms;

-- grant permission 549 to any user that
-- has a potentially locally-added perm
-- with code COPY_STATUS_LONG_OVERDUE.override
WITH new_usr_perms AS (
SELECT usr, 549 AS perm, depth, grantable
FROM permission.usr_perm_map pupm
JOIN permission.perm_list ppl ON ppl.id = pupm.perm
WHERE ppl.code = 'COPY_STATUS_LONG_OVERDUE.override'
-- short circuit if perm id 549 exists and doesn't have the expected code
AND EXISTS (SELECT 1 FROM permission.perm_list ppl WHERE ppl.id = 549 and ppl.code = 'COPY_STATUS_LONGOVERDUE.override')
-- don't try to assign perm 549 if already assigned
AND NOT EXISTS (SELECT 1 FROM permission.usr_perm_map pupm2 WHERE pupm2.usr = pupm.usr AND pupm2.perm = 549)
)
INSERT INTO permission.usr_perm_map
(usr, perm, depth, grantable)
SELECT usr, perm, depth, grantable
FROM new_usr_perms;

-- delete any group assignments of the locally-added perm
DELETE FROM permission.grp_perm_map
WHERE perm = (SELECT id FROM permission.perm_list WHERE code = 'COPY_STATUS_LONG_OVERDUE.override' AND id <> 549)
-- short circuit if perm id 549 exists and doesn't have the expected code
AND EXISTS (SELECT 1 FROM permission.perm_list ppl WHERE ppl.id = 549 and ppl.code = 'COPY_STATUS_LONGOVERDUE.override');

-- delete any user assignments of the locally-added perm
DELETE FROM permission.usr_perm_map
WHERE perm = (SELECT id FROM permission.perm_list WHERE code = 'COPY_STATUS_LONG_OVERDUE.override' AND id <> 549)
-- short circuit if perm id 549 exists and doesn't have the expected code
AND EXISTS (SELECT 1 FROM permission.perm_list ppl WHERE ppl.id = 549 and ppl.code = 'COPY_STATUS_LONGOVERDUE.override');

-- delete the locally-added perm, if any
DELETE FROM permission.perm_list
WHERE code = 'COPY_STATUS_LONG_OVERDUE.override'
AND id <> 549
-- short circuit if perm id 549 exists and doesn't have the expected code
AND EXISTS (SELECT 1 FROM permission.perm_list ppl WHERE ppl.id = 549 and ppl.code = 'COPY_STATUS_LONGOVERDUE.override');

-- update perm id 549 to the correct code, if not already
UPDATE permission.perm_list
SET code = 'COPY_STATUS_LONG_OVERDUE.override'
WHERE id = 549
AND code = 'COPY_STATUS_LONGOVERDUE.override';


SELECT evergreen.upgrade_deps_block_check('1039', :eg_version); -- jeffdavis/gmcharlt

UPDATE config.org_unit_setting_type
SET datatype = 'link', fm_class = 'vms'
WHERE name = 'vandelay.default_match_set'
AND   datatype = 'string'
AND   fm_class IS NULL;

\echo Existing vandelay.default_match_set that do not
\echo correspond to match sets
SELECT aou.shortname, aous.value
FROM   actor.org_unit_setting aous
JOIN   actor.org_unit aou ON (aou.id = aous.org_unit)
WHERE  aous.name = 'vandelay.default_match_set'
AND    (
  value !~ '^"[0-9]+"$'
  OR
    oils_json_to_text(aous.value)::INT NOT IN (
      SELECT id FROM vandelay.match_set
    )
);

\echo And now deleting the bad values, as otherwise they
\echo will break the Library Settings Editor.
DELETE
FROM actor.org_unit_setting aous
WHERE  aous.name = 'vandelay.default_match_set'
AND    (
  value !~ '^"[0-9]+"$'
  OR
    oils_json_to_text(aous.value)::INT NOT IN (
      SELECT id FROM vandelay.match_set
    )
);


SELECT evergreen.upgrade_deps_block_check('1040', :eg_version);

CREATE INDEX edi_message_remote_file_idx ON acq.edi_message (evergreen.lowercase(remote_file));

COMMIT;
