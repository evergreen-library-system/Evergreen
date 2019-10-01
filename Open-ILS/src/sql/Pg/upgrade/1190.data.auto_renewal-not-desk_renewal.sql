BEGIN;

SELECT evergreen.upgrade_deps_block_check('1190', :eg_version);

UPDATE action.circulation SET desk_renewal = FALSE WHERE auto_renewal IS TRUE;

UPDATE action.aged_circulation SET desk_renewal = FALSE WHERE auto_renewal IS TRUE;

COMMIT;
