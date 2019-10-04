BEGIN;

SELECT evergreen.upgrade_deps_block_check('1193', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.circ.patron.xact_details_details_bills', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.circ.patron.xact_details_details_bills',
    'Grid Config: circ.patron.xact_details_details_bills',
    'cwst', 'label')
), (
    'eg.grid.circ.patron.xact_details_details_payments', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.circ.patron.xact_details_details_payments',
    'Grid Config: circ.patron.xact_details_details_payments',
    'cwst', 'label')
);

COMMIT;
