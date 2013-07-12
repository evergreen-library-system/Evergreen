BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0807', :eg_version);

ALTER TABLE config.usr_setting_type
    ADD COLUMN reg_default TEXT;

COMMIT;
