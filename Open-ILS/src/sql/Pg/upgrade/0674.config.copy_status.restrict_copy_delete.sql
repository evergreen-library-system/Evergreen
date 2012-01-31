BEGIN;

SELECT evergreen.upgrade_deps_block_check('0674', :eg_version);

ALTER TABLE config.copy_status
	  ADD COLUMN restrict_copy_delete BOOL NOT NULL DEFAULT FALSE;

UPDATE config.copy_status
SET restrict_copy_delete = TRUE
WHERE id IN (1,3,6,8);

INSERT INTO permission.perm_list (id, code, description) VALUES (
    520,
    'COPY_DELETE_WARNING.override',
    'Allow a user to override warnings about deleting copies in problematic situations.'
);

COMMIT;
