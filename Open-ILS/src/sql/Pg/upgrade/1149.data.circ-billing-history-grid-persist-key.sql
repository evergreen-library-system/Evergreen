BEGIN;

SELECT evergreen.upgrade_deps_block_check('1149', :eg_version); -- Dyrcona/mmorgan/gmcharlt

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
  'eg.grid.circ.patron.billhistory_xacts', 'gui', 'object',
  oils_i18n_gettext(
    'eg.grid.circ.patron.billhistory_xacts',
    'Grid Config: circ.patron.billhistory_xacts',
    'cwst', 'label'
  )
);

COMMIT;
