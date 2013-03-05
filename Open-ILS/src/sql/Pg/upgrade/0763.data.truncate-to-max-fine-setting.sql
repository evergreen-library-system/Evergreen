BEGIN;

SELECT evergreen.upgrade_deps_block_check('0763', :eg_version);

INSERT INTO config.org_unit_setting_type (
    name, label, grp, datatype
) VALUES (
    'circ.fines.truncate_to_max_fine',
    'Truncate fines to max fine amount',
    'circ',
    'bool'
);

COMMIT;

