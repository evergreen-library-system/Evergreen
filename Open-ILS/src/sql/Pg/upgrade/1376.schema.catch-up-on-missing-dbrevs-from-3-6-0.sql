BEGIN;

SELECT evergreen.upgrade_deps_block_check('1376', :eg_version);

-- 1236

CREATE OR REPLACE VIEW action.all_circulation_combined_types AS
 SELECT acirc.id AS id,
    acirc.xact_start,
    acirc.circ_lib,
    acirc.circ_staff,
    acirc.create_time,
    ac_acirc.circ_modifier AS item_type,
    'regular_circ'::text AS circ_type
   FROM action.circulation acirc,
    asset.copy ac_acirc
  WHERE acirc.target_copy = ac_acirc.id
UNION ALL
 SELECT ancc.id::BIGINT AS id,
    ancc.circ_time AS xact_start,
    ancc.circ_lib,
    ancc.staff AS circ_staff,
    ancc.circ_time AS create_time,
    cnct_ancc.name AS item_type,
    'non-cat_circ'::text AS circ_type
   FROM action.non_cataloged_circulation ancc,
    config.non_cataloged_type cnct_ancc
  WHERE ancc.item_type = cnct_ancc.id
UNION ALL
 SELECT aihu.id::BIGINT AS id,
    aihu.use_time AS xact_start,
    aihu.org_unit AS circ_lib,
    aihu.staff AS circ_staff,
    aihu.use_time AS create_time,
    ac_aihu.circ_modifier AS item_type,
    'in-house_use'::text AS circ_type
   FROM action.in_house_use aihu,
    asset.copy ac_aihu
  WHERE aihu.item = ac_aihu.id
UNION ALL
 SELECT ancihu.id::BIGINT AS id,
    ancihu.use_time AS xact_start,
    ancihu.org_unit AS circ_lib,
    ancihu.staff AS circ_staff,
    ancihu.use_time AS create_time,
    cnct_ancihu.name AS item_type,
    'non-cat-in-house_use'::text AS circ_type
   FROM action.non_cat_in_house_use ancihu,
    config.non_cataloged_type cnct_ancihu
  WHERE ancihu.item_type = cnct_ancihu.id
UNION ALL
 SELECT aacirc.id AS id,
    aacirc.xact_start,
    aacirc.circ_lib,
    aacirc.circ_staff,
    aacirc.create_time,
    ac_aacirc.circ_modifier AS item_type,
    'aged_circ'::text AS circ_type
   FROM action.aged_circulation aacirc,
    asset.copy ac_aacirc
  WHERE aacirc.target_copy = ac_aacirc.id;

-- 1237

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
SELECT
    'eg.staffcat.exclude_electronic', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.staffcat.exclude_electronic',
        'Staff Catalog "Exclude Electronic Resources" Option',
        'cwst', 'label'
    )
WHERE NOT EXISTS (
    SELECT 1
    FROM config.workstation_setting_type
    WHERE name = 'eg.staffcat.exclude_electronic'
);

-- 1238

INSERT INTO permission.perm_list ( id, code, description ) SELECT
 625, 'VIEW_BOOKING_RESERVATION', oils_i18n_gettext(625,
    'View booking reservations', 'ppl', 'description')
WHERE NOT EXISTS (
    SELECT 1
    FROM permission.perm_list
    WHERE id = 625
    AND   code = 'VIEW_BOOKING_RESERVATION'
);

INSERT INTO permission.perm_list ( id, code, description ) SELECT
 626, 'VIEW_BOOKING_RESERVATION_ATTR_MAP', oils_i18n_gettext(626,
    'View booking reservation attribute maps', 'ppl', 'description')
WHERE NOT EXISTS (
    SELECT 1
    FROM permission.perm_list
    WHERE id = 626
    AND   code = 'VIEW_BOOKING_RESERVATION_ATTR_MAP'
);

-- reprise 1269 just in case now that the perms should definitely exist

WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('VIEW_BOOKING_RESERVATION', 'VIEW_BOOKING_RESERVATION_ATTR_MAP'))

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map
        
        --- Don't add the permissions if they have already been assigned
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)
            
        --- Anybody who can view resources should also see reservations
        --- at the same level
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'VIEW_BOOKING_RESOURCE'
        );

-- 1239

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
SELECT
    'eg.grid.booking.pull_list', 'gui', 'object',
    oils_i18n_gettext(
        'booking.pull_list',
        'Grid Config: Booking Pull List',
        'cwst', 'label')
WHERE NOT EXISTS (
    SELECT 1
    FROM config.workstation_setting_type
    WHERE name = 'eg.grid.booking.pull_list'
);

-- 1240

INSERT INTO action_trigger.event_params (event_def, param, value)
SELECT id, 'check_sms_notify', 1
FROM action_trigger.event_definition
WHERE reactor = 'SendSMS'
AND validator IN ('HoldIsAvailable', 'HoldIsCancelled', 'HoldNotifyCheck')
AND NOT EXISTS (
    SELECT * FROM action_trigger.event_params
    WHERE param = 'check_sms_notify'
);

-- fill in the gaps, but only if the upgrade log indicates that
-- this database had been at version 3.6.0 at some point.
INSERT INTO config.upgrade_log (version, applied_to) SELECT '1236', :eg_version
WHERE NOT EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '1236')
AND       EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '3.6.0');
INSERT INTO config.upgrade_log (version, applied_to) SELECT '1237', :eg_version
WHERE NOT EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '1237')
AND       EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '3.6.0');
INSERT INTO config.upgrade_log (version, applied_to) SELECT '1238', :eg_version
WHERE NOT EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '1238')
AND       EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '3.6.0');
INSERT INTO config.upgrade_log (version, applied_to) SELECT '1239', :eg_version
WHERE NOT EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '1239')
AND       EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '3.6.0');
INSERT INTO config.upgrade_log (version, applied_to) SELECT '1240', :eg_version
WHERE NOT EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '1240')
AND       EXISTS (SELECT 1 FROM config.upgrade_log WHERE version = '3.6.0');

COMMIT;
