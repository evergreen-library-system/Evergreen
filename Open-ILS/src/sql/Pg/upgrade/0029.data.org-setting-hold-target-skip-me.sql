BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0029');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.holds.target_skip_me',
    'Skip For Hold Targeting',
    'When true, don''t target any copies at this org unit for holds',
    'bool'
);

COMMIT;

