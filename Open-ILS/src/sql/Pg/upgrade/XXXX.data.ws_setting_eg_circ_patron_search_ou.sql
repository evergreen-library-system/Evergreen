BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, label, description, datatype, fm_class)
VALUES (
    'eg.circ.patron.search.ou',
    'circ',
    oils_i18n_gettext(
        'eg.circ.patron.search.ou',
        'Staff Client patron search: home organization unit',
        'cwst', 'label'),
    oils_i18n_gettext(
        'eg.circ.patron.search.ou',
        'Specifies the home organization unit for patron search',
        'cwst', 'description'),
    'link',
    'aou'
    );

COMMIT;
