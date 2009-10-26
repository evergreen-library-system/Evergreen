BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0055'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'circ.auto_hide_patron_summary',
        'GUI: Toggle off the patron summary sidebar after first view.',
        'When true, the patron summary sidebar will collapse after a new patron sub-interface is selected.',
        'bool'
    );

COMMIT;
