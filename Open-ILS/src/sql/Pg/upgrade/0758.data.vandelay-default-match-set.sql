BEGIN;

SELECT evergreen.upgrade_deps_block_check('0758', :eg_version);

INSERT INTO config.settings_group (name, label) VALUES
    ('vandelay', 'Vandelay');

INSERT INTO config.org_unit_setting_type (name, grp, label, datatype, fm_class) VALUES
    ('vandelay.default_match_set', 'vandelay', 'Default Record Match Set', 'link', 'vms');

COMMIT;
