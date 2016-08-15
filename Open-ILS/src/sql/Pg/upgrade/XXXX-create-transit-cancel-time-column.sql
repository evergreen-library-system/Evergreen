BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE action.transit_copy
	ADD COLUMN cancel_time TIMESTAMPTZ;

-- change "abort" to "cancel" in perm descriptions
UPDATE permission.perm_list SET description = 'Allow a user to cancel a copy transit if the user is at the transit destination or source' WHERE code = 'ABORT_TRANSIT';
UPDATE permission.perm_list SET description = 'Allow a user to cancel a copy transit if the user is not at the transit source or dest' WHERE code = 'ABORT_REMOTE_TRANSIT'; 
UPDATE permission.perm_list SET description = 'Allows a user to cancel a transit on a copy with status of LOST' WHERE code = 'ABORT_TRANSIT_ON_LOST';
UPDATE permission.perm_list SET description = 'Allows a user to cancel a transit on a copy with status of MISSING' WHERE code = 'ABORT_TRANSIT_ON_MISSING';

COMMIT;
