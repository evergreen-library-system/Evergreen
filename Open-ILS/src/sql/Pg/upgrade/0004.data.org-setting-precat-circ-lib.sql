BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0004');

INSERT INTO config.org_unit_setting_type (name, label, description, datatype) VALUES (
    'circ.pre_cat_copy_circ_lib',
    'Pre-cat Item Circ Lib',
    'Override the default circ lib of "here" with a pre-configured circ lib for pre-cat items.  The value should be the "shortname" (aka policy name) of the org unit',
    'string'
);

COMMIT;

