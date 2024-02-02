--Upgrade Script for 3.11.2 to 3.11.3
\set eg_version '''3.11.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.11.3', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1399', :eg_version);

ALTER TABLE asset.copy_template DROP CONSTRAINT valid_fine_level;
ALTER TABLE asset.copy_template ADD CONSTRAINT valid_fine_level
      CHECK (fine_level IS NULL OR fine_level IN (1,2,3));


SELECT evergreen.upgrade_deps_block_check('1400', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.actor.stat_cat_entry', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.actor.stat_cat_entry',
        'Grid Config: admin.local.actor.stat_cat_entry',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.local.asset.stat_cat_entry', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.asset.stat_cat_entry',
        'Grid Config: admin.local.asset.stat_cat_entry',
        'cwst', 'label'
    )
);

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
