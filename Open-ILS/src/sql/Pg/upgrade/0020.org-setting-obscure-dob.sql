BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0020');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.obscure_dob',
    'Obscure the Date of Birth field',
    'When true, the Date of Birth column in patron lists will default to Not Visible, and in the Patron Summary sidebar the value will display as <Hidden> unless the field label is clicked.',
    'bool'
);

COMMIT;

