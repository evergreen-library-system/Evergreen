BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0066');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES ('circ.holds.default_shelf_expire_interval',
            'Default hold shelf expire interval',
            '',
            'interval');

COMMIT;

