BEGIN;

SELECT evergreen.upgrade_deps_block_check('1164', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.circ.patron.group_members', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.circ.patron.group_members',
    'Grid Config: circ.patron.group_members',
    'cwst', 'label')
);

COMMIT;
