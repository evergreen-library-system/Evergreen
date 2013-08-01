BEGIN;

SELECT evergreen.upgrade_deps_block_check('0813', :eg_version);

-- Don't require state in the auditor tracking for user addresses

ALTER TABLE auditor.actor_usr_address_history ALTER COLUMN state DROP NOT NULL;

-- Change constraint on actor.org_unit_setting_log to be deferrable initially

ALTER TABLE config.org_unit_setting_type_log
  DROP CONSTRAINT org_unit_setting_type_log_field_name_fkey,
  ADD CONSTRAINT org_unit_setting_type_log_field_name_fkey FOREIGN KEY (field_name)
    REFERENCES config.org_unit_setting_type (name) MATCH SIMPLE
    ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED;

-- Fix names in the org unit setting configuration

UPDATE config.org_unit_setting_type SET name = overlay(name placing 'aua' from 16 for 2) where name like 'ui.patron.edit.au.state.%';

-- Fix names if they have already been set in the editor

UPDATE actor.org_unit_setting SET name = overlay(name placing 'aua' from 16 for 2) where name like 'ui.patron.edit.au.state.%';

-- and the logs too

UPDATE config.org_unit_setting_type_log SET field_name = overlay(field_name placing 'aua' from 16 for 2) where field_name like 'ui.patron.edit.au.state.%';

COMMIT;
