--Upgrade Script for 3.6.1 to 3.6.2
\set eg_version '''3.6.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.6.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1243', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, fm_class, label)
VALUES (
    'eg.orgselect.catalog.holdings', 'gui', 'link', 'aou',
    oils_i18n_gettext(
        'eg.orgselect.catalog.holdings',
        'Default org unit for catalog holdings tab',
        'cwst', 'label'
    )
);




SELECT evergreen.upgrade_deps_block_check('1244', :eg_version);

-- In some cases, asset.copy_tag_copy_map might have an inh_fkey()
-- trigger that fires on delete when it's not supposed to. This
-- update drops all inh_fkey triggers on that table and recreates
-- the known good version.
DROP TRIGGER IF EXISTS inherit_asset_copy_tag_copy_map_copy_fkey ON asset.copy_tag_copy_map;
DROP TRIGGER IF EXISTS inherit_copy_tag_copy_map_copy_fkey ON asset.copy_tag_copy_map;

CREATE CONSTRAINT TRIGGER inherit_asset_copy_tag_copy_map_copy_fkey
        AFTER UPDATE OR INSERT ON asset.copy_tag_copy_map
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_tag_copy_map_copy_inh_fkey();


SELECT evergreen.upgrade_deps_block_check('1245', :eg_version);

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'auth.block_expired_staff_login',
    NULL,
    FALSE,
    oils_i18n_gettext(
        'auth.block_expired_staff_login',
        'Block the ability of expired user with the STAFF_LOGIN permission to log into Evergreen.',
        'cgf', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1246', :eg_version);

CREATE OR REPLACE VIEW money.open_with_balance_usr_summary AS
    SELECT
        usr,
        sum(total_paid) AS total_paid,
        sum(total_owed) AS total_owed,
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    WHERE xact_finish IS NULL AND balance_owed <> 0.0
    GROUP BY usr;

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
