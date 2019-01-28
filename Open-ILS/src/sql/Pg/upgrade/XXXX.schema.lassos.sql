BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- XXX Committer: confirm ID below is the next available!
INSERT INTO permission.perm_list (id, code, description)
    VALUES ( 629, 'ADMIN_LIBRARY_GROUPS', 'Administer library groups');

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.server.actor.org_lasso', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.actor.org_lasso',
        'Grid Config: admin.server.actor.org_lasso',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.actor.org_lasso_map', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.actor.org_lasso_map',
        'Grid Config: admin.server.actor.org_lasso_map',
        'cwst', 'label'
    )
);

ALTER TABLE actor.org_lasso ADD COLUMN global BOOL NOT NULL DEFAULT FALSE;

COMMIT;

