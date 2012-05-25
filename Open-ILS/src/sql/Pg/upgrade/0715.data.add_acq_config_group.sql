BEGIN;

SELECT evergreen.upgrade_deps_block_check('0715', :eg_version);

INSERT INTO config.settings_group (name, label) VALUES
('acq', oils_i18n_gettext('config.settings_group.system', 'Acquisitions', 'coust', 'label'));

UPDATE config.org_unit_setting_type
    SET grp = 'acq'
    WHERE name LIKE 'acq%';

COMMIT;
