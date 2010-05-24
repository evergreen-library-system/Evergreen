BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0275'); -- miker

CREATE TABLE config.settings_group (
  name     text primary key,
  label    text not null unique
);
 
ALTER TABLE config.org_unit_setting_type
  ADD COLUMN grp TEXT REFERENCES config.settings_group (name);
 
ALTER TABLE config.usr_setting_type
  ADD COLUMN grp TEXT REFERENCES config.settings_group (name);

COMMIT;

