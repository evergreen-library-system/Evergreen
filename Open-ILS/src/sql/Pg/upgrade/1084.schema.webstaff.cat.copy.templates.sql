BEGIN;

SELECT evergreen.upgrade_deps_block_check('1084', :eg_version);

INSERT INTO config.usr_setting_type (name, label, description, datatype)
  VALUES ('webstaff.cat.copy.templates', 'Web Client Copy Editor Templates', 'Web Client Copy Editor Templates', 'object');

COMMIT;
