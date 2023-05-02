
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1370', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES
    (
        'eg.orgselect.admin.stat_cat.owner', 'gui', 'integer',
        oils_i18n_gettext(
            'eg.orgselect.admin.stat_cat.owner',
            'Default org unit for stat cat and stat cat entry editors',
            'cwst', 'label'
        )
    ), (
        'eg.orgfamilyselect.admin.item_stat_cat.main_org_selector', 'gui', 'integer',
        oils_i18n_gettext(
            'eg.orgfamilyselect.admin.item_stat_cat.main_org_selector',
            'Default org unit for the main org select in the item stat cat and stat cat entry admin interfaces.',
            'cwst', 'label'
        )
    ), (
        'eg.orgfamilyselect.admin.patron_stat_cat.main_org_selector', 'gui', 'integer',
        oils_i18n_gettext(
            'eg.orgfamilyselect.admin.patron_stat_cat.main_org_selector',
            'Default org unit for the main org select in the patron stat cat and stat cat entry admin interfaces.',
            'cwst', 'label'
        )
    );

COMMIT;
