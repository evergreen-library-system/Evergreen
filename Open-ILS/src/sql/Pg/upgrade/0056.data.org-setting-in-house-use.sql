BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0056'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'ui.circ.in_house_use.entry_cap',
        'GUI: Record In-House Use: Maximum # of uses allowed per entry.',
        'The # of uses entry in the Record In-House Use interface may not exceed the value of this setting.',
        'integer'
    );

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'ui.circ.in_house_use.entry_warn',
        'GUI: Record In-House Use: # of uses threshold for Are You Sure? dialog.',
        'In the Record In-House Use interface, a submission attempt will warn if the # of uses field exceeds the value of this setting.',
        'integer'
    );

COMMIT;
