--Upgrade Script for 3.14.4 to 3.15-beta
\set eg_version '''3.15-beta'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.15-beta', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1450', :eg_version);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'eg.admin.keyboard_shortcuts.disable_single',
    'gui',
    oils_i18n_gettext('eg.admin.keyboard_shortcuts.disable_single',
        'Staff Client: disable single-letter keyboard shortcuts',
        'coust', 'label'),
    oils_i18n_gettext('eg.admin.keyboard_shortcuts.disable_single',
        'Disables single-letter keyboard shortcuts if set to true. Screen reader users should set this to true to avoid interference with standard keyboard shortcuts.',
        'coust', 'description'),
    'bool'
);


SELECT evergreen.upgrade_deps_block_check('1452', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype)
VALUES (
    'ui.staff.place_holds_for_recent_patrons',
    oils_i18n_gettext(
        'ui.staff.place_holds_for_recent_patrons',
        'Place holds for recent patrons',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.staff.place_holds_for_recent_patrons',
        'Loading a patron in the place holds interface designates them as recent. ' ||
        'Show the interface to load recent patrons when placing holds.',
        'coust',
        'description'
    ),
    'gui',
    'bool'
);


SELECT evergreen.upgrade_deps_block_check('1453', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
   676,
   'UPDATE_TOP_OF_QUEUE',
   oils_i18n_gettext(676,
     'Allow setting and unsetting hold from top of hold queue (cut in line)', 'ppl', 'description'
   )
   FROM permission.perm_list
   WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'UPDATE_TOP_OF_QUEUE');


--Assign permission to any perm groups with UPDATE_HOLD_REQUEST_TIME
WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('UPDATE_TOP_OF_QUEUE'))
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map

        --- Don't add the permissions if they have already been assigned
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)

        --- we're going to match the depth of their existing perm
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'UPDATE_HOLD_REQUEST_TIME'
        );

-- Add missing FROM clause entry to asset.opac_lasso_record_copy_count


SELECT evergreen.upgrade_deps_block_check('1455', :eg_version);

CREATE OR REPLACE FUNCTION asset.opac_lasso_record_copy_count (i_lasso INT, rid BIGINT) RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT) AS $f$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.org_unit AS id FROM actor.org_lasso_map AS u WHERE lasso = i_lasso LOOP
        RETURN QUERY
        WITH org_list AS (SELECT ARRAY_AGG(id)::BIGINT[] AS orgs FROM actor.org_unit_descendants(ans.id) x),
             available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
             mask AS (SELECT c_attrs FROM asset.patron_default_visibility_mask() x)
        SELECT  -1,
                ans.id,
                COUNT( av.id ),
                SUM( (cp.status = ANY (available_statuses.ids))::INT ),
                COUNT( av.id ),
                trans
          FROM  mask,
                org_list,
                available_statuses,
                asset.copy_vis_attr_cache av
                JOIN asset.copy cp ON (cp.id = av.target_copy AND av.record = rid)
          WHERE cp.circ_lib = ANY (org_list.orgs) AND av.vis_attr_vector @@ mask.c_attrs::query_int
          GROUP BY 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT -1, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('1456', :eg_version);

INSERT into config.workstation_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'ui.staff.grid.density',
    'gui',
    oils_i18n_gettext('ui.staff.grid.density',
        'Grid UI density',
        'coust', 'label'),
    oils_i18n_gettext('ui.staff.grid.density',
        'Whitespace around table cells in staff UI data grids. Default is "standard".',
        'coust', 'description'),
    'string'
);


-- Move OPAC alert banner feature from config file to a library setting

SELECT evergreen.upgrade_deps_block_check('1458', :eg_version);

INSERT into config.org_unit_setting_type
         (name, grp, label, description, datatype)
VALUES (
         'opac.alert_banner_show',
         'opac',
         oils_i18n_gettext('opac.alert_banner_show',
         'OPAC Alert Banner: Display',
         'coust', 'label'),
         oils_i18n_gettext('opac.alert_message_show',
         'Show an alert banner in the OPAC. Default is false.',
         'coust', 'description'),
         'bool'
);

INSERT into config.org_unit_setting_type
         (name, grp, label, description, datatype)
VALUES (
         'opac.alert_banner_type',
         'opac',
         oils_i18n_gettext('opac.alert_banner_type',
         'OPAC Alert Banner: Type',
         'coust', 'label'),
         oils_i18n_gettext('opac.alert_message_type',
         'Determine the display of the banner. Options are: success, info, warning, danger.',
         'coust', 'description'),
         'string'
);

INSERT into config.org_unit_setting_type
         (name, grp, label, description, datatype)
VALUES (
         'opac.alert_banner_text',
         'opac',
         oils_i18n_gettext('opac.alert_banner_text',
         'OPAC Alert Banner: Text',
         'coust', 'label'),
         oils_i18n_gettext('opac.alert_message_text',
         'Text that will display in the alert banner.',
         'coust', 'description'),
         'string'
);


-- Move Google Analytics settings from config.tt2 to library settings

SELECT evergreen.upgrade_deps_block_check('1459', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'opac.google_analytics_enable',
    'opac',
    oils_i18n_gettext('opac.google_analytics_enable',
    'Google Analytics: Enable',
    'coust', 'label'),
    oils_i18n_gettext('opac.alert_message_show',
    'Enable Google Analytics in the OPAC. Default is false.',
    'coust', 'description'),
    'bool'
);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
VALUES (
    'opac.google_analytics_code',
    'opac',
    oils_i18n_gettext('opac.google_analytics_code',
    'Google Analytics: Code',
    'coust', 'label'),
    oils_i18n_gettext('opac.google_analytics_code',
    'Account code provided by Google. (Example: G-GVGQ11X12)',
    'coust', 'description'),
    'string'
);


SELECT evergreen.upgrade_deps_block_check('1460', :eg_version); -- JBoyer

-- Note: the value will not be consistent from system to system. It's an opaque key that has no meaning of its own,
-- if the value cached in the client does not match or is missing, it clears some cached values and then saves the current value.
INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'staff.client_cache_key',
    oils_i18n_gettext(
        'staff.client_cache_key',
        'Change this value to force staff clients to clear some cached values',
        'cgf',
        'label'
    ),
    md5(random()::text),
    TRUE
);


SELECT evergreen.upgrade_deps_block_check('1461', :eg_version);

-- for searching e.g. "111-111-1111"
CREATE INDEX actor_usr_setting_phone_values_idx
    ON actor.usr_setting (evergreen.lowercase(value))
    WHERE name IN ('opac.default_phone', 'opac.default_sms_notify');

-- for searching e.g. "1111111111"
CREATE INDEX actor_usr_setting_phone_values_numeric_idx
    ON actor.usr_setting (evergreen.lowercase(REGEXP_REPLACE(value, '[^0-9]', '', 'g')))
    WHERE name IN ('opac.default_phone', 'opac.default_sms_notify');


SELECT evergreen.upgrade_deps_block_check('1462', :eg_version);

INSERT INTO acq.edi_attr (key, label) VALUES
    ('LINEITEM_SEQUENTIAL_ID',
        oils_i18n_gettext('LINEITEM_SEQUENTIAL_ID',
        'Lineitems Are Enumerated Sequentially', 'aea', 'label'));


SELECT evergreen.upgrade_deps_block_check('1463', :eg_version);

INSERT INTO config.org_unit_setting_type
    (grp, name, datatype, label, description)
VALUES (
    'gui',
    'ui.cat.volume_copy_editor.template_bar.show_save_template', 'bool',
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.template_bar.show_save_template',
        'Show "Save Template" in Holdings Editor',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.template_bar.show_save_template',
        'Displays the "Save Template" button for the template bar in the Volume/Copy/Holdings Editor. By default, this is only displayed when working with templates from the Admin interface.',
        'coust',
        'description'
    )
);

INSERT INTO config.org_unit_setting_type
    (grp, name, datatype, label, description)
VALUES (
    'gui',
    'ui.cat.volume_copy_editor.hide_template_bar', 'bool',
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.hide_template_bar',
        'Hide the entire template bar in Holdings Editor',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.cat.volume_copy_editor.hide_template_bar',
        'Hides the template bar in the Volume/Copy/Holdings Editor. By default, the template bar is displayed in this interface.',
        'coust',
        'description'
    )
);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.volcopy.template_grid', 'gui', 'object', 
    oils_i18n_gettext(
        'eg.grid.cat.volcopy.template_grid',
        'Holdings Template Grid Settings',
        'cwst', 'label'
    )
);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.holdings.copy_tags.tag_map_list', 'gui', 'object', 
    oils_i18n_gettext(
        'eg.grid.holdings.copy_tags.tag_map_list',
        'Copy Tag Maps Template Grid Settings',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1464', :eg_version);

-- If you want to know how many items are available in a particular library group,
-- you can't easily sum the results of, say, asset.staff_lasso_record_copy_count,
-- since library groups can theoretically include descendants of other org units
-- in the library group (for example, the group could include a system and a branch
-- within that same system), which means that certain items would be counted twice.
-- The following functions address that problem by providing deduplicated sums that
-- only count each item once.

CREATE OR REPLACE FUNCTION asset.staff_lasso_record_copy_count_sum(lasso_id INT, record_id BIGINT)
    RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT, library_group INT) AS $$
    BEGIN
    IF (lasso_id IS NULL) THEN RETURN; END IF;
    IF (record_id IS NULL) THEN RETURN; END IF;
    RETURN QUERY SELECT
        -1,
        -1,
        COUNT(cp.id),
        SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available) THEN 1 ELSE 0 END ),
        SUM( CASE WHEN cl.opac_visible AND cp.opac_visible THEN 1 ELSE 0 END),
        0,
        lasso_id
    FROM ( SELECT DISTINCT descendants.id FROM actor.org_lasso_map aolmp JOIN LATERAL actor.org_unit_descendants(aolmp.org_unit) AS descendants ON TRUE WHERE aolmp.lasso = lasso_id) d
        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
        JOIN asset.call_number cn ON (cn.record = record_id AND cn.id = cp.call_number AND NOT cn.deleted);
    END;
$$ LANGUAGE PLPGSQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION asset.opac_lasso_record_copy_count_sum(lasso_id INT, record_id BIGINT)
    RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT, library_group INT) AS $$
    BEGIN
    IF (lasso_id IS NULL) THEN RETURN; END IF;
    IF (record_id IS NULL) THEN RETURN; END IF;

    RETURN QUERY SELECT
        -1,
        -1,
        COUNT(cp.id),
        SUM( CASE WHEN cp.status IN (SELECT id FROM config.copy_status WHERE holdable AND is_available) THEN 1 ELSE 0 END ),
        SUM( CASE WHEN cl.opac_visible AND cp.opac_visible THEN 1 ELSE 0 END),
        0,
        lasso_id
    FROM ( SELECT DISTINCT descendants.id FROM actor.org_lasso_map aolmp JOIN LATERAL actor.org_unit_descendants(aolmp.org_unit) AS descendants ON TRUE WHERE aolmp.lasso = lasso_id) d
        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
        JOIN asset.call_number cn ON (cn.record = record_id AND cn.id = cp.call_number AND NOT cn.deleted)
        JOIN asset.copy_vis_attr_cache av ON (cp.id = av.target_copy AND av.record = record_id)
        JOIN LATERAL (SELECT c_attrs FROM asset.patron_default_visibility_mask()) AS mask ON TRUE
        WHERE av.vis_attr_vector @@ mask.c_attrs::query_int;
    END;
$$ LANGUAGE PLPGSQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION asset.staff_lasso_metarecord_copy_count_sum(lasso_id INT, metarecord_id BIGINT)
    RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT, library_group INT) AS $$
    SELECT (
        -1,
        -1,
        SUM(sums.visible)::bigint,
        SUM(sums.available)::bigint,
        SUM(sums.unshadow)::bigint,
        MIN(sums.transcendant),
        lasso_id
    ) FROM metabib.metarecord_source_map mmsm
      JOIN LATERAL (SELECT visible, available, unshadow, transcendant FROM asset.staff_lasso_record_copy_count_sum(lasso_id, mmsm.source)) sums ON TRUE
      WHERE mmsm.metarecord = metarecord_id;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION asset.opac_lasso_metarecord_copy_count_sum(lasso_id INT, metarecord_id BIGINT)
    RETURNS TABLE (depth INT, org_unit INT, visible BIGINT, available BIGINT, unshadow BIGINT, transcendant INT, library_group INT) AS $$
    SELECT (
        -1,
        -1,
        SUM(sums.visible)::bigint,
        SUM(sums.available)::bigint,
        SUM(sums.unshadow)::bigint,
        MIN(sums.transcendant),
        lasso_id
    ) FROM metabib.metarecord_source_map mmsm
      JOIN LATERAL (SELECT visible, available, unshadow, transcendant FROM asset.opac_lasso_record_copy_count_sum(lasso_id, mmsm.source)) sums ON TRUE
      WHERE mmsm.metarecord = metarecord_id;
$$ LANGUAGE SQL STABLE ROWS 1;


CREATE OR REPLACE FUNCTION asset.copy_org_ids(org_units INT[], depth INT, library_groups INT[])
RETURNS TABLE (id INT)
AS $$
DECLARE
    ancestor INT;
BEGIN
    RETURN QUERY SELECT org_unit FROM actor.org_lasso_map WHERE lasso = ANY(library_groups);
    FOR ancestor IN SELECT unnest(org_units)
    LOOP
        RETURN QUERY
        SELECT d.id
        FROM actor.org_unit_descendants(ancestor, depth) d;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION asset.staff_copy_total(rec_id INT, org_units INT[], depth INT, library_groups INT[])
RETURNS INT AS $$
  SELECT COUNT(cp.id) total
  	FROM asset.copy cp
  	INNER JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted AND cn.record = rec_id)
  	INNER JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
  	WHERE cp.circ_lib = ANY (SELECT asset.copy_org_ids(org_units, depth, library_groups))
  	AND NOT cp.deleted;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION asset.opac_copy_total(rec_id INT, org_units INT[], depth INT, library_groups INT[])
RETURNS INT AS $$
  SELECT COUNT(cp.id) total
  	FROM asset.copy cp
  	INNER JOIN asset.call_number cn ON (cn.id = cp.call_number AND NOT cn.deleted AND cn.record = rec_id)
  	INNER JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
    INNER JOIN asset.copy_vis_attr_cache av ON (cp.id = av.target_copy AND av.record = rec_id)
    JOIN LATERAL (SELECT c_attrs FROM asset.patron_default_visibility_mask()) AS mask ON TRUE
    WHERE av.vis_attr_vector @@ mask.c_attrs::query_int
  	AND cp.circ_lib = ANY (SELECT asset.copy_org_ids(org_units, depth, library_groups))
  	AND NOT cp.deleted;
$$ LANGUAGE SQL;

-- We are adding another argument, which means that we must delete functions with the old signature
DROP FUNCTION IF EXISTS unapi.holdings_xml(
    bid BIGINT,
    ouid INT,
    org TEXT,
    depth INT,
    includes TEXT[],
    slimit HSTORE,
    soffset HSTORE,
    include_xmlns BOOL,
    pref_lib INT);

CREATE OR REPLACE FUNCTION unapi.holdings_xml (
    bid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL,
    library_group INT DEFAULT NULL
)
RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('bre' = ANY ($5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id,
                    (SELECT record_has_holdable_copy FROM asset.record_has_holdable_copy($1)) AS has_holdable
                 ),
                 XMLELEMENT(
                     name counts,
                     (SELECT  XMLAGG(XMLELEMENT::XML) FROM (
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($2,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_ou_record_copy_count($2, $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('pref_lib' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_record_copy_count($9,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, library_group, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_lasso_record_copy_count_sum(library_group,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, library_group, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_lasso_record_copy_count_sum(library_group,  $1)
                                     ORDER BY 1
                     )x)
                 ),
                 CASE 
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT(
                            name monograph_parts,
                            (SELECT XMLAGG(bmp) FROM (
                                SELECT  unapi.bmp( id, 'xml', 'monograph_part', array_remove( array_remove($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE)
                                  FROM  biblio.monograph_part
                                  WHERE NOT deleted AND record = $1
                            )x)
                        )
                     ELSE NULL
                 END,
                 XMLELEMENT(
                     name volumes,
                     (SELECT XMLAGG(acn ORDER BY rank, name, label_sortkey) FROM (
                        -- Physical copies
                        SELECT  unapi.acn(y.id,'xml','volume',array_remove( array_remove($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), y.rank, name, label_sortkey
                        FROM evergreen.ranked_volumes($1, $2, $4, $6, $7, $9, $5) AS y
                        UNION ALL
                        -- Located URIs
                        SELECT unapi.acn(uris.id,'xml','volume',array_remove( array_remove($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), uris.rank, name, label_sortkey
                        FROM evergreen.located_uris($1, $2, $9) AS uris
                     )x)
                 ),
                 CASE WHEN ('ssub' = ANY ($5)) THEN 
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry = $1
                        )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('acp' = ANY ($5)) THEN 
                     XMLELEMENT(
                         name foreign_copies,
                         (SELECT XMLAGG(acp) FROM (
                            SELECT  unapi.acp(p.target_copy,'xml','copy',array_remove($5,'acp'), $3, $4, $6, $7, FALSE)
                              FROM  biblio.peer_bib_copy_map p
                                    JOIN asset.copy c ON (p.target_copy = c.id)
                              WHERE NOT c.deleted AND p.peer_record = $1
                            LIMIT ($6 -> 'acp')::INT
                            OFFSET ($7 -> 'acp')::INT
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL STABLE;

DROP FUNCTION IF EXISTS unapi.bre (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT,
    slimit HSTORE,
    soffset HSTORE,
    include_xmlns BOOL,
    pref_lib INT);

CREATE OR REPLACE FUNCTION unapi.bre (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL,
    library_group INT DEFAULT NULL
)
RETURNS XML AS $F$
DECLARE
    me      biblio.record_entry%ROWTYPE;
    layout  unapi.bre_output_layout%ROWTYPE;
    xfrm    config.xml_transform%ROWTYPE;
    ouid    INT;
    tmp_xml TEXT;
    top_el  TEXT;
    output  XML;
    hxml    XML;
    axml    XML;
    source  XML;
BEGIN

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;

    IF ouid IS NULL THEN
        RETURN NULL::XML;
    END IF;

    IF format = 'holdings_xml' THEN -- the special case
        output := unapi.holdings_xml( obj_id, ouid, org, depth, includes, slimit, soffset, include_xmlns, NULL, library_group);
        RETURN output;
    END IF;

    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO xfrm FROM config.xml_transform WHERE name = layout.transform;

    SELECT * INTO me FROM biblio.record_entry WHERE id = obj_id;

    -- grab bib_source, if any
    IF ('cbs' = ANY (includes) AND me.source IS NOT NULL) THEN
        source := unapi.cbs(me.source,NULL,NULL,NULL,NULL);
    ELSE
        source := NULL::XML;
    END IF;

    -- grab SVF if we need them
    IF ('mra' = ANY (includes)) THEN 
        axml := unapi.mra(obj_id,NULL,NULL,NULL,NULL);
    ELSE
        axml := NULL::XML;
    END IF;

    -- grab holdings if we need them
    IF ('holdings_xml' = ANY (includes)) THEN 
        hxml := unapi.holdings_xml(obj_id, ouid, org, depth, array_remove(includes,'holdings_xml'), slimit, soffset, include_xmlns, pref_lib, library_group);
    ELSE
        hxml := NULL::XML;
    END IF;


    -- generate our item node


    IF format = 'marcxml' THEN
        tmp_xml := me.marc;
        IF tmp_xml !~ E'<marc:' THEN -- If we're not using the prefixed namespace in this record, then remove all declarations of it
           tmp_xml := REGEXP_REPLACE(tmp_xml, ' xmlns:marc="http://www.loc.gov/MARC21/slim"', '', 'g');
        END IF; 
    ELSE
        tmp_xml := oils_xslt_process(me.marc, xfrm.xslt)::XML;
    END IF;

    top_el := REGEXP_REPLACE(tmp_xml, E'^.*?<((?:\\S+:)?' || layout.holdings_element || ').*$', E'\\1');

    IF source IS NOT NULL THEN
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', source || '</' || top_el || E'>\\1');
    END IF;

    IF axml IS NOT NULL THEN 
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', axml || '</' || top_el || E'>\\1');
    END IF;

    IF hxml IS NOT NULL THEN -- XXX how do we configure the holdings position?
        tmp_xml := REGEXP_REPLACE(tmp_xml, '</' || top_el || '>(.*?)$', hxml || '</' || top_el || E'>\\1');
    END IF;

    IF ('bre.unapi' = ANY (includes)) THEN 
        output := REGEXP_REPLACE(
            tmp_xml,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name abbr,
                XMLATTRIBUTES(
                    'http://www.w3.org/1999/xhtml' AS xmlns,
                    'unapi-id' AS class,
                    'tag:open-ils.org:U2@bre/' || obj_id || '/' || org AS title
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := tmp_xml;
    END IF;

    IF ('bre.extern' = ANY (includes)) THEN 
        output := REGEXP_REPLACE(
            tmp_xml,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name extern,
                XMLATTRIBUTES(
                    'http://open-ils.org/spec/biblio/v1' AS xmlns,
                    me.creator AS creator,
                    me.editor AS editor,
                    me.create_date AS create_date,
                    me.edit_date AS edit_date,
                    me.quality AS quality,
                    me.fingerprint AS fingerprint,
                    me.tcn_source AS tcn_source,
                    me.tcn_value AS tcn_value,
                    me.owner AS owner,
                    me.share_depth AS share_depth,
                    me.active AS active,
                    me.deleted AS deleted
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := tmp_xml;
    END IF;

    output := REGEXP_REPLACE(output::TEXT,E'>\\s+<','><','gs')::XML;
    RETURN output;
END;
$F$ LANGUAGE PLPGSQL STABLE;

DROP FUNCTION IF EXISTS unapi.biblio_record_entry_feed (
    id_list BIGINT[],
    format TEXT,
    includes TEXT[],
    org TEXT,
    depth INT,
    slimit HSTORE,
    soffset HSTORE,
    include_xmlns BOOL,
    title TEXT,
    description TEXT,
    creator TEXT,
    update_ts TEXT,
    unapi_url TEXT,
    header_xml XML,
    pref_lib INT);
CREATE OR REPLACE FUNCTION unapi.biblio_record_entry_feed (
    id_list BIGINT[],
    format TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL, 
    include_xmlns BOOL DEFAULT TRUE,
    title TEXT DEFAULT NULL,
    description TEXT DEFAULT NULL,
    creator TEXT DEFAULT NULL,
    update_ts TEXT DEFAULT NULL,
    unapi_url TEXT DEFAULT NULL,
    header_xml XML DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    library_group INT DEFAULT NULL
     ) RETURNS XML AS $F$
DECLARE
    layout          unapi.bre_output_layout%ROWTYPE;
    transform       config.xml_transform%ROWTYPE;
    item_format     TEXT;
    tmp_xml         TEXT;
    xmlns_uri       TEXT := 'http://open-ils.org/spec/feed-xml/v1';
    ouid            INT;
    element_list    TEXT[];
BEGIN

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;
    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO transform FROM config.xml_transform WHERE name = layout.transform;
    xmlns_uri := COALESCE(transform.namespace_uri,xmlns_uri);

    -- Gather the bib xml
    SELECT XMLAGG( unapi.bre(i, format, '', includes, org, depth, slimit, soffset, include_xmlns, pref_lib, library_group)) INTO tmp_xml FROM UNNEST( id_list ) i;

    IF layout.title_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.title_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, title;
    END IF;

    IF layout.description_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.description_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, description;
    END IF;

    IF layout.creator_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.creator_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, creator;
    END IF;

    IF layout.update_ts_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.update_ts_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, update_ts;
    END IF;

    IF unapi_url IS NOT NULL THEN
        EXECUTE $$SELECT XMLCONCAT( XMLELEMENT( name link, XMLATTRIBUTES( 'http://www.w3.org/1999/xhtml' AS xmlns, 'unapi-server' AS rel, $1 AS href, 'unapi' AS title)), $2)$$ INTO tmp_xml USING unapi_url, tmp_xml::XML;
    END IF;

    IF header_xml IS NOT NULL THEN tmp_xml := XMLCONCAT(header_xml,tmp_xml::XML); END IF;

    element_list := regexp_split_to_array(layout.feed_top,E'\\.');
    FOR i IN REVERSE ARRAY_UPPER(element_list, 1) .. 1 LOOP
        EXECUTE 'SELECT XMLELEMENT( name '|| quote_ident(element_list[i]) ||', XMLATTRIBUTES( $1 AS xmlns), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML;
    END LOOP;

    RETURN tmp_xml::XML;
END;
$F$ LANGUAGE PLPGSQL STABLE;


DROP FUNCTION IF EXISTS unapi.metabib_virtual_record_feed (
    id_list BIGINT[],
    format TEXT,
    includes TEXT[],
    org TEXT,
    depth INT,
    slimit HSTORE,
    soffset HSTORE,
    include_xmlns BOOL, title TEXT,
    description TEXT,
    creator TEXT,
    update_ts TEXT,
    unapi_url TEXT,
    header_xml XML,
    pref_lib INT);
CREATE OR REPLACE FUNCTION unapi.metabib_virtual_record_feed (
    id_list BIGINT[],
    format TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    title TEXT DEFAULT NULL,
    description TEXT DEFAULT NULL,
    creator TEXT DEFAULT NULL,
    update_ts TEXT DEFAULT NULL,
    unapi_url TEXT DEFAULT NULL,
    header_xml XML DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    library_group INT DEFAULT NULL ) RETURNS XML AS $F$
DECLARE
    layout          unapi.bre_output_layout%ROWTYPE;
    transform       config.xml_transform%ROWTYPE;
    item_format     TEXT;
    tmp_xml         TEXT;
    xmlns_uri       TEXT := 'http://open-ils.org/spec/feed-xml/v1';
    ouid            INT;
    element_list    TEXT[];
BEGIN

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;
    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO transform FROM config.xml_transform WHERE name = layout.transform;
    xmlns_uri := COALESCE(transform.namespace_uri,xmlns_uri);

    -- Gather the bib xml
    SELECT XMLAGG( unapi.mmr(i, format, '', includes, org, depth, slimit, soffset, include_xmlns, pref_lib, library_group)) INTO tmp_xml FROM UNNEST( id_list ) i;

    IF layout.title_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.title_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, title;
    END IF;

    IF layout.description_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.description_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, description;
    END IF;

    IF layout.creator_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.creator_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, creator;
    END IF;

    IF layout.update_ts_element IS NOT NULL THEN
        EXECUTE 'SELECT XMLCONCAT( XMLELEMENT( name '|| layout.update_ts_element ||', XMLATTRIBUTES( $1 AS xmlns), $3), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML, update_ts;
    END IF;

    IF unapi_url IS NOT NULL THEN
        EXECUTE $$SELECT XMLCONCAT( XMLELEMENT( name link, XMLATTRIBUTES( 'http://www.w3.org/1999/xhtml' AS xmlns, 'unapi-server' AS rel, $1 AS href, 'unapi' AS title)), $2)$$ INTO tmp_xml USING unapi_url, tmp_xml::XML;
    END IF;

    IF header_xml IS NOT NULL THEN tmp_xml := XMLCONCAT(header_xml,tmp_xml::XML); END IF;

    element_list := regexp_split_to_array(layout.feed_top,E'\\.');
    FOR i IN REVERSE ARRAY_UPPER(element_list, 1) .. 1 LOOP
        EXECUTE 'SELECT XMLELEMENT( name '|| quote_ident(element_list[i]) ||', XMLATTRIBUTES( $1 AS xmlns), $2)' INTO tmp_xml USING xmlns_uri, tmp_xml::XML;
    END LOOP;

    RETURN tmp_xml::XML;
END;
$F$ LANGUAGE PLPGSQL STABLE;


DROP FUNCTION IF EXISTS unapi.mmr(
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT,
    slimit HSTORE,
    soffset HSTORE,
    include_xmlns BOOL,
    pref_lib INT
);

CREATE OR REPLACE FUNCTION unapi.mmr (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL,
    library_group INT DEFAULT NULL
)
RETURNS XML AS $F$
DECLARE
    mmrec   metabib.metarecord%ROWTYPE;
    leadrec biblio.record_entry%ROWTYPE;
    subrec biblio.record_entry%ROWTYPE;
    layout  unapi.bre_output_layout%ROWTYPE;
    xfrm    config.xml_transform%ROWTYPE;
    ouid    INT;
    xml_buf TEXT; -- growing XML document
    tmp_xml TEXT; -- single-use XML string
    xml_frag TEXT; -- single-use XML fragment
    top_el  TEXT;
    output  XML;
    hxml    XML;
    axml    XML;
    subxml  XML; -- subordinate records elements
    sub_xpath TEXT; 
    parts   TEXT[]; 
BEGIN

    -- xpath for extracting bre.marc values from subordinate records 
    -- so they may be appended to the MARC of the master record prior
    -- to XSLT processing.
    -- subjects, isbn, issn, upc -- anything else?
    sub_xpath := 
      '//*[starts-with(@tag, "6") or @tag="020" or @tag="022" or @tag="024"]';

    IF org = '-' OR org IS NULL THEN
        SELECT shortname INTO org FROM evergreen.org_top();
    END IF;

    SELECT id INTO ouid FROM actor.org_unit WHERE shortname = org;

    IF ouid IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT INTO mmrec * FROM metabib.metarecord WHERE id = obj_id;
    IF NOT FOUND THEN
        RETURN NULL::XML;
    END IF;

    -- TODO: aggregate holdings from constituent records
    IF format = 'holdings_xml' THEN -- the special case
        output := unapi.mmr_holdings_xml(
            obj_id, ouid, org, depth,
            array_remove(includes,'holdings_xml'),
            slimit, soffset, include_xmlns, pref_lib, library_group);
        RETURN output;
    END IF;

    SELECT * INTO layout FROM unapi.bre_output_layout WHERE name = format;

    IF layout.name IS NULL THEN
        RETURN NULL::XML;
    END IF;

    SELECT * INTO xfrm FROM config.xml_transform WHERE name = layout.transform;

    SELECT INTO leadrec * FROM biblio.record_entry WHERE id = mmrec.master_record;

    -- Grab distinct MVF for all records if requested
    IF ('mra' = ANY (includes)) THEN 
        axml := unapi.mmr_mra(obj_id,NULL,NULL,NULL,org,depth,NULL,NULL,TRUE,pref_lib);
    ELSE
        axml := NULL::XML;
    END IF;

    xml_buf = leadrec.marc;

    hxml := NULL::XML;
    IF ('holdings_xml' = ANY (includes)) THEN
        hxml := unapi.mmr_holdings_xml(
                    obj_id, ouid, org, depth,
                    array_remove(includes,'holdings_xml'),
                    slimit, soffset, include_xmlns, pref_lib, library_group);
    END IF;

    subxml := NULL::XML;
    parts := '{}'::TEXT[];
    FOR subrec IN SELECT bre.* FROM biblio.record_entry bre
         JOIN metabib.metarecord_source_map mmsm ON (mmsm.source = bre.id)
         JOIN metabib.metarecord mmr ON (mmr.id = mmsm.metarecord)
         WHERE mmr.id = obj_id AND NOT bre.deleted
         ORDER BY CASE WHEN bre.id = mmr.master_record THEN 0 ELSE bre.id END
         LIMIT COALESCE((slimit->'bre')::INT, 5) LOOP

        IF subrec.id = leadrec.id THEN CONTINUE; END IF;
        -- Append choice data from the the non-lead records to the 
        -- the lead record document

        parts := parts || xpath(sub_xpath, subrec.marc::XML)::TEXT[];
    END LOOP;

    SELECT STRING_AGG( DISTINCT p , '' )::XML INTO subxml FROM UNNEST(parts) p;

    -- append data from the subordinate records to the 
    -- main record document before applying the XSLT

    IF subxml IS NOT NULL THEN 
        xml_buf := REGEXP_REPLACE(xml_buf, 
            '</record>(.*?)$', subxml || '</record>' || E'\\1');
    END IF;

    IF format = 'marcxml' THEN
         -- If we're not using the prefixed namespace in 
         -- this record, then remove all declarations of it
        IF xml_buf !~ E'<marc:' THEN
           xml_buf := REGEXP_REPLACE(xml_buf, 
            ' xmlns:marc="http://www.loc.gov/MARC21/slim"', '', 'g');
        END IF; 
    ELSE
        xml_buf := oils_xslt_process(xml_buf, xfrm.xslt)::XML;
    END IF;

    -- update top_el to reflect the change in xml_buf, which may
    -- now be a different type of document (e.g. record -> mods)
    top_el := REGEXP_REPLACE(xml_buf, E'^.*?<((?:\\S+:)?' || 
        layout.holdings_element || ').*$', E'\\1');

    IF axml IS NOT NULL THEN 
        xml_buf := REGEXP_REPLACE(xml_buf, 
            '</' || top_el || '>(.*?)$', axml || '</' || top_el || E'>\\1');
    END IF;

    IF hxml IS NOT NULL THEN
        xml_buf := REGEXP_REPLACE(xml_buf, 
            '</' || top_el || '>(.*?)$', hxml || '</' || top_el || E'>\\1');
    END IF;

    IF ('mmr.unapi' = ANY (includes)) THEN 
        output := REGEXP_REPLACE(
            xml_buf,
            '</' || top_el || '>(.*?)',
            XMLELEMENT(
                name abbr,
                XMLATTRIBUTES(
                    'http://www.w3.org/1999/xhtml' AS xmlns,
                    'unapi-id' AS class,
                    'tag:open-ils.org:U2@mmr/' || obj_id || '/' || org AS title
                )
            )::TEXT || '</' || top_el || E'>\\1'
        );
    ELSE
        output := xml_buf;
    END IF;

    -- remove ignorable whitesace
    output := REGEXP_REPLACE(output::TEXT,E'>\\s+<','><','gs')::XML;
    RETURN output;
END;
$F$ LANGUAGE PLPGSQL STABLE;

DROP FUNCTION IF EXISTS unapi.mmr_holdings_xml (
    mid BIGINT,
    ouid INT,
    org TEXT,
    depth INT,
    includes TEXT[],
    slimit HSTORE,
    soffset HSTORE,
    include_xmlns BOOL,
    pref_lib INT
);

CREATE OR REPLACE FUNCTION unapi.mmr_holdings_xml (
    mid BIGINT,
    ouid INT,
    org TEXT,
    depth INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[],
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL,
    library_group INT DEFAULT NULL
)
RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('mmr' = ANY ($5)) THEN 'tag:open-ils.org:U2@mmr/' || $1 || '/' || $3 ELSE NULL END AS id,
                    (SELECT metarecord_has_holdable_copy FROM asset.metarecord_has_holdable_copy($1)) AS has_holdable
                 ),
                 XMLELEMENT(
                     name counts,
                     (SELECT  XMLAGG(XMLELEMENT::XML) FROM (
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_metarecord_copy_count($2,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_ou_metarecord_copy_count($2, $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('pref_lib' as type, depth, org_unit, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_ou_metarecord_copy_count($9,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('public' as type, depth, library_group, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.opac_lasso_metarecord_copy_count_sum(library_group,  $1)
                                     UNION
                         SELECT  XMLELEMENT(
                                     name count,
                                     XMLATTRIBUTES('staff' as type, depth, library_group, coalesce(transcendant,0) as transcendant, available, visible as count, unshadow)
                                 )::text
                           FROM  asset.staff_lasso_metarecord_copy_count_sum(library_group,  $1)
                                     ORDER BY 1
                     )x)
                 ),
                 -- XXX monograph_parts and foreign_copies are skipped in MRs ... put them back some day?
                 XMLELEMENT(
                     name volumes,
                     (SELECT XMLAGG(acn ORDER BY rank, name, label_sortkey) FROM (
                        -- Physical copies
                        SELECT  unapi.acn(y.id,'xml','volume',array_remove( array_remove($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), y.rank, name, label_sortkey
                        FROM evergreen.ranked_volumes((SELECT ARRAY_AGG(source) FROM metabib.metarecord_source_map WHERE metarecord = $1), $2, $4, $6, $7, $9, $5) AS y
                        UNION ALL
                        -- Located URIs
                        SELECT unapi.acn(uris.id,'xml','volume',array_remove( array_remove($5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE), uris.rank, name, label_sortkey
                        FROM evergreen.located_uris((SELECT ARRAY_AGG(source) FROM metabib.metarecord_source_map WHERE metarecord = $1), $2, $9) AS uris
                     )x)
                 ),
                 CASE WHEN ('ssub' = ANY ($5)) THEN
                     XMLELEMENT(
                         name subscriptions,
                         (SELECT XMLAGG(ssub) FROM (
                            SELECT  unapi.ssub(id,'xml','subscription','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  serial.subscription
                              WHERE record_entry IN (SELECT source FROM metabib.metarecord_source_map WHERE metarecord = $1)
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL STABLE;


SELECT evergreen.upgrade_deps_block_check('1465', :eg_version);

ALTER TABLE config.ui_staff_portal_page_entry
ADD COLUMN url_newtab boolean;


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


SELECT evergreen.upgrade_deps_block_check('1467', :eg_version);

CREATE TABLE action.eresource_link_click (
    id          BIGSERIAL PRIMARY KEY,
    clicked_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    url         TEXT,
    record      BIGINT NOT NULL REFERENCES biblio.record_entry (id)
);

CREATE TABLE action.eresource_link_click_course (
    id            SERIAL      PRIMARY KEY,
    click         BIGINT NOT NULL REFERENCES action.eresource_link_click (id) ON DELETE CASCADE,
    course        INT REFERENCES asset.course_module_course (id) ON UPDATE CASCADE ON DELETE SET NULL,
    course_name   TEXT NOT NULL,
    course_number TEXT NOT NULL
);

INSERT INTO config.global_flag  (name, label, enabled)
    VALUES (
        'opac.eresources.link_click_tracking',
        oils_i18n_gettext('opac.eresources.link_click_tracking',
                          'Track clicks on eresources links.  Before enabling this global flag, be sure that you are monitoring disk space on your database server and have a cron job set up to delete click records after the desired retention interval.',
                          'cgf', 'label'),
        FALSE
    );

CREATE FUNCTION action.delete_old_eresource_link_clicks(days integer)
    RETURNS VOID AS
    'DELETE FROM action.eresource_link_click
     WHERE clicked_at < current_timestamp
               - ($1::text || '' days'')::interval'
    LANGUAGE SQL
    VOLATILE;



SELECT evergreen.upgrade_deps_block_check('1468', :eg_version);

-- Necessary pre-seed data


INSERT INTO actor.passwd_type (code, name, login, crypt_algo, iter_count)
    VALUES ('api', 'OpenAPI Integration Password', TRUE, 'bf', 10)
ON CONFLICT DO NOTHING;

-- Move top-level perms "down" ...
INSERT INTO permission.grp_perm_map (grp,perm,depth,grantable)
 SELECT  DISTINCT g.id, p.perm, p.depth, p.grantable
   FROM  permission.grp_perm_map p,
         permission.grp_tree g
   WHERE g.parent = 1 AND p.grp = 1;

-- ... then remove the User version ...
DELETE FROM permission.grp_perm_map WHERE grp = 1;

-- ... and add a new branch to the group tree for API perms
INSERT INTO permission.grp_tree (name, parent, description, application_perm)
    VALUES ('API Integrator', 1, 'API Integration Accounts', 'group_application.api_integrator');

INSERT INTO permission.grp_tree (name, parent, description, application_perm) SELECT 'Patron API', id, 'Patron API', 'group_application.api_integrator' FROM permission.grp_tree WHERE name = 'API Integrator';
INSERT INTO permission.grp_tree (name, parent, description, application_perm) SELECT 'Org Unit API', id, 'Org Unit API', 'group_application.api_integrator' FROM permission.grp_tree WHERE name = 'API Integrator';
INSERT INTO permission.grp_tree (name, parent, description, application_perm) SELECT 'Bib Record API', id, 'Bib Record API', 'group_application.api_integrator' FROM permission.grp_tree WHERE name = 'API Integrator';
INSERT INTO permission.grp_tree (name, parent, description, application_perm) SELECT 'Item Record API', id, 'Item Record API', 'group_application.api_integrator' FROM permission.grp_tree WHERE name = 'API Integrator';
INSERT INTO permission.grp_tree (name, parent, description, application_perm) SELECT 'Holds API', id, 'Holds API', 'group_application.api_integrator' FROM permission.grp_tree WHERE name = 'API Integrator';
INSERT INTO permission.grp_tree (name, parent, description, application_perm) SELECT 'Debt Collection API', id, 'Debt Collection API', 'group_application.api_integrator' FROM permission.grp_tree WHERE name = 'API Integrator';
INSERT INTO permission.grp_tree (name, parent, description, application_perm) SELECT 'Course Reserves API', id, 'Course Reserves API', 'group_application.api_integrator' FROM permission.grp_tree WHERE name = 'API Integrator';

INSERT INTO permission.perm_list (code) VALUES
 ('group_application.api_integrator'),
 ('API_LOGIN'),
 ('REST.api'),
 ('REST.api.patrons'),
 ('REST.api.orgs'),
 ('REST.api.bibs'),
 ('REST.api.items'),
 ('REST.api.holds'),
 ('REST.api.collections'),
 ('REST.api.courses')
 --- ... etc
ON CONFLICT DO NOTHING;

INSERT INTO permission.grp_perm_map (grp,perm,depth)
    SELECT g.id, p.id, 0 FROM permission.grp_tree g, permission.perm_list p WHERE g.name='API Integrator' AND p.code IN ('API_LOGIN','REST.api')
        UNION
    SELECT g.id, p.id, 0 FROM permission.grp_tree g, permission.perm_list p WHERE g.name='Patron API' AND p.code = 'REST.api.patrons'
        UNION
    SELECT g.id, p.id, 0 FROM permission.grp_tree g, permission.perm_list p WHERE g.name='Org Unit API' AND p.code = 'REST.api.orgs'
        UNION
    SELECT g.id, p.id, 0 FROM permission.grp_tree g, permission.perm_list p WHERE g.name='Bib Record API' AND p.code = 'REST.api.bibs'
        UNION
    SELECT g.id, p.id, 0 FROM permission.grp_tree g, permission.perm_list p WHERE g.name='Item Record API' AND p.code = 'REST.api.items'
        UNION
    SELECT g.id, p.id, 0 FROM permission.grp_tree g, permission.perm_list p WHERE g.name='Holds API' AND p.code = 'REST.api.holds'
        UNION
    SELECT g.id, p.id, 0 FROM permission.grp_tree g, permission.perm_list p WHERE g.name='Debt Collection API' AND p.code = 'REST.api.collections'
        UNION
    SELECT g.id, p.id, 0 FROM permission.grp_tree g, permission.perm_list p WHERE g.name='Course Reserves API' AND p.code = 'REST.api.courses'
ON CONFLICT DO NOTHING;

DROP SCHEMA IF EXISTS openapi CASCADE;
CREATE SCHEMA IF NOT EXISTS openapi;

CREATE TABLE IF NOT EXISTS openapi.integrator (
    id      INT     PRIMARY KEY REFERENCES actor.usr (id),
    enabled BOOL    NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS openapi.json_schema_datatype (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL UNIQUE,
    description TEXT
);
INSERT INTO openapi.json_schema_datatype (name,label) VALUES
    ('boolean','Boolean'),
    ('string','String'),
    ('integer','Integer'),
    ('number','Number'),
    ('array','Array'),
    ('object','Object')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS openapi.json_schema_format (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL UNIQUE,
    description TEXT
);
INSERT INTO openapi.json_schema_format (name,label) VALUES
    ('date-time','Timestamp'),
    ('date','Date'),
    ('time','Time'),
    ('interval','Interval'),
    ('email','Email Address'),
    ('uri','URI'),
    ('identifier','Opaque Identifier'),
    ('money','Money'),
    ('float','Floating Point Number'),
    ('int64','Large Integer'),
    ('password','Password')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS openapi.rate_limit_definition (
    id              SERIAL      PRIMARY KEY,
    name            TEXT        UNIQUE NOT NULL, -- i18n
    limit_interval  INTERVAL    NOT NULL,
    limit_count     INT         NOT NULL
);
SELECT SETVAL('openapi.rate_limit_definition_id_seq'::TEXT, 100);
INSERT INTO openapi.rate_limit_definition (id, name, limit_interval, limit_count) VALUES
    (1, 'Once per second', '1 second', 1),
    (2, 'Ten per minute', '1 minute', 10),
    (3, 'One hunderd per hour', '1 hour', 100),
    (4, 'One thousand per hour', '1 hour', 1000),
    (5, 'One thousand per 24 hour period', '24 hours', 1000),
    (6, 'Ten thousand per 24 hour period', '24 hours', 10000),
    (7, 'Unlimited', '1 second', 1000000),
    (8, 'One hundred per second', '1 second', 100)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS openapi.endpoint (
    operation_id    TEXT    PRIMARY KEY,
    path            TEXT    NOT NULL,
    http_method     TEXT    NOT NULL CHECK (http_method IN ('get','put','post','delete','patch')),
    security        TEXT    NOT NULL DEFAULT 'bearerAuth' CHECK (security IN ('bearerAuth','basicAuth','cookieAuth','paramAuth')),
    summary         TEXT    NOT NULL,
    method_source   TEXT    NOT NULL, -- perl module or opensrf application, tested by regex and assumes opensrf app name contains a "."
    method_name     TEXT    NOT NULL,
    method_params   TEXT,             -- eg, 'eg_auth_token hold' or 'eg_auth_token eg_user_id circ req.json'
    active          BOOL    NOT NULL DEFAULT TRUE,
    rate_limit      INT     REFERENCES openapi.rate_limit_definition (id),
    CONSTRAINT path_and_method_once UNIQUE (path, http_method)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_param (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    name            TEXT    NOT NULL CHECK (name ~ '^\w+$'),
    required        BOOL    NOT NULL DEFAULT FALSE,
    in_part         TEXT    NOT NULL DEFAULT 'query' CHECK (in_part IN ('path','query','header','cookie')),
    fm_type         TEXT,
    schema_type     TEXT    REFERENCES openapi.json_schema_datatype (name),
    schema_format   TEXT    REFERENCES openapi.json_schema_format (name),
    array_items     TEXT    REFERENCES openapi.json_schema_datatype (name),
    default_value   TEXT,
    CONSTRAINT endpoint_and_name_once UNIQUE (endpoint, name),
    CONSTRAINT format_requires_type CHECK (schema_format IS NULL OR schema_type IS NOT NULL),
    CONSTRAINT array_items_requires_array_type CHECK (array_items IS NULL OR schema_type = 'array')
);
CREATE TABLE IF NOT EXISTS openapi.endpoint_response (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    validate        BOOL    NOT NULL DEFAULT TRUE,
    status          INT     NOT NULL DEFAULT 200,
    content_type    TEXT    NOT NULL DEFAULT 'application/json',
    description     TEXT    NOT NULL DEFAULT 'Success',
    fm_type         TEXT,
    schema_type     TEXT    REFERENCES openapi.json_schema_datatype (name),
    schema_format   TEXT    REFERENCES openapi.json_schema_format (name),
    array_items     TEXT    REFERENCES openapi.json_schema_datatype (name),
    CONSTRAINT endpoint_status_content_type_once UNIQUE (endpoint, status, content_type)
);

CREATE TABLE IF NOT EXISTS openapi.perm_set (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    NOT NULL
); -- push sequence value
SELECT SETVAL('openapi.perm_set_id_seq'::TEXT, 1001);
INSERT INTO openapi.perm_set (id, name) VALUES
 (1,'Self - API only'),
 (2,'Patrons - API only'),
 (3,'Orgs - API only'),
 (4,'Bibs - API only'),
 (5,'Items - API only'),
 (6,'Holds - API only'),
 (7,'Collections - API only'),
 (8,'Courses - API only'),

 (101,'Self - standard permissions'),
 (102,'Patrons - standard permissions'),
 (103,'Orgs - standard permissions'),
 (104,'Bibs - standard permissions'),
 (105,'Items - standard permissions'),
 (106,'Holds - standard permissions'),
 (107,'Collections - standard permissions'),
 (108,'Courses - standard permissions')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS openapi.perm_set_perm_map (
    id          SERIAL  PRIMARY KEY,
    perm_set    INT     NOT NULL REFERENCES openapi.perm_set (id) ON UPDATE CASCADE ON DELETE CASCADE,
    perm        INT     NOT NULL REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE CASCADE
);
INSERT INTO openapi.perm_set_perm_map (perm_set, perm)
  SELECT 1, id FROM permission.perm_list WHERE code IN ('API_LOGIN','REST.api')
    UNION
  SELECT 2, id FROM permission.perm_list WHERE code IN ('API_LOGIN','REST.api','REST.api.patrons')
    UNION
  SELECT 3, id FROM permission.perm_list WHERE code IN ('API_LOGIN','REST.api','REST.api.orgs')
    UNION
  SELECT 4, id FROM permission.perm_list WHERE code IN ('API_LOGIN','REST.api','REST.api.bibs')
    UNION
  SELECT 5, id FROM permission.perm_list WHERE code IN ('API_LOGIN','REST.api','REST.api.items')
    UNION
  SELECT 6, id FROM permission.perm_list WHERE code IN ('API_LOGIN','REST.api','REST.api.holds')
    UNION
  SELECT 7, id FROM permission.perm_list WHERE code IN ('API_LOGIN','REST.api','REST.api.collections')
    UNION
  SELECT 8, id FROM permission.perm_list WHERE code IN ('API_LOGIN','REST.api','REST.api.cources')
    UNION
                -- ...
  SELECT 101, id FROM permission.perm_list WHERE code IN ('OPAC_LOGIN')
    UNION
  SELECT 102, id FROM permission.perm_list WHERE code IN ('STAFF_LOGIN','VIEW_USER')
    UNION
  SELECT 103, id FROM permission.perm_list WHERE code IN ('OPAC_LOGIN')
    UNION
  SELECT 104, id FROM permission.perm_list WHERE code IN ('OPAC_LOGIN')
    UNION
  SELECT 105, id FROM permission.perm_list WHERE code IN ('OPAC_LOGIN')
    UNION
  SELECT 106, id FROM permission.perm_list WHERE code IN ('STAFF_LOGIN','VIEW_USER')
    UNION
  SELECT 107, id FROM permission.perm_list WHERE code IN ('STAFF_LOGIN','VIEW_USER')
    UNION
  SELECT 108, id FROM permission.perm_list WHERE code IN ('STAFF_LOGIN')

ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS openapi.endpoint_perm_set_map (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint(operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    perm_set        INT     NOT NULL REFERENCES openapi.perm_set (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set (
    name            TEXT    PRIMARY KEY,
    description     TEXT    NOT NULL,
    active          BOOL    NOT NULL DEFAULT TRUE,
    rate_limit      INT     REFERENCES openapi.rate_limit_definition (id)
);
INSERT INTO openapi.endpoint_set (name, description) VALUES
  ('self', 'Methods for retrieving and manipulating your own user account information'),
  ('orgs', 'Methods for retrieving and manipulating organizational unit information'),
  ('patrons', 'Methods for retrieving and manipulating patron information'),
  ('holds', 'Methods for accessing and manipulating hold data'),
  ('collections', 'Methods for accessing and manipulating patron debt collections data'),
  ('bibs', 'Methods for accessing and manipulating bibliographic records and related data'),
  ('items', 'Methods for accessing and manipulating barcoded item records'),
  ('courses', 'Methods for accessing and manipulating course reserve data')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS openapi.endpoint_user_rate_limit_map (
    id              SERIAL  PRIMARY KEY,
    accessor        INT     NOT NULL REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    rate_limit      INT     NOT NULL REFERENCES openapi.rate_limit_definition (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_accessor_once UNIQUE (accessor, endpoint)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_user_rate_limit_map (
    id              SERIAL  PRIMARY KEY,
    accessor        INT     NOT NULL REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    rate_limit      INT     NOT NULL REFERENCES openapi.rate_limit_definition (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_set_accessor_once UNIQUE (accessor, endpoint_set)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_ip_rate_limit_map (
    id              SERIAL  PRIMARY KEY,
    ip_range        INET    NOT NULL,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    rate_limit      INT     NOT NULL REFERENCES openapi.rate_limit_definition (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_ip_range_once UNIQUE (ip_range, endpoint)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_ip_rate_limit_map (
    id              SERIAL  PRIMARY KEY,
    ip_range        INET    NOT NULL,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    rate_limit      INT     NOT NULL REFERENCES openapi.rate_limit_definition (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_set_ip_range_once UNIQUE (ip_range, endpoint_set)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_endpoint_map (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_set_endpoint_once UNIQUE (endpoint_set, endpoint)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_perm_map (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    perm            INT     NOT NULL REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_perm_set_map (
    id              SERIAL  PRIMARY KEY,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    perm_set        INT     NOT NULL REFERENCES openapi.perm_set (id) ON UPDATE CASCADE ON DELETE CASCADE
);
INSERT INTO openapi.endpoint_set_perm_set_map (endpoint_set, perm_set) VALUES
  ('self', 1),        ('self', 101),
  ('patrons', 2),     ('patrons', 102),
  ('orgs', 3),        ('orgs', 103),
  ('bibs', 4),        ('bibs', 104),
  ('items', 5),       ('items', 105),
  ('holds', 6),       ('holds', 106),
  ('collections', 7), ('collections', 107),
  ('courses', 8),     ('courses', 108)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_perm_map (
    id              SERIAL  PRIMARY KEY,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    perm            INT     NOT NULL REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS openapi.authen_attempt_log (
    request_id      TEXT        PRIMARY KEY,
    attempt_time    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_addr         INET,
    cred_user       TEXT,
    token           TEXT
);
CREATE INDEX authen_cred_user_attempt_time_idx ON openapi.authen_attempt_log (attempt_time, cred_user);
CREATE INDEX authen_ip_addr_attempt_time_idx ON openapi.authen_attempt_log (attempt_time, ip_addr);

CREATE TABLE IF NOT EXISTS openapi.endpoint_access_attempt_log (
    request_id      TEXT        PRIMARY KEY,
    attempt_time    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    endpoint        TEXT        NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    allowed         BOOL        NOT NULL,
    ip_addr         INET,
    accessor        INT         REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    token           TEXT
);
CREATE INDEX access_accessor_attempt_time_idx ON openapi.endpoint_access_attempt_log (accessor, attempt_time);

CREATE TABLE IF NOT EXISTS openapi.endpoint_dispatch_log (
    request_id      TEXT        PRIMARY KEY,
    complete_time   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    error           BOOL        NOT NULL
);

CREATE OR REPLACE FUNCTION actor.verify_passwd(pw_usr integer, pw_type text, test_passwd text) RETURNS boolean AS $f$
DECLARE
    pw_salt     TEXT;
    api_enabled BOOL;
BEGIN
    /* Returns TRUE if the password provided matches the in-db password.
     * If the password type is salted, we compare the output of CRYPT().
     * NOTE: test_passwd is MD5(salt || MD5(password)) for legacy
     * 'main' passwords.
     *
     * Password type 'api' requires that the user be enabled as an
     * integrator in the openapi.integrator table.
     */

    IF pw_type = 'api' THEN
        SELECT  enabled INTO api_enabled
          FROM  openapi.integrator
          WHERE id = pw_usr;

        IF NOT FOUND OR api_enabled IS FALSE THEN
            -- API integrator account not registered
            RETURN FALSE;
        END IF;
    END IF;

    SELECT INTO pw_salt salt FROM actor.passwd
        WHERE usr = pw_usr AND passwd_type = pw_type;

    IF NOT FOUND THEN
        -- no such password
        RETURN FALSE;
    END IF;

    IF pw_salt IS NULL THEN
        -- Password is unsalted, compare the un-CRYPT'ed values.
        RETURN EXISTS (
            SELECT TRUE FROM actor.passwd WHERE
                usr = pw_usr AND
                passwd_type = pw_type AND
                passwd = test_passwd
        );
    END IF;

    RETURN EXISTS (
        SELECT TRUE FROM actor.passwd WHERE
            usr = pw_usr AND
            passwd_type = pw_type AND
            passwd = CRYPT(test_passwd, pw_salt)
    );
END;
$f$ STRICT LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION openapi.find_default_endpoint_rate_limit (target_endpoint TEXT) RETURNS openapi.rate_limit_definition AS $f$
DECLARE
    def_rl    openapi.rate_limit_definition%ROWTYPE;
BEGIN
    -- Default rate limits can be applied at the endpoint or endpoint_set level;
    -- endpoint overrides endpoint_set, and we choose the most restrictive from
    -- the set if we have to look there.
    SELECT  d.* INTO def_rl
      FROM  openapi.rate_limit_definition d
            JOIN openapi.endpoint e ON (e.rate_limit = d.id)
      WHERE e.operation_id = target_endpoint;

    IF NOT FOUND THEN
        SELECT  d.* INTO def_rl
          FROM  openapi.rate_limit_definition d
                JOIN openapi.endpoint_set es ON (es.rate_limit = d.id)
                JOIN openapi.endpoint_set_endpoint_map m ON (es.name = m.endpoint_set AND m.endpoint = target_endpoint)
           -- This ORDER BY calculates the avg time between requests the user would have to wait to perfectly
           -- avoid rate limiting.  So, a bigger wait means it's more restrictive.  We take the most restrictive
           -- set-applied one.
          ORDER BY EXTRACT(EPOCH FROM d.limit_interval) / d.limit_count::NUMERIC DESC
          LIMIT 1;
    END IF;

    -- If there's no default for the endpoint or set, we provide 1/sec.
    IF NOT FOUND THEN
        def_rl.limit_interval := '1 second'::INTERVAL;
        def_rl.limit_count := 1;
    END IF;

    RETURN def_rl;
END;
$f$ STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION openapi.find_user_endpoint_rate_limit (target_endpoint TEXT, accessing_usr INT) RETURNS openapi.rate_limit_definition AS $f$
DECLARE
    def_u_rl    openapi.rate_limit_definition%ROWTYPE;
BEGIN
    SELECT  d.* INTO def_u_rl
      FROM  openapi.rate_limit_definition d
            JOIN openapi.endpoint_user_rate_limit_map e ON (e.rate_limit = d.id)
      WHERE e.endpoint = target_endpoint
            AND e.accessor = accessing_usr;

    IF NOT FOUND THEN
        SELECT  d.* INTO def_u_rl
          FROM  openapi.rate_limit_definition d
                JOIN openapi.endpoint_set_user_rate_limit_map e ON (e.rate_limit = d.id AND e.accessor = accessing_usr)
                JOIN openapi.endpoint_set_endpoint_map m ON (e.endpoint_set = m.endpoint_set AND m.endpoint = target_endpoint)
          ORDER BY EXTRACT(EPOCH FROM d.limit_interval) / d.limit_count::NUMERIC DESC
          LIMIT 1;
    END IF;

    RETURN def_u_rl;
END;
$f$ STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION openapi.find_ip_addr_endpoint_rate_limit (target_endpoint TEXT, from_ip_addr INET) RETURNS openapi.rate_limit_definition AS $f$
DECLARE
    def_i_rl    openapi.rate_limit_definition%ROWTYPE;
BEGIN
    SELECT  d.* INTO def_i_rl
      FROM  openapi.rate_limit_definition d
            JOIN openapi.endpoint_ip_rate_limit_map e ON (e.rate_limit = d.id)
      WHERE e.endpoint = target_endpoint
            AND e.ip_range && from_ip_addr
       -- For IPs, we order first by the size of the ranges that we
       -- matched (mask length), most specific (smallest block of IPs)
       -- first, then by the restrictiveness of the limit, more restrictive first.
      ORDER BY MASKLEN(e.ip_range) DESC, EXTRACT(EPOCH FROM d.limit_interval) / d.limit_count::NUMERIC DESC
      LIMIT 1;

    IF NOT FOUND THEN
        SELECT  d.* INTO def_i_rl
          FROM  openapi.rate_limit_definition d
                JOIN openapi.endpoint_set_ip_rate_limit_map e ON (e.rate_limit = d.id AND ip_range && from_ip_addr)
                JOIN openapi.endpoint_set_endpoint_map m ON (e.endpoint_set = m.endpoint_set AND m.endpoint = target_endpoint)
          ORDER BY MASKLEN(e.ip_range) DESC, EXTRACT(EPOCH FROM d.limit_interval) / d.limit_count::NUMERIC DESC
          LIMIT 1;
    END IF;

    RETURN def_i_rl;
END;
$f$ STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION openapi.check_generic_endpoint_rate_limit (target_endpoint TEXT, accessing_usr INT DEFAULT NULL, from_ip_addr INET DEFAULT NULL) RETURNS INT AS $f$
DECLARE
    def_rl    openapi.rate_limit_definition%ROWTYPE;
    def_u_rl  openapi.rate_limit_definition%ROWTYPE;
    def_i_rl  openapi.rate_limit_definition%ROWTYPE;
    u_wait    INT;
    i_wait    INT;
BEGIN
    def_rl := openapi.find_default_endpoint_rate_limit(target_endpoint);

    IF accessing_usr IS NOT NULL THEN
        def_u_rl := openapi.find_user_endpoint_rate_limit(target_endpoint, accessing_usr);
    END IF;

    IF from_ip_addr IS NOT NULL THEN
        def_i_rl := openapi.find_ip_addr_endpoint_rate_limit(target_endpoint, from_ip_addr);
    END IF;

    -- Now we test the user-based and IP-based limits in their focused way...
    IF def_u_rl.id IS NOT NULL THEN
        SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_u_rl.limit_interval) - NOW())) INTO u_wait
          FROM  (SELECT l.attempt_time,
                        COUNT(*) OVER (PARTITION BY l.accessor ORDER BY l.attempt_time DESC) AS running_count
                  FROM  openapi.endpoint_access_attempt_log l
                  WHERE l.endpoint = target_endpoint
                        AND l.accessor = accessing_usr
                        AND l.attempt_time > NOW() - def_u_rl.limit_interval
                ) x
          WHERE running_count = def_u_rl.limit_count;
    END IF;

    IF def_i_rl.id IS NOT NULL THEN
        SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_u_rl.limit_interval) - NOW())) INTO i_wait
          FROM  (SELECT l.attempt_time,
                        COUNT(*) OVER (PARTITION BY l.ip_addr ORDER BY l.attempt_time DESC) AS running_count
                  FROM  openapi.endpoint_access_attempt_log l
                  WHERE l.endpoint = target_endpoint
                        AND l.ip_addr = from_ip_addr
                        AND l.attempt_time > NOW() - def_u_rl.limit_interval
                ) x
          WHERE running_count = def_u_rl.limit_count;
    END IF;

    -- If there are no user-specific or IP-based limit
    -- overrides; check endpoint-wide limits for user,
    -- then IP, and if we were passed neither, then limit
    -- endpoint access for all users.  Better to lock it
    -- all down than to set the servers on fire.
    IF COALESCE(u_wait, i_wait) IS NULL AND COALESCE(def_i_rl.id, def_u_rl.id) IS NULL THEN
        IF accessing_usr IS NOT NULL THEN
            SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_rl.limit_interval) - NOW())) INTO u_wait
              FROM  (SELECT l.attempt_time,
                            COUNT(*) OVER (PARTITION BY l.accessor ORDER BY l.attempt_time DESC) AS running_count
                      FROM  openapi.endpoint_access_attempt_log l
                      WHERE l.endpoint = target_endpoint
                            AND l.accessor = accessing_usr
                            AND l.attempt_time > NOW() - def_rl.limit_interval
                    ) x
              WHERE running_count = def_rl.limit_count;
        ELSIF from_ip_addr IS NOT NULL THEN
            SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_rl.limit_interval) - NOW())) INTO i_wait
              FROM  (SELECT l.attempt_time,
                            COUNT(*) OVER (PARTITION BY l.ip_addr ORDER BY l.attempt_time DESC) AS running_count
                      FROM  openapi.endpoint_access_attempt_log l
                      WHERE l.endpoint = target_endpoint
                            AND l.ip_addr = from_ip_addr
                            AND l.attempt_time > NOW() - def_rl.limit_interval
                    ) x
              WHERE running_count = def_rl.limit_count;
        ELSE -- we have no user and no IP, global per-endpoint rate limit?
            SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_rl.limit_interval) - NOW())) INTO i_wait
              FROM  (SELECT l.attempt_time,
                            COUNT(*) OVER (PARTITION BY l.endpoint ORDER BY l.attempt_time DESC) AS running_count
                      FROM  openapi.endpoint_access_attempt_log l
                      WHERE l.endpoint = target_endpoint
                            AND l.attempt_time > NOW() - def_rl.limit_interval
                    ) x
              WHERE running_count = def_rl.limit_count;
        END IF;
    END IF;

    -- Send back the largest required wait time, or NULL for no restriction
    u_wait := GREATEST(u_wait,i_wait);
    IF u_wait > 0 THEN
        RETURN u_wait;
    END IF;

    RETURN NULL;
END;
$f$ STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION openapi.check_auth_endpoint_rate_limit (accessing_usr TEXT DEFAULT NULL, from_ip_addr INET DEFAULT NULL) RETURNS INT AS $f$
DECLARE
    def_rl    openapi.rate_limit_definition%ROWTYPE;
    def_u_rl  openapi.rate_limit_definition%ROWTYPE;
    def_i_rl  openapi.rate_limit_definition%ROWTYPE;
    u_wait    INT;
    i_wait    INT;
BEGIN
    def_rl := openapi.find_default_endpoint_rate_limit('authenticateUser');

    IF accessing_usr IS NOT NULL THEN
        SELECT  (openapi.find_user_endpoint_rate_limit('authenticateUser', u.id)).* INTO def_u_rl
          FROM  actor.usr u
          WHERE u.usrname = accessing_usr;
    END IF;

    IF from_ip_addr IS NOT NULL THEN
        def_i_rl := openapi.find_ip_addr_endpoint_rate_limit('authenticateUser', from_ip_addr);
    END IF;

    -- Now we test the user-based and IP-based limits in their focused way...
    IF def_u_rl.id IS NOT NULL THEN
        SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_u_rl.limit_interval) - NOW())) INTO u_wait
          FROM  (SELECT l.attempt_time,
                        COUNT(*) OVER (PARTITION BY l.cred_user ORDER BY l.attempt_time DESC) AS running_count
                  FROM  openapi.authen_attempt_log l
                  WHERE l.cred_user = accessing_usr
                        AND l.attempt_time > NOW() - def_u_rl.limit_interval
                ) x
          WHERE running_count = def_u_rl.limit_count;
    END IF;

    IF def_i_rl.id IS NOT NULL THEN
        SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_u_rl.limit_interval) - NOW())) INTO i_wait
          FROM  (SELECT l.attempt_time,
                        COUNT(*) OVER (PARTITION BY l.ip_addr ORDER BY l.attempt_time DESC) AS running_count
                  FROM  openapi.authen_attempt_log l
                  WHERE l.ip_addr = from_ip_addr
                        AND l.attempt_time > NOW() - def_u_rl.limit_interval
                ) x
          WHERE running_count = def_u_rl.limit_count;
    END IF;

    -- If there are no user-specific or IP-based limit
    -- overrides; check endpoint-wide limits for user,
    -- then IP, and if we were passed neither, then limit
    -- endpoint access for all users.  Better to lock it
    -- all down than to set the servers on fire.
    IF COALESCE(u_wait, i_wait) IS NULL AND COALESCE(def_i_rl.id, def_u_rl.id) IS NULL THEN
        IF accessing_usr IS NOT NULL THEN
            SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_rl.limit_interval) - NOW())) INTO u_wait
              FROM  (SELECT l.attempt_time,
                            COUNT(*) OVER (PARTITION BY l.cred_user ORDER BY l.attempt_time DESC) AS running_count
                      FROM  openapi.authen_attempt_log l
                      WHERE l.cred_user = accessing_usr
                            AND l.attempt_time > NOW() - def_rl.limit_interval
                    ) x
              WHERE running_count = def_rl.limit_count;
        ELSIF from_ip_addr IS NOT NULL THEN
            SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_rl.limit_interval) - NOW())) INTO i_wait
              FROM  (SELECT l.attempt_time,
                            COUNT(*) OVER (PARTITION BY l.ip_addr ORDER BY l.attempt_time DESC) AS running_count
                      FROM  openapi.authen_attempt_log l
                      WHERE l.ip_addr = from_ip_addr
                            AND l.attempt_time > NOW() - def_rl.limit_interval
                    ) x
              WHERE running_count = def_rl.limit_count;
        ELSE -- we have no user and no IP, global auth attempt rate limit?
            SELECT  CEIL(EXTRACT(EPOCH FROM (l.attempt_time + def_rl.limit_interval) - NOW())) INTO u_wait
              FROM  openapi.authen_attempt_log l
              WHERE l.attempt_time > NOW() - def_rl.limit_interval
              ORDER BY l.attempt_time DESC
              LIMIT 1 OFFSET def_rl.limit_count;
        END IF;
    END IF;

    -- Send back the largest required wait time, or NULL for no restriction
    u_wait := GREATEST(u_wait,i_wait);
    IF u_wait > 0 THEN
        RETURN u_wait;
    END IF;

    RETURN NULL;
END;
$f$ STABLE LANGUAGE PLPGSQL;

--===================================== Seed data ==================================

-- ===== authentication
INSERT INTO openapi.endpoint (operation_id, path, security, http_method, summary, method_source, method_name, method_params, rate_limit) VALUES
-- Builtin auth-related methods, give all users and IPs 100/s of each
  ('authenticateUser', '/self/auth', 'basicAuth', 'get', 'Authenticate API user', 'OpenILS::OpenAPI::Controller', 'authenticateUser', 'param.u param.p param.t', 8),
  ('logoutUser', '/self/auth', 'bearerAuth', 'delete', 'Logout API user', 'open-ils.auth', 'open-ils.auth.session.delete', 'eg_auth_token', 8)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,default_value) VALUES
  ('authenticateUser','u','query','string',NULL,NULL),
  ('authenticateUser','p','query','string','password',NULL),
  ('authenticateUser','t','query','string',NULL,'api')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('authenticateUser','object') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,content_type) VALUES ('authenticateUser','text/plain') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('logoutUser','object') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,content_type) VALUES ('logoutUser','text/plain') ON CONFLICT DO NOTHING;

-- ===== self-service
-- get/update me
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrieveSelfProfile', '/self/me', 'get', 'Return patron/user record for logged in user', 'OpenILS::OpenAPI::Controller::patron', 'deliver_user', 'eg_auth_token eg_user_id'),
  ('selfUpdateParts', '/self/me', 'patch', 'Update portions of the logged in user''s record', 'OpenILS::OpenAPI::Controller::patron', 'update_user_parts', 'eg_auth_token req.json')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('retrieveSelfProfile','au') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('selfUpdateParts','object') ON CONFLICT DO NOTHING;

-- get my standing penalties
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'selfActivePenalties',
    '/self/standing_penalties',
    'get',
    'Produces patron-visible penalty details for the authorized account',
    'OpenILS::OpenAPI::Controller::patron',
    'standing_penalties',
    'eg_auth_token eg_user_id "1"'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('selfActivePenalties','array','object') ON CONFLICT DO NOTHING; -- array of fleshed ausp

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'selfPenalty',
    '/self/standing_penalty/:penaltyid',
    'get',
    'Retrieve one penalty for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'standing_penalties',
    'eg_auth_token eg_user_id "1" param.penaltyid'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('selfPenalty','penaltyid','path','integer',TRUE) ON CONFLICT DO NOTHING;



-- manage my holds
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrieveSelfHolds', '/self/holds', 'get', 'Return unfilled holds for the authorized account', 'OpenILS::OpenAPI::Controller::hold', 'open_holds', 'eg_auth_token eg_user_id'),
  ('requestSelfHold', '/self/holds', 'post', 'Request a hold for the authorized account', 'OpenILS::OpenAPI::Controller::hold', 'request_hold', 'eg_auth_token eg_user_id req.json'),
  ('retrieveSelfHold', '/self/hold/:hold', 'get', 'Retrieve one hold for the logged in user', 'OpenILS::OpenAPI::Controller::hold', 'fetch_user_hold', 'eg_auth_token eg_user_id param.hold'),
  ('updateSelfHold', '/self/hold/:hold', 'patch', 'Update one hold for the logged in user', 'OpenILS::OpenAPI::Controller::hold', 'update_user_hold', 'eg_auth_token eg_user_id param.hold req.json'),
  ('cancelSelfHold', '/self/hold/:hold', 'delete', 'Cancel one hold for the logged in user', 'OpenILS::OpenAPI::Controller::hold', 'cancel_user_hold', 'eg_auth_token eg_user_id param.hold "6"')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES
  ('retrieveSelfHold','hold','path','integer',TRUE),
  ('updateSelfHold','hold','path','integer',TRUE),
  ('cancelSelfHold','hold','path','integer',TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrieveSelfHolds','array','object') ON CONFLICT DO NOTHING;


-- general xact list
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrieveSelfXacts',
    '/self/transactions/:state',
    'get',
    'Produces a list of transactions of the logged in user',
    'OpenILS::OpenAPI::Controller::patron',
    'transactions_by_state',
    'eg_auth_token eg_user_id state param.limit param.offset param.sort param.before param.after'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,default_value,required) VALUES
  ('retrieveSelfXacts','state','path','string',NULL,NULL,TRUE),
  ('retrieveSelfXacts','limit','query','integer',NULL,NULL,FALSE),
  ('retrieveSelfXacts','offset','query','integer',NULL,'0',FALSE),
  ('retrieveSelfXacts','sort','query','string',NULL,'desc',FALSE),
  ('retrieveSelfXacts','before','query','string','date-time',NULL,FALSE),
  ('retrieveSelfXacts','after','query','string','date-time',NULL,FALSE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrieveSelfXacts','array','object') ON CONFLICT DO NOTHING;

-- general xact detail
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrieveSelfXact',
    '/self/transaction/:id',
    'get',
    'Details of one transaction for the logged in user',
    'open-ils.actor',
    'open-ils.actor.user.transaction.fleshed.retrieve',
    'eg_auth_token param.id'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrieveSelfXact','id','path','integer',TRUE) ON CONFLICT DO NOTHING;


INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrieveSelfCircs', '/self/checkouts', 'get', 'Open Circs for the logged in user', 'open-ils.circ', 'open-ils.circ.actor.user.checked_out.atomic', 'eg_auth_token eg_user_id'),
  ('requestSelfCirc', '/self/checkouts', 'post', 'Attempt a circulation for the logged in user', 'OpenILS::OpenAPI::Controller::patron', 'checkout_item', 'eg_auth_token eg_user_id req.json')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrieveSelfCircs','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrieveSelfCircHistory',
    '/self/checkouts/history',
    'get',
    'Historical Circs for logged in user',
    'OpenILS::OpenAPI::Controller::patron',
    'circulation_history',
    'eg_auth_token eg_user_id param.limit param.offset param.sort param.before param.after'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,default_value) VALUES
  ('retrieveSelfCircHistory','limit','query','integer',NULL,NULL),
  ('retrieveSelfCircHistory','offset','query','integer',NULL,'0'),
  ('retrieveSelfCircHistory','sort','query','string',NULL,'desc'),
  ('retrieveSelfCircHistory','before','query','string','date-time',NULL),
  ('retrieveSelfCircHistory','after','query','string','date-time',NULL)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrieveSelfCircHistory','array','object') ON CONFLICT DO NOTHING;


INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrieveSelfCirc', '/self/checkout/:id', 'get', 'Retrieve one circulation for the logged in user', 'open-ils.actor', 'open-ils.actor.user.transaction.fleshed.retrieve', 'eg_auth_token param.id'),
  ('renewSelfCirc', '/self/checkout/:id', 'put', 'Renew one circulation for the logged in user', 'OpenILS::OpenAPI::Controller::patron', 'renew_circ', 'eg_auth_token param.id eg_user_id'),
  ('checkinSelfCirc', '/self/checkout/:id', 'delete', 'Check in one circulation for the logged in user', 'OpenILS::OpenAPI::Controller::patron', 'checkin_circ', 'eg_auth_token param.id eg_user_id')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES
  ('retrieveSelfCirc','id','path','integer',TRUE),
  ('renewSelfCirc','id','path','integer',TRUE),
  ('checkinSelfCirc','id','path','integer',TRUE)
ON CONFLICT DO NOTHING;

-- bib, item, and org methods
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrieveOrgList',
    '/org_units',
    'get',
    'List of org units',
    'OpenILS::OpenAPI::Controller::org',
    'flat_org_list',
    'every_param.field every_param.comparison every_param.value'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type) VALUES
  ('retrieveOrgList','field','query','string'),
  ('retrieveOrgList','comparison','query','string'),
  ('retrieveOrgList','value','query','string')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrieveOrgList','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrieveOneOrg',
    '/org_unit/:id',
    'get',
    'One org unit',
    'OpenILS::OpenAPI::Controller::org',
    'one_org',
    'param.id'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrieveOneOrg','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('retrieveOneOrg','aou') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name) VALUES (
    'retrieveFullOrgTree',
    '/org_tree',
    'get',
    'Full hierarchical tree of org units',
    'OpenILS::OpenAPI::Controller::org',
    'full_tree'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('retrieveFullOrgTree','aou') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrievePartialOrgTree',
    '/org_tree/:id',
    'get',
    'Partial hierarchical tree of org units starting from a specific org unit',
    'OpenILS::OpenAPI::Controller::org',
    'one_tree',
    'param.id'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrievePartialOrgTree','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('retrievePartialOrgTree','aou') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'createOneBib',
    '/bibs',
    'post',
    'Attempts to create a bibliographic record using MARCXML passed as the request content',
    'open-ils.cat',
    'open-ils.cat.biblio.record.xml.create',
    'eg_auth_token req.text param.sourcename'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type) VALUES ('createOneBib','sourcename','query','string') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('createOneBib','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'updateOneBib',
    '/bib/:id',
    'put',
    'Attempts to update a bibliographic record using MARCXML passed as the request content',
    'open-ils.cat',
    'open-ils.cat.biblio.record.marc.replace',
    'eg_auth_token param.id req.text param.sourcename'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('updateOneBib','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type) VALUES ('updateOneBib','sourcename','query','string') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('updateOneBib','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'deleteOneBib',
    '/bib/:id',
    'delete',
    'Attempts to delete a bibliographic record',
    'open-ils.cat',
    'open-ils.cat.biblio.record_entry.delete',
    'eg_auth_token param.id'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('deleteOneBib','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,validate) VALUES ('deleteOneBib','integer',FALSE) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'updateBREParts',
    '/bib/:id',
    'patch',
    'Attempts to update the biblio.record_entry metadata surrounding a bib record',
    'OpenILS::OpenAPI::Controller::bib',
    'update_bre_parts',
    'eg_auth_token param.id req.json'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('updateBREParts','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('updateBREParts','bre') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrieveOneBib',
    '/bib/:id',
    'get',
    'Retrieve a bibliographic record, either full biblio::record_entry object, or just the MARCXML',
    'OpenILS::OpenAPI::Controller::bib',
    'fetch_one_bib',
    'param.id'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrieveOneBib','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('retrieveOneBib','bre') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,content_type) VALUES ('retrieveOneBib','application/xml') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,content_type) VALUES ('retrieveOneBib','application/octet-stream') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrieveOneBibHoldings',
    '/bib/:id/holdings',
    'get',
    'Retrieve the holdings data for a bibliographic record',
    'OpenILS::OpenAPI::Controller::bib',
    'fetch_one_bib_holdings',
    'param.id'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,default_value,required) VALUES
  ('retrieveOneBibHoldings','id','path','integer',NULL,TRUE),
  ('retrieveOneBibHoldings','limit','query','integer',NULL,FALSE),
  ('retrieveOneBibHoldings','offset','query','integer','0',FALSE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrieveOneBibHoldings','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'bibDisplayFields',
    '/bib/:id/display_fields',
    'get',
    'Retrieve display-related data for a bibliographic record',
    'OpenILS::OpenAPI::Controller::bib',
    'fetch_one_bib_display_fields',
    'param.id req.text'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('bibDisplayFields','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('bibDisplayFields','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'newItems',
    '/items/fresh',
    'get',
    'Retrieve a list of newly added items',
    'OpenILS::OpenAPI::Controller::bib',
    'fetch_new_items',
    'param.limit param.offset param.maxage'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,default_value) VALUES ('newItems','limit','query','integer','0') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,default_value) VALUES ('newItems','offset','query','integer','100') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format) VALUES ('newItems','maxage','query','string','interval') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('newItems','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrieveItem',
    '/item/:barcode',
    'get',
    'Retrieve one item by its barcode',
    'OpenILS::OpenAPI::Controller::bib',
    'item_by_barcode',
    'param.barcode'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrieveItem','barcode','path','string',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,description,status,schema_type) VALUES ('retrieveItem','Item Lookup Failed','404','object') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('retrieveItem','acp') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'createItem',
    '/items',
    'post',
    'Create an item record',
    'OpenILS::OpenAPI::Controller::bib',
    'create_or_update_one_item',
    'eg_auth_token req.json'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,description,status) VALUES ('createItem','Item Creation Failed','400') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('createItem','acp') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'updateItem',
    '/item/:barcode',
    'patch',
    'Update a restricted set of item record fields',
    'OpenILS::OpenAPI::Controller::bib',
    'create_or_update_one_item',
    'eg_auth_token req.json param.barcode'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('updateItem','barcode','path','string',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,description,status) VALUES ('updateItem','Item Update Failed','400') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('updateItem','acp') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'deleteItem',
    '/item/:barcode',
    'delete',
    'Delete one item record',
    'OpenILS::OpenAPI::Controller::bib',
    'delete_one_item',
    'eg_auth_token param.barcode'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('deleteItem','barcode','path','string',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,description,status,schema_type) VALUES ('deleteItem','Item Deletion Failed','404','object') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('deleteItem','boolean') ON CONFLICT DO NOTHING;


-- === patron (non-self) methods
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'searchPatrons',
    '/patrons',
    'get',
    'List of patrons matching requested conditions',
    'OpenILS::OpenAPI::Controller::patron',
    'find_users',
    'eg_auth_token every_param.field every_param.comparison every_param.value param.limit param.offset'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type) VALUES
  ('searchPatrons','field','query','string'),
  ('searchPatrons','comparison','query','string'),
  ('searchPatrons','value','query','string')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,default_value) VALUES
  ('searchPatrons','offset','query','integer',NULL,'0'),
  ('searchPatrons','limit','query','integer',NULL,'100')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('searchPatrons','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'verifyUserCredentials',
    '/patrons/verify',
    'get',
    'Verify the credentials for a user account',
    'open-ils.actor',
    'open-ils.actor.verify_user_password',
    'eg_auth_token param.barcode param.usrname "" param.password'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,required) VALUES
  ('verifyUserCredentials','barcode','query','string',NULL,FALSE),
  ('verifyUserCredentials','usrname','query','string',NULL,FALSE),
  ('verifyUserCredentials','password','query','string','password',TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('verifyUserCredentials','boolean') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrievePatronProfile', '/patron/:userid', 'get', 'Return patron/user record for the requested user', 'OpenILS::OpenAPI::Controller::patron', 'deliver_user', 'eg_auth_token param.userid')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrievePatronProfile','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('retrievePatronProfile','au') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
  'patronIdByCardBarcode',
  '/patrons/by_barcode/:barcode/id',
  'get',
  'Retrieve patron id by barcode',
  'open-ils.actor',
  'open-ils.actor.user.retrieve_id_by_barcode_or_username',
  'eg_auth_token param.barcode'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronIdByCardBarcode','barcode','path','string',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('patronIdByCardBarcode','integer') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
  'patronIdByUsername',
  '/patrons/by_username/:username/id',
  'get',
  'Retrieve patron id by username',
  'open-ils.actor',
  'open-ils.actor.user.retrieve_id_by_barcode_or_username',
  'eg_auth_token "" param.username'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronIdByUsername','username','path','string',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('patronIdByUsername','integer') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
  'patronByCardBarcode',
  '/patrons/by_barcode/:barcode',
  'get',
  'Retrieve patron by barcode',
  'OpenILS::OpenAPI::Controller::patron',
  'user_by_identifier_string',
  'eg_auth_token param.barcode'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronByCardBarcode','barcode','path','string',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('patronByCardBarcode','au') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
  'patronByUsername',
  '/patrons/by_username/:username',
  'get',
  'Retrieve patron by username',
  'OpenILS::OpenAPI::Controller::patron',
  'user_by_identifier_string',
  'eg_auth_token "" param.username'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronByUsername','username','path','string',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('patronByUsername','au') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrievePatronCircHistory',
    '/patron/:userid/checkouts/history',
    'get',
    'Historical Circs for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'circulation_history',
    'eg_auth_token param.userid param.limit param.offset param.sort param.before param.after'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,default_value,required) VALUES
  ('retrievePatronCircHistory','userid','path','integer',NULL,NULL,TRUE),
  ('retrievePatronCircHistory','limit','query','integer',NULL,NULL,FALSE),
  ('retrievePatronCircHistory','offset','query','integer',NULL,'0',FALSE),
  ('retrievePatronCircHistory','sort','query','string',NULL,'desc',FALSE),
  ('retrievePatronCircHistory','before','query','string','date-time',NULL,FALSE),
  ('retrievePatronCircHistory','after','query','string','date-time',NULL,FALSE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrievePatronCircHistory','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrievePatronHolds', '/patron/:userid/holds', 'get', 'Retrieve unfilled holds for a patron', 'OpenILS::OpenAPI::Controller::hold', 'open_holds', 'eg_auth_token param.userid'),
  ('requestPatronHold', '/patron/:userid/holds', 'post', 'Request a hold for a patron', 'OpenILS::OpenAPI::Controller::hold', 'request_hold', 'eg_auth_token param.userid req.json'),
  ('retrievePatronHold','/patron/:userid/hold/:hold', 'get', 'Retrieve one hold for a patron', 'OpenILS::OpenAPI::Controller::hold', 'fetch_user_hold', 'eg_auth_token param.userid param.hold'),
  ('updatePatronHold', '/patron/:userid/hold/:hold', 'patch', 'Update one hold for a patron', 'OpenILS::OpenAPI::Controller::hold', 'update_user_hold', 'eg_auth_token param.userid param.hold req.json'),
  ('cancelPatronHold', '/patron/:userid/hold/:hold', 'delete', 'Cancel one hold for a patron', 'OpenILS::OpenAPI::Controller::hold', 'cancel_user_hold', 'eg_auth_token param.userid param.hold "6"')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES
  ('retrievePatronHolds','userid','path','integer',TRUE),
  ('retrievePatronHold','userid','path','integer',TRUE),
  ('retrievePatronHold','hold','path','integer',TRUE),
  ('requestPatronHold','userid','path','integer',TRUE),
  ('updatePatronHold','userid','path','integer',TRUE),
  ('updatePatronHold','hold','path','integer',TRUE),
  ('cancelPatronHold','userid','path','integer',TRUE),
  ('cancelPatronHold','hold','path','integer',TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrieveHoldPickupLocations', '/holds/pickup_locations', 'get', 'Retrieve all valid hold/reserve pickup locations', 'OpenILS::OpenAPI::Controller::hold', 'valid_hold_pickup_locations', '')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrieveHoldPickupLocations','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrieveHold', '/hold/:hold', 'get', 'Retrieve one hold object', 'open-ils.circ', 'open-ils.circ.hold.details.retrieve', 'eg_auth_token param.hold')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrieveHold','hold','path','integer',TRUE) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrievePatronXacts',
    '/patron/:userid/transactions/:state',
    'get',
    'Produces a list of transactions of the specified user',
    'OpenILS::OpenAPI::Controller::patron',
    'transactions_by_state',
    'eg_auth_token param.userid state param.limit param.offset param.sort param.before param.after'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,default_value,required) VALUES
  ('retrievePatronXacts','userid','path','integer',NULL,NULL,TRUE),
  ('retrievePatronXacts','state','path','string',NULL,NULL,TRUE),
  ('retrievePatronXacts','limit','query','integer',NULL,NULL,FALSE),
  ('retrievePatronXacts','offset','query','integer',NULL,'0',FALSE),
  ('retrievePatronXacts','sort','query','string',NULL,'desc',FALSE),
  ('retrievePatronXacts','before','query','string','date-time',NULL,FALSE),
  ('retrievePatronXacts','after','query','string','date-time',NULL,FALSE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrievePatronXacts','array','object') ON CONFLICT DO NOTHING;

-- general xact detail
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'retrievePatronXact',
    '/patron/:userid/transaction/:id',
    'get',
    'Details of one transaction for the specified user',
    'open-ils.actor',
    'open-ils.actor.user.transaction.fleshed.retrieve',
    'eg_auth_token param.id'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrievePatronXact','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrievePatronXact','id','path','integer',TRUE) ON CONFLICT DO NOTHING;


INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrievePatronCircs', '/patron/:userid/checkouts', 'get', 'Open Circs for a patron', 'open-ils.circ', 'open-ils.circ.actor.user.checked_out.atomic', 'eg_auth_token param.userid'),
  ('requestPatronCirc', '/patron/:userid/checkouts', 'post', 'Attempt a circulation for a patron', 'OpenILS::OpenAPI::Controller::patron', 'checkout_item', 'eg_auth_token param.userid req.json')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrievePatronCircs','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('requestPatronCirc','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrievePatronCircs','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrievePatronCirc', '/patron/:userid/checkout/:id', 'get', 'Retrieve one circulation for the specified user', 'open-ils.actor', 'open-ils.actor.user.transaction.fleshed.retrieve', 'eg_auth_token param.id'),
  ('renewPatronCirc', '/patron/:userid/checkout/:id', 'put', 'Renew one circulation for the specified user', 'OpenILS::OpenAPI::Controller::patron', 'renew_circ', 'eg_auth_token param.id param.userid'),
  ('checkinPatronCirc', '/patron/:userid/checkout/:id', 'delete', 'Check in one circulation for the specified user', 'OpenILS::OpenAPI::Controller::patron', 'checkin_circ', 'eg_auth_token param.id param.userid')
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES
  ('retrievePatronCirc','userid','path','integer',TRUE),
  ('retrievePatronCirc','id','path','integer',TRUE),
  ('renewPatronCirc','userid','path','integer',TRUE),
  ('renewPatronCirc','id','path','integer',TRUE),
  ('checkinPatronCirc','userid','path','integer',TRUE),
  ('checkinPatronCirc','id','path','integer',TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'patronATEvents',
    '/patron/:userid/triggered_events',
    'get',
    'Retrieve a list of A/T events for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'usr_at_events',
    'eg_auth_token param.userid param.limit param.offset param.before param.after every_param.hook'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,default_value,required) VALUES
  ('patronATEvents','userid','path','integer',NULL,NULL,TRUE),
  ('patronATEvents','limit','query','integer',NULL,'100',FALSE),
  ('patronATEvents','offset','query','integer',NULL,'0',FALSE),
  ('patronATEvents','before','query','string','date-time',NULL,FALSE),
  ('patronATEvents','after','query','string','date-time',NULL,FALSE),
  ('patronATEvents','hook','query','string',NULL,NULL,FALSE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('patronATEvents','array','integer') ON CONFLICT DO NOTHING; -- array of ausp ids

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'patronATEvent',
    '/patron/:userid/triggered_event/:eventid',
    'get',
    'Retrieve one penalty for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'usr_at_events',
    'eg_auth_token param.userid "1" "0" "" "" "" param.eventid'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronATEvent','eventid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronATEvent','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'patronActivePenalties',
    '/patron/:userid/standing_penalties',
    'get',
    'Retrieve all penalty details for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'standing_penalties',
    'eg_auth_token param.userid'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronActivePenalties','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('patronActivePenalties','array','integer') ON CONFLICT DO NOTHING; -- array of ausp ids

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'patronPenalty',
    '/patron/:userid/standing_penalty/:penaltyid',
    'get',
    'Retrieve one penalty for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'standing_penalties',
    'eg_auth_token param.userid "0" param.penaltyid'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronPenalty','penaltyid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronPenalty','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'patronActiveMessages',
    '/patron/:userid/messages',
    'get',
    'Retrieve all active message ids for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'usr_messages',
    'eg_auth_token param.userid "0"'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronActiveMessages','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('patronActiveMessages','array','integer') ON CONFLICT DO NOTHING; -- array of aum ids

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'patronMessage',
    '/patron/:userid/message/:msgid',
    'get',
    'Retrieve one message for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'usr_messages',
    'eg_auth_token param.userid "0" param.msgid'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronMessage','msgid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronMessage','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('patronMessage','aum') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'patronMessageUpdate',
    '/patron/:userid/message/:msgid',
    'patch',
    'Update one message for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'update_usr_message',
    'eg_auth_token eg_user_id param.userid param.msgid req.json'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronMessageUpdate','msgid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronMessageUpdate','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('patronMessageUpdate','aum') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'patronMessageArchive',
    '/patron/:userid/message/:msgid',
    'delete',
    'Archive one message for a patron',
    'OpenILS::OpenAPI::Controller::patron',
    'archive_usr_message',
    'eg_auth_token eg_user_id param.userid param.msgid'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronMessageArchive','msgid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('patronMessageArchive','userid','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type) VALUES ('patronMessageArchive','boolean') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'patronActivityLog',
    '/patron/:userid/activity',
    'get',
    'Retrieve patron activity (authen, authz, etc)',
    'OpenILS::OpenAPI::Controller::patron',
    'usr_activity',
    'eg_auth_token param.userid param.maxage param.limit param.offset param.sort'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,default_value,required) VALUES
  ('patronActivityLog','userid','path','integer',NULL,NULL,TRUE),
  ('patronActivityLog','limit','query','integer',NULL,'100',FALSE),
  ('patronActivityLog','offset','query','integer',NULL,'0',FALSE),
  ('patronActivityLog','sort','query','string',NULL,'desc',FALSE),
  ('patronActivityLog','maxage','query','string','date-time',NULL,FALSE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('patronActivityLog','array','object') ON CONFLICT DO NOTHING;

------- collections
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'collectionsPatronsOfInterest',
    '/collections/:shortname/users_of_interest',
    'get',
    'List of patrons to consider for collections based on the search criteria provided.',
    'open-ils.collections',
    'open-ils.collections.users_of_interest.retrieve',
    'eg_auth_token param.fine_age param.fine_amount param.shortname'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,required) VALUES
  ('collectionsPatronsOfInterest','shortname','path','string',NULL,TRUE),
  ('collectionsPatronsOfInterest','fine_age','query','integer',NULL,TRUE),
  ('collectionsPatronsOfInterest','fine_amount','query','string','money',TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items,validate) VALUES ('collectionsPatronsOfInterest','array','object',FALSE) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'collectionsPatronsOfInterestWarning',
    '/collections/:shortname/users_of_interest/warning',
    'get',
    'List of patrons with the PATRON_EXCEEDS_COLLECTIONS_WARNING penalty to consider for collections based on the search criteria provided.',
    'open-ils.collections',
    'open-ils.collections.users_of_interest.warning_penalty.retrieve',
    'eg_auth_token param.shortname param.min_age param.max_age'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,required) VALUES
  ('collectionsPatronsOfInterestWarning','shortname','path','string',NULL,TRUE),
  ('collectionsPatronsOfInterestWarning','min_age','query','string','date-time',FALSE),
  ('collectionsPatronsOfInterestWarning','max_age','query','string','date-time',FALSE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items,validate) VALUES ('collectionsPatronsOfInterestWarning','array','object',FALSE) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'collectionsGetPatronDetail',
    '/patron/:usrid/collections/:shortname',
    'get',
    'Get collections-related transaction details for a patron.',
    'open-ils.collections',
    'open-ils.collections.user_transaction_details.retrieve',
    'eg_auth_token param.start param.end param.shortname every_param.usrid'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,required) VALUES
  ('collectionsGetPatronDetail','usrid','path','integer',NULL,TRUE),
  ('collectionsGetPatronDetail','shortname','path','string',NULL,TRUE),
  ('collectionsGetPatronDetail','start','query','string','date-time',TRUE),
  ('collectionsGetPatronDetail','end','query','string','date-time',TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items,validate) VALUES ('collectionsGetPatronDetail','array','object',FALSE) ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'collectionsPutPatronInCollections',
    '/patron/:usrid/collections/:shortname',
    'post',
    'Put patron into collections.',
    'open-ils.collections',
    'open-ils.collections.put_into_collections',
    'eg_auth_token param.usrid param.shortname param.fee param.note'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,schema_format,required) VALUES
  ('collectionsPutPatronInCollections','usrid','path','integer',NULL,TRUE),
  ('collectionsPutPatronInCollections','shortname','path','string',NULL,TRUE),
  ('collectionsPutPatronInCollections','fee','query','string','money',FALSE),
  ('collectionsPutPatronInCollections','note','query','string',NULL,FALSE)
ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES (
    'collectionsRemovePatronFromCollections',
    '/patron/:usrid/collections/:shortname',
    'delete',
    'Remove patron from collections.',
    'open-ils.collections',
    'open-ils.collections.remove_from_collections',
    'eg_auth_token param.usrid param.shortname'
) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES
  ('collectionsRemovePatronFromCollections','usrid','path','integer',TRUE),
  ('collectionsRemovePatronFromCollections','shortname','path','string',TRUE)
ON CONFLICT DO NOTHING;


------- courses
INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('activeCourses', '/courses', 'get', 'Retrieve all courses used for course material reservation', 'OpenILS::OpenAPI::Controller::course', 'get_active_courses', 'eg_auth_token every_param.org')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type) VALUES ('activeCourses','org','query','integer') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('activeCourses','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('activeRoles', '/courses/public_role_users', 'get', 'Retrieve all public roles used for courses', 'OpenILS::OpenAPI::Controller::course', 'get_all_course_public_roles', 'eg_auth_token every_param.org')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type) VALUES ('activeRoles','org','query','integer') ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('activeRoles','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrieveCourse', '/course/:id', 'get', 'Retrieve one detailed course', 'OpenILS::OpenAPI::Controller::course', 'get_course_detail', 'eg_auth_token param.id')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrieveCourse','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,fm_type) VALUES ('retrieveCourse','acmc') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrieveCourseMaterials', '/course/:id/materials', 'get', 'Retrieve detailed materials for one course', 'OpenILS::OpenAPI::Controller::course', 'get_course_materials', 'param.id')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrieveCourseMaterials','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrieveCourseMaterials','array','object') ON CONFLICT DO NOTHING;

INSERT INTO openapi.endpoint (operation_id, path, http_method, summary, method_source, method_name, method_params) VALUES
  ('retrieveCourseUsers', '/course/:id/public_role_users', 'get', 'Retrieve detailed user list for one course', 'open-ils.courses', 'open-ils.courses.course_users.retrieve', 'param.id')
ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_param (endpoint,name,in_part,schema_type,required) VALUES ('retrieveCourseUsers','id','path','integer',TRUE) ON CONFLICT DO NOTHING;
INSERT INTO openapi.endpoint_response (endpoint,schema_type,array_items) VALUES ('retrieveCourseUsers','array','object') ON CONFLICT DO NOTHING;

--------- put likely stock endpoints into sets --------

INSERT INTO openapi.endpoint_set_endpoint_map (endpoint, endpoint_set)
  SELECT e.operation_id, s.name FROM openapi.endpoint e JOIN openapi.endpoint_set s ON (e.path LIKE '/'||RTRIM(s.name,'s')||'%')
ON CONFLICT DO NOTHING;

-- Check that all endpoints are in sets -- should return 0 rows
SELECT * FROM openapi.endpoint e WHERE NOT EXISTS (SELECT 1 FROM openapi.endpoint_set_endpoint_map WHERE endpoint = e.operation_id);

-- Global Fieldmapper property-filtering org and user settings
INSERT INTO config.settings_group (name,label) VALUES ('openapi','OpenAPI data access control');

INSERT INTO config.org_unit_setting_type (name,label,grp) VALUES ('REST.api.blacklist_properties','Globally filtered Fieldmapper properties','openapi');
INSERT INTO config.org_unit_setting_type (name,label,grp) VALUES ('REST.api.whitelist_properties','Globally whitelisted Fieldmapper properties','openapi');

UPDATE config.org_unit_setting_type
    SET update_perm = (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_OPENAPI' LIMIT 1)
    WHERE name IN ('REST.api.blacklist_properties','REST.api.whitelist_properties');

INSERT INTO config.usr_setting_type (name,label,grp) VALUES ('REST.api.whitelist_properties','Globally whitelisted Fieldmapper properties','openapi');
INSERT INTO config.usr_setting_type (name,label,grp) VALUES ('REST.api.blacklist_properties','Globally filtered Fieldmapper properties','openapi');


/* -- Some extra example permission setup, to allow (basically) readonly patron retrieve

INSERT INTO permission.perm_list (code,description) VALUES ('REST.api.patrons.detail.read','Permission meant to facilitate read-only patron-related API access');
INSERT INTO openapi.perm_set (name) values ('Patron Detail, Readonly');
INSERT INTO openapi.perm_set_perm_map (perm_set,perm) SELECT s.id, p.id FROM openapi.perm_set s, permission.perm_list p WHERE p.code IN ('REST.api', 'REST.api.patrons.detail.read') AND s.name='Patron RO';
INSERT INTO openapi.endpoint_perm_set_map (endpoint,perm_set) SELECT 'retrievePatronProfile', s.id FROM openapi.perm_set s WHERE s.name='Patron RO';

*/
COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
