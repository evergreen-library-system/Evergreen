BEGIN;

--SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

UPDATE config.org_unit_setting_type
SET grp='holds'
WHERE
name='circ.holds.calculated_age_proximity'
and grp='circ'
;

COMMIT;
