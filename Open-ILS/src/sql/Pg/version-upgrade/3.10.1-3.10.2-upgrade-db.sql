--Upgrade Script for 3.10.1 to 3.10.2
\set eg_version '''3.10.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.10.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1362', :eg_version);

CREATE INDEX hold_request_hopeless_date_idx ON action.hold_request (hopeless_date);


ANALYZE action.hold_request;

SELECT evergreen.upgrade_deps_block_check('1365', :eg_version);

CREATE OR REPLACE FUNCTION search.highlight_display_fields_impl(
    rid         BIGINT,
    tsq         TEXT,
    field_list  INT[] DEFAULT '{}'::INT[],
    css_class   TEXT DEFAULT 'oils_SH',
    hl_all      BOOL DEFAULT TRUE,
    minwords    INT DEFAULT 5,
    maxwords    INT DEFAULT 25,
    shortwords  INT DEFAULT 0,
    maxfrags    INT DEFAULT 0,
    delimiter   TEXT DEFAULT ' ... '
) RETURNS SETOF search.highlight_result AS $f$
DECLARE
    opts            TEXT := '';
    v_css_class     TEXT := css_class;
    v_delimiter     TEXT := delimiter;
    v_field_list    INT[] := field_list;
    hl_query        TEXT;
BEGIN
    IF v_delimiter LIKE $$%'%$$ OR v_delimiter LIKE '%"%' THEN --"
        v_delimiter := ' ... ';
    END IF;

    IF NOT hl_all THEN
        opts := opts || 'MinWords=' || minwords;
        opts := opts || ', MaxWords=' || maxwords;
        opts := opts || ', ShortWords=' || shortwords;
        opts := opts || ', MaxFragments=' || maxfrags;
        opts := opts || ', FragmentDelimiter="' || delimiter || '"';
    ELSE
        opts := opts || 'HighlightAll=TRUE';
    END IF;

    IF v_css_class LIKE $$%'%$$ OR v_css_class LIKE '%"%' THEN -- "
        v_css_class := 'oils_SH';
    END IF;

    opts := opts || $$, StopSel=</mark>, StartSel="<mark class='$$ || v_css_class; -- "

    IF v_field_list = '{}'::INT[] THEN
        SELECT ARRAY_AGG(id) INTO v_field_list FROM config.metabib_field WHERE display_field;
    END IF;

    hl_query := $$
        SELECT  de.id,
                de.source,
                de.field,
                evergreen.escape_for_html(de.value) AS value,
                ts_headline(
                    ts_config::REGCONFIG,
                    evergreen.escape_for_html(de.value),
                    $$ || quote_literal(tsq) || $$,
                    $1 || ' ' || mf.field_class || ' ' || mf.name || $xx$'>"$xx$ -- "'
                ) AS highlight
          FROM  metabib.display_entry de
                JOIN config.metabib_field mf ON (mf.id = de.field)
                JOIN search.best_tsconfig t ON (t.id = de.field)
          WHERE de.source = $2
                AND field = ANY ($3)
          ORDER BY de.id;$$;

    RETURN QUERY EXECUTE hl_query USING opts, rid, v_field_list;
END;
$f$ LANGUAGE PLPGSQL;


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


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1377', :eg_version);

-- 950.data.seed-values.sql

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'opac.login_redirect_domains',
    '',
    TRUE,
    oils_i18n_gettext(
        'opac.login_redirect_domains',
        'Restrict post-login redirection to local URLs, or those that match the supplied comma-separated list of foreign domains or host names.',
        'cgf', 'label'
    )
);



SELECT evergreen.upgrade_deps_block_check('1378', :eg_version);

CREATE OR REPLACE FUNCTION search.highlight_display_fields(
    rid         BIGINT,
    tsq_map     TEXT, -- '(a | b) & c' => '1,2,3,4', ...
    css_class   TEXT DEFAULT 'oils_SH',
    hl_all      BOOL DEFAULT TRUE,
    minwords    INT DEFAULT 5,
    maxwords    INT DEFAULT 25,
    shortwords  INT DEFAULT 0,
    maxfrags    INT DEFAULT 0,
    delimiter   TEXT DEFAULT ' ... '
) RETURNS SETOF search.highlight_result AS $f$
DECLARE
    tsq         TEXT;
    fields      TEXT;
    afields     INT[];
    seen        INT[];
BEGIN

    FOR tsq, fields IN SELECT key, value FROM each(tsq_map::HSTORE) LOOP
        SELECT  ARRAY_AGG(unnest::INT) INTO afields
          FROM  unnest(regexp_split_to_array(fields,','));
        seen := seen || afields;

        RETURN QUERY
            SELECT * FROM search.highlight_display_fields_impl(
                rid, tsq, afields, css_class, hl_all,minwords,
                maxwords, shortwords, maxfrags, delimiter
            );
    END LOOP;

    RETURN QUERY
        SELECT  id,
                source,
                field,
                evergreen.escape_for_html(value) AS value,
                evergreen.escape_for_html(value) AS highlight
          FROM  metabib.display_entry
          WHERE source = rid
                AND NOT (field = ANY (seen));
END;
$f$ LANGUAGE PLPGSQL ROWS 10;


COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
