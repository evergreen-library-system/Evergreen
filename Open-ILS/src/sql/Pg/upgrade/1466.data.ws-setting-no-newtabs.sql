BEGIN;

SELECT evergreen.upgrade_deps_block_check('1466', :eg_version);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'ui.staff.disable_links_newtabs',
    'gui',
    oils_i18n_gettext('ui.staff.disable_links_newtabs',
        'Staff Client: no new tabs',
        'coust', 'label'),
    oils_i18n_gettext('ui.staff.disable_links_newtabs',
        'Prevents links in the staff interface from opening in new tabs or windows.',
        'coust', 'description'),
    'bool'
);

COMMIT;
