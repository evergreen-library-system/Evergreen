BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES ('eg.circ.in_house.do_inventory_update', 'circ', 'bool',
    oils_i18n_gettext (
        'eg.circ.in_house.do_inventory_update',
        'In-House Use: Update Inventory',
        'cwst', 'label'
    )
);

COMMIT;
