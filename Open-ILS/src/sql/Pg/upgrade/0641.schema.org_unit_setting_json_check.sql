-- Evergreen DB patch 0641.schema.org_unit_setting_json_check.sql
--
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0641', :eg_version);

ALTER TABLE actor.org_unit_setting ADD CONSTRAINT aous_must_be_json CHECK ( evergreen.is_json(value) );

COMMIT;
