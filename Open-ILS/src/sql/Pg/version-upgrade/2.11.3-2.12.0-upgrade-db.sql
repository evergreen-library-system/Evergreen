--Upgrade Script for 2.11.3 to 2.12.0
\set eg_version '''2.12.0'''
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1006', :eg_version);

-- This function is used to help clean up facet labels. Due to quirks in
-- MARC parsing, some facet labels may be generated with periods or commas
-- at the end.  This will strip a trailing commas off all the time, and
-- periods when they don't look like they are part of initials.
--      Smith, John    =>  no change
--      Smith, John,   =>  Smith, John
--      Smith, John.   =>  Smith, John
--      Public, John Q. => no change
CREATE OR REPLACE FUNCTION metabib.trim_trailing_punctuation ( TEXT ) RETURNS TEXT AS $$
DECLARE
    result    TEXT;
    last_char TEXT;
BEGIN
    result := $1;
    last_char = substring(result from '.$');

    IF last_char = ',' THEN
        result := substring(result from '^(.*),$');

    ELSIF last_char = '.' THEN
        IF substring(result from ' \w\.$') IS NULL THEN
            result := substring(result from '^(.*)\.$');
        END IF;
    END IF;

    RETURN result;

END;
$$ language 'plpgsql';

INSERT INTO config.index_normalizer (name, description, func, param_count) VALUES (
	'Trim Trailing Punctuation',
	'Eliminate extraneous trailing commas and periods in text',
	'metabib.trim_trailing_punctuation',
	0
);

INSERT INTO config.metabib_field_index_norm_map (field,norm,pos)
    SELECT  m.id,
            i.id,
            -1
      FROM  config.metabib_field m,
            config.index_normalizer i
      WHERE i.func = 'metabib.trim_trailing_punctuation'
            AND m.id IN (7,8,9,10);

SELECT evergreen.upgrade_deps_block_check('1007', :eg_version);

UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('audience', 'Audience', 'crad', 'label')
WHERE description IS NULL
AND name = 'audience';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('bib_level', 'Bib Level', 'crad', 'label')
WHERE description IS NULL
AND name = 'bib_level';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('item_form', 'Item Form', 'crad', 'label')
WHERE description IS NULL
AND name = 'item_form';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('item_lang', 'Language', 'crad', 'label')
WHERE description IS NULL
AND name = 'item_lang';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('lit_form', 'Literary Form', 'crad', 'label')
WHERE description IS NULL
AND name = 'lit_form';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('item_type', 'Item Type', 'crad', 'label')
WHERE description IS NULL
AND name = 'item_type';
UPDATE config.record_attr_definition
SET description = oils_i18n_gettext('vr_format', 'Video Format', 'crad', 'label')
WHERE description IS NULL
AND name = 'vr_format';

SELECT evergreen.upgrade_deps_block_check('1008', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.unaccent_and_squash ( IN arg text) RETURNS text
    IMMUTABLE STRICT AS $$
	BEGIN
	RETURN evergreen.lowercase(unaccent(regexp_replace(arg, '[\s[:punct:]]','','g')));
	END;
$$ LANGUAGE PLPGSQL;

SELECT evergreen.upgrade_deps_block_check('1009', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'acq.copy_status_on_receiving', 'acq',
    oils_i18n_gettext('acq.copy_status_on_receiving',
        'Initial status for received items',
        'coust', 'label'),
    oils_i18n_gettext('acq.copy_status_on_receiving',
        'Allows staff to designate a custom copy status on received lineitems.  Default status is "In Process".',
        'coust', 'description'),
    'link', 'ccs');

-- remove unused org unit setting for self checkout interface
SELECT evergreen.upgrade_deps_block_check('1010', :eg_version);

DELETE FROM actor.org_unit_setting WHERE name = 'circ.selfcheck.require_patron_password';

DELETE FROM config.org_unit_setting_type WHERE name = 'circ.selfcheck.require_patron_password';

DELETE FROM config.org_unit_setting_type_log WHERE field_name = 'circ.selfcheck.require_patron_password';

DELETE FROM permission.usr_perm_map WHERE perm IN (SELECT id FROM permission.perm_list WHERE code = 'UPDATE_ORG_UNIT_SETTING.circ.selfcheck.require_patron_password');

DELETE FROM permission.grp_perm_map WHERE perm IN (SELECT id FROM permission.perm_list WHERE code = 'UPDATE_ORG_UNIT_SETTING.circ.selfcheck.require_patron_password');

DELETE FROM permission.perm_list WHERE code = 'UPDATE_ORG_UNIT_SETTING.circ.selfcheck.require_patron_password';

SELECT evergreen.upgrade_deps_block_check('1011', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES
        ('circ.in_house_use.copy_alert',
         'circ',
         oils_i18n_gettext('circ.in_house_use.copy_alert',
             'Display copy alert for in-house-use',
             'coust', 'label'),
         oils_i18n_gettext('circ.in_house_use.copy_alert',
             'Display copy alert for in-house-use',
             'coust', 'description'),
         'bool'),
        ('circ.in_house_use.checkin_alert',
         'circ',
         oils_i18n_gettext('circ.in_house_use.checkin_alert',
             'Display copy location checkin alert for in-house-use',
             'coust', 'label'),
         oils_i18n_gettext('circ.in_house_use.checkin_alert',
             'Display copy location checkin alert for in-house-use',
             'coust', 'description'),
         'bool');

SELECT evergreen.upgrade_deps_block_check('1014', :eg_version);
-- this update of unapi.mmr_mra() removed since 1015 has a newer version
  
SELECT evergreen.upgrade_deps_block_check('1015', :eg_version);

CREATE OR REPLACE FUNCTION unapi.mmr_mra (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
        name attributes,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@mmr/' || $1 AS metarecord
        ),
        (SELECT XMLAGG(foo.y)
          FROM (
            WITH sourcelist AS (
                WITH aou AS (SELECT COALESCE(id, (evergreen.org_top()).id) AS id
                    FROM actor.org_unit WHERE shortname = $5 LIMIT 1)
                SELECT source
                FROM metabib.metarecord_source_map mmsm, aou
                WHERE metarecord = $1 AND (
                    EXISTS (
                        SELECT 1 FROM asset.opac_visible_copies
                        WHERE record = source AND circ_lib IN (
                            SELECT id FROM actor.org_unit_descendants(aou.id, $6))
                        LIMIT 1
                    )
                    OR EXISTS (SELECT 1 FROM located_uris(source, aou.id, $10) LIMIT 1)
                    OR EXISTS (SELECT 1 FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = mmsm.source LIMIT 1)
                )
            )
            SELECT  cmra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            cmra.attr AS name,
                            cmra.value AS "coded-value",
                            cmra.aid AS "cvmid",
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter,
                            cmra.source_list
                        ),
                        cmra.value
                    )
              FROM  (
                SELECT DISTINCT aid, attr, value, STRING_AGG(x.id::TEXT, ',') AS source_list
                  FROM (
                    SELECT  v.source AS id,
                            c.id AS aid,
                            c.ctype AS attr,
                            c.code AS value
                      FROM  metabib.record_attr_vector_list v
                            JOIN config.coded_value_map c ON ( c.id = ANY( v.vlist ) )
                    ) AS x
                    JOIN sourcelist ON (x.id = sourcelist.source)
                    GROUP BY 1, 2, 3
                ) AS cmra
                JOIN config.record_attr_definition rad ON (cmra.attr = rad.name)
                UNION ALL
            SELECT  umra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            umra.attr AS name,
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        umra.value
                    )
              FROM  (
                SELECT DISTINCT aid, attr, value
                  FROM (
                    SELECT  v.source AS id,
                            m.id AS aid,
                            m.attr AS attr,
                            m.value AS value
                      FROM  metabib.record_attr_vector_list v
                            JOIN metabib.uncontrolled_record_attr_value m ON ( m.id = ANY( v.vlist ) )
                    ) AS x
                    JOIN sourcelist ON (x.id = sourcelist.source)
                ) AS umra
                JOIN config.record_attr_definition rad ON (umra.attr = rad.name)
                ORDER BY 1

            )foo(id,y)
        )
    )
$F$ LANGUAGE SQL STABLE;
  
SELECT evergreen.upgrade_deps_block_check('1016', :eg_version);

INSERT INTO config.biblio_fingerprint (name, xpath, format)
    VALUES (
        'PartName',
        '//mods32:mods/mods32:titleInfo/mods32:partName',
        'mods32'
    );

INSERT INTO config.biblio_fingerprint (name, xpath, format)
    VALUES (
        'PartNumber',
        '//mods32:mods/mods32:titleInfo/mods32:partNumber',
        'mods32'
    );

SELECT evergreen.upgrade_deps_block_check('1017', :eg_version);

CREATE OR REPLACE FUNCTION biblio.extract_fingerprint ( marc text ) RETURNS TEXT AS $func$
DECLARE
	idx		config.biblio_fingerprint%ROWTYPE;
	xfrm		config.xml_transform%ROWTYPE;
	prev_xfrm	TEXT;
	transformed_xml	TEXT;
	xml_node	TEXT;
	xml_node_list	TEXT[];
	raw_text	TEXT;
    output_text TEXT := '';
BEGIN

    IF marc IS NULL OR marc = '' THEN
        RETURN NULL;
    END IF;

	-- Loop over the indexing entries
	FOR idx IN SELECT * FROM config.biblio_fingerprint ORDER BY format, id LOOP

		SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

		-- See if we can skip the XSLT ... it's expensive
		IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
			-- Can't skip the transform
			IF xfrm.xslt <> '---' THEN
				transformed_xml := oils_xslt_process(marc,xfrm.xslt);
			ELSE
				transformed_xml := marc;
			END IF;

			prev_xfrm := xfrm.name;
		END IF;

		raw_text := COALESCE(
            naco_normalize(
                ARRAY_TO_STRING(
                    oils_xpath(
                        '//text()',
                        (oils_xpath(
                            idx.xpath,
                            transformed_xml,
                            ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] 
                        ))[1]
                    ),
                    ''
                )
            ),
            ''
        );

        raw_text := REGEXP_REPLACE(raw_text, E'\\[.+?\\]', E'');
        raw_text := REGEXP_REPLACE(raw_text, E'\\mthe\\M|\\man?d?d\\M', E'', 'g'); -- arg! the pain!

        IF idx.first_word IS TRUE THEN
            raw_text := REGEXP_REPLACE(raw_text, E'^(\\w+).*?$', E'\\1');
        END IF;

		output_text := output_text || idx.name || ':' ||
					   REGEXP_REPLACE(raw_text, E'\\s+', '', 'g') || ' ';

	END LOOP;

    RETURN BTRIM(output_text);

END;
$func$ LANGUAGE PLPGSQL;

SELECT evergreen.upgrade_deps_block_check('1019', :eg_version);

CREATE OR REPLACE FUNCTION
    action.hold_request_regen_copy_maps(
        hold_id INTEGER, copy_ids INTEGER[]) RETURNS VOID AS $$
    DELETE FROM action.hold_copy_map WHERE hold = $1;
    INSERT INTO action.hold_copy_map (hold, target_copy) SELECT $1, UNNEST($2);
$$ LANGUAGE SQL;

-- DATA

INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'circ.holds.retarget_interval',
    oils_i18n_gettext(
        'circ.holds.retarget_interval',
        'Holds Retarget Interval', 
        'cgf',
        'label'
    ),
    '24h',
    TRUE
);

SELECT evergreen.upgrade_deps_block_check('1020', :eg_version);

CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_setting_batch_by_org(
    setting_name TEXT, org_ids INTEGER[]) 
    RETURNS SETOF actor.org_unit_setting AS 
$FUNK$
DECLARE
    setting RECORD;
    org_id INTEGER;
BEGIN
    /*  Returns one actor.org_unit_setting row per org unit ID provided.
        When no setting exists for a given org unit, the setting row
        will contain all empty values. */
    FOREACH org_id IN ARRAY org_ids LOOP
        SELECT INTO setting * FROM 
            actor.org_unit_ancestor_setting(setting_name, org_id);
        RETURN NEXT setting;
    END LOOP;
    RETURN;
END;
$FUNK$ LANGUAGE plpgsql STABLE;

SELECT evergreen.upgrade_deps_block_check('1021', :eg_version);

-- Add missing permissions noted in LP 1517137 adjusting those added manually and ignoring those already in place.

DO $$
DECLARE fixperm TEXT[3];
DECLARE modify BOOLEAN;
DECLARE permid BIGINT;
DECLARE oldid BIGINT;
BEGIN

FOREACH fixperm SLICE 1 IN ARRAY ARRAY[
  ['564', 'MARK_ITEM_CATALOGING', 'Allow a user to mark an item status as ''cataloging'''],
  ['565', 'MARK_ITEM_DAMAGED', 'Allow a user to mark an item status as ''damaged'''],
  ['566', 'MARK_ITEM_DISCARD', 'Allow a user to mark an item status as ''discard'''],
  ['567', 'MARK_ITEM_RESERVES', 'Allow a user to mark an item status as ''reserves'''],
  ['568', 'ADMIN_ORG_UNIT_SETTING_TYPE_LOG', 'Allow a user to modify the org unit settings log'],
  ['570', 'CREATE_POP_BADGE', 'Allow a user to create a new popularity badge'],
  ['571', 'DELETE_POP_BADGE', 'Allow a user to delete a popularity badge'],
  ['572', 'UPDATE_POP_BADGE', 'Allow a user to modify a popularity badge'],
  ['573', 'CREATE_POP_PARAMETER', 'Allow a user to create a popularity badge parameter'],
  ['574', 'DELETE_POP_PARAMETER', 'Allow a user to delete a popularity badge parameter'],
  ['575', 'UPDATE_POP_PARAMETER', 'Allow a user to modify a popularity badge parameter'],
  ['576', 'CREATE_AUTHORITY_RECORD', 'Allow a user to create an authority record'],
  ['577', 'DELETE_AUTHORITY_RECORD', 'Allow a user to delete an authority record'],
  ['578', 'UPDATE_AUTHORITY_RECORD', 'Allow a user to modify an authority record'],
  ['579', 'CREATE_AUTHORITY_CONTROL_SET', 'Allow a user to create an authority control set'],
  ['580', 'DELETE_AUTHORITY_CONTROL_SET', 'Allow a user to delete an authority control set'],
  ['581', 'UPDATE_AUTHORITY_CONTROL_SET', 'Allow a user to modify an authority control set'],
  ['582', 'ACTOR_USER_DELETE_OPEN_XACTS.override', 'Override the ACTOR_USER_DELETE_OPEN_XACTS event'],
  ['583', 'PATRON_EXCEEDS_LOST_COUNT.override', 'Override the PATRON_EXCEEDS_LOST_COUNT event'],
  ['584', 'MAX_HOLDS.override', 'Override the MAX_HOLDS event'],
  ['585', 'ITEM_DEPOSIT_REQUIRED.override', 'Override the ITEM_DEPOSIT_REQUIRED event'],
  ['586', 'ITEM_DEPOSIT_PAID.override', 'Override the ITEM_DEPOSIT_PAID event'],
  ['587', 'COPY_STATUS_LOST_AND_PAID.override', 'Override the COPY_STATUS_LOST_AND_PAID event'],
  ['588', 'ITEM_NOT_HOLDABLE.override', 'Override the ITEM_NOT_HOLDABLE event'],
  ['589', 'ITEM_RENTAL_FEE_REQUIRED.override', 'Override the ITEM_RENTAL_FEE_REQUIRED event']
]
LOOP
  permid := CAST (fixperm[1] AS BIGINT);
  -- Has this permission already been manually applied at the expected id?
  PERFORM * FROM permission.perm_list WHERE id = permid;
  IF NOT FOUND THEN
    UPDATE permission.perm_list SET code = code || '_local' WHERE code = fixperm[2] AND id > 1000 RETURNING id INTO oldid;
    modify := FOUND;

    INSERT INTO permission.perm_list (id, code, description) VALUES (permid, fixperm[2], fixperm[3]);

    -- Several of these are rather unlikely for these particular permissions but safer > sorry.
    IF modify THEN
      UPDATE permission.grp_perm_map SET perm = permid WHERE perm = oldid;
      UPDATE config.org_unit_setting_type SET update_perm = permid WHERE update_perm = oldid;
      UPDATE permission.usr_object_perm_map SET perm = permid WHERE perm = oldid;
      UPDATE permission.usr_perm_map SET perm = permid WHERE perm = oldid;
      UPDATE config.org_unit_setting_type SET view_perm = permid WHERE view_perm = oldid;
      UPDATE config.z3950_source SET use_perm = permid WHERE use_perm = oldid;
      DELETE FROM permission.perm_list WHERE id = oldid;
    END IF;
  END IF;
END LOOP;

END$$;

SELECT evergreen.upgrade_deps_block_check('1022', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.merge_record_xml_using_profile ( incoming_marc TEXT, existing_marc TEXT, merge_profile_id BIGINT ) RETURNS TEXT AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    target_marc     TEXT;
    source_marc     TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    IF existing_marc IS NULL OR incoming_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for source or target records';
        RETURN NULL;
    END IF;

    IF merge_profile_id IS NOT NULL THEN
        SELECT * INTO merge_profile FROM vandelay.merge_profile WHERE id = merge_profile_id;
        IF FOUND THEN
            dyn_profile.add_rule := COALESCE(merge_profile.add_spec,'');
            dyn_profile.strip_rule := COALESCE(merge_profile.strip_spec,'');
            dyn_profile.replace_rule := COALESCE(merge_profile.replace_spec,'');
            dyn_profile.preserve_rule := COALESCE(merge_profile.preserve_spec,'');
        ELSE
            -- RAISE NOTICE 'merge profile not found';
            RETURN NULL;
        END IF;
    ELSE
        -- RAISE NOTICE 'no merge profile specified';
        RETURN NULL;
    END IF;

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN NULL;
    END IF;

    IF dyn_profile.replace_rule = '' AND dyn_profile.preserve_rule = '' AND dyn_profile.add_rule = '' AND dyn_profile.strip_rule = '' THEN
        -- Since we have nothing to do, just return a target record as is
        RETURN existing_marc;
    ELSIF dyn_profile.preserve_rule <> '' THEN
        source_marc = existing_marc;
        target_marc = incoming_marc;
        replace_rule = dyn_profile.preserve_rule;
    ELSE
        source_marc = incoming_marc;
        target_marc = existing_marc;
        replace_rule = dyn_profile.replace_rule;
    END IF;

    RETURN vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule );

END;
$$ LANGUAGE PLPGSQL;

SELECT evergreen.upgrade_deps_block_check('1023', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
(
    'cat.default_merge_profile', 'cat',
    oils_i18n_gettext(
        'cat.default_merge_profile',
        'Default Merge Profile (Z39.50 and Record Buckets)',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'cat.default_merge_profile',
        'Default merge profile to use during Z39.50 imports and record bucket merges',
        'coust',
        'description'
    ),
    'link',
    'vmp'
);

SELECT evergreen.upgrade_deps_block_check('1024', :eg_version);

-- Add new column "rtl" with default of false
ALTER TABLE config.i18n_locale ADD COLUMN rtl BOOL NOT NULL DEFAULT FALSE;

SELECT evergreen.upgrade_deps_block_check('1025', :eg_version);

-- Add Arabic (Jordan) to i18n_locale table as a stock language option
INSERT INTO config.i18n_locale (code,marc_code,name,description,rtl)
    VALUES ('ar-JO', 'ara', oils_i18n_gettext('ar-JO', 'Arabic (Jordan)', 'i18n_l', 'name'),
        oils_i18n_gettext('ar-JO', 'Arabic (Jordan)', 'i18n_l', 'description'), 'true');

SELECT evergreen.upgrade_deps_block_check('1026', :eg_version);

INSERT INTO config.metabib_field ( id, field_class, name, label, 
     format, xpath, search_field, browse_field, authority_xpath, joiner ) VALUES
    (34, 'subject', 'topic_browse', oils_i18n_gettext(34, 'Topic Browse', 'cmf', 'label'), 
     'mods32', $$//mods32:mods/mods32:subject[local-name(./*[1]) = "topic"]$$, FALSE, TRUE, '//@xlink:href', ' -- ' ); -- /* to fool vim */;

INSERT INTO config.metabib_field ( id, field_class, name, label, 
     format, xpath, search_field, browse_field, authority_xpath, joiner ) VALUES
    (35, 'subject', 'geographic_browse', oils_i18n_gettext(35, 'Geographic Name Browse', 'cmf', 'label'), 
     'mods32', $$//mods32:mods/mods32:subject[local-name(./*[1]) = "geographic"]$$, FALSE, TRUE, '//@xlink:href', ' -- ' ); -- /* to fool vim */;

INSERT INTO config.metabib_field ( id, field_class, name, label, 
     format, xpath, search_field, browse_field, authority_xpath, joiner ) VALUES
    (36, 'subject', 'temporal_browse', oils_i18n_gettext(36, 'Temporal Term Browse', 'cmf', 'label'), 
     'mods32', $$//mods32:mods/mods32:subject[local-name(./*[1]) = "temporal"]$$, FALSE, TRUE, '//@xlink:href', ' -- ' ); -- /* to fool vim */;

INSERT INTO config.metabib_field_index_norm_map (field,norm)
    SELECT  m.id,
            i.id
      FROM  config.metabib_field m,
        config.index_normalizer i
      WHERE i.func IN ('naco_normalize')
            AND m.id IN (34, 35, 36);

UPDATE config.metabib_field
SET browse_field = FALSE
WHERE field_class = 'subject' AND name = 'topic'
AND id = 14;
UPDATE config.metabib_field
SET browse_field = FALSE
WHERE field_class = 'subject' AND name = 'geographic'
AND id = 13;
UPDATE config.metabib_field
SET browse_field = FALSE
WHERE field_class = 'subject' AND name = 'temporal'
AND id = 11;

UPDATE authority.control_set_bib_field_metabib_field_map
SET metabib_field = 34
WHERE metabib_field = 14;
UPDATE authority.control_set_bib_field_metabib_field_map
SET metabib_field = 35
WHERE metabib_field = 13;
UPDATE authority.control_set_bib_field_metabib_field_map
SET metabib_field = 36
WHERE metabib_field = 11;

SELECT evergreen.upgrade_deps_block_check('1027', :eg_version);

INSERT INTO config.settings_group (name, label)
    VALUES ('ebook_api', 'Ebook API Integration');

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype) 
VALUES (
    'ebook_api.oneclickdigital.library_id',
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.library_id',
        'OneClickdigital Library ID',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.library_id',
        'Identifier assigned to this library by OneClickdigital',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.oneclickdigital.basic_token',
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.basic_token',
        'OneClickdigital Basic Token',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.basic_token',
        'Basic token for client authentication with OneClickdigital API (supplied by OneClickdigital)',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype) 
VALUES (
    'ebook_api.overdrive.discovery_base_uri',
    oils_i18n_gettext(
        'ebook_api.overdrive.discovery_base_uri',
        'OverDrive Discovery API Base URI',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.discovery_base_uri',
        'Base URI for OverDrive Discovery API (defaults to https://api.overdrive.com/v1). Using HTTPS here is strongly encouraged.',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.circulation_base_uri',
    oils_i18n_gettext(
        'ebook_api.overdrive.circulation_base_uri',
        'OverDrive Circulation API Base URI',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.circulation_base_uri',
        'Base URI for OverDrive Circulation API (defaults to https://patron.api.overdrive.com/v1). Using HTTPS here is strongly encouraged.',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.account_id',
    oils_i18n_gettext(
        'ebook_api.overdrive.account_id',
        'OverDrive Account ID',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.account_id',
        'Account ID (a.k.a. Library ID) for this library, as assigned by OverDrive',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.websiteid',
    oils_i18n_gettext(
        'ebook_api.overdrive.websiteid',
        'OverDrive Website ID',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.websiteid',
        'Website ID for this library, as assigned by OverDrive',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.authorizationname',
    oils_i18n_gettext(
        'ebook_api.overdrive.authorizationname',
        'OverDrive Authorization Name',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.authorizationname',
        'Authorization name for this library, as assigned by OverDrive',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.basic_token',
    oils_i18n_gettext(
        'ebook_api.overdrive.basic_token',
        'OverDrive Basic Token',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.basic_token',
        'Basic token for client authentication with OverDrive API (supplied by OverDrive)',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.granted_auth_redirect_uri',
    oils_i18n_gettext(
        'ebook_api.overdrive.granted_auth_redirect_uri',
        'OverDrive Granted Authorization Redirect URI',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.granted_auth_redirect_uri',
        'URI provided to OverDrive for use with granted authorization',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
),(
    'ebook_api.overdrive.password_required',
    oils_i18n_gettext(
        'ebook_api.overdrive.password_required',
        'OverDrive Password Required',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.overdrive.password_required',
        'Does this library require a password when authenticating patrons with the OverDrive API?',
        'coust',
        'description'
    ),
    'ebook_api',
    'bool'
);

SELECT evergreen.upgrade_deps_block_check('1029', :eg_version); -- csharp/gmcharlt

UPDATE config.index_normalizer SET description = 'Apply NACO normalization rules to the extracted text.  See https://www.loc.gov/aba/pcc/naco/normrule-2.html for details.' WHERE func = 'naco_normalize';
UPDATE config.index_normalizer SET description = 'Apply NACO normalization rules to the extracted text, retaining the first comma.  See https://www.loc.gov/aba/pcc/naco/normrule-2.html for details.' WHERE func = 'naco_normalize_keep_comma';

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = shift;
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # https://www.loc.gov/aba/pcc/naco/documents/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;

    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}]['/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

-- Currently, the only difference from naco_normalize is that search_normalize
-- turns apostrophes into spaces, while naco_normalize collapses them.
CREATE OR REPLACE FUNCTION public.search_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = shift;
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # https://www.loc.gov/aba/pcc/naco/documents/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;

    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}][/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

SELECT evergreen.upgrade_deps_block_check('1030', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.oils_xslt_process(TEXT, TEXT) RETURNS TEXT AS $func$
  use strict;

  use XML::LibXSLT;
  use XML::LibXML;

  my $doc = shift;
  my $xslt = shift;

  # The following approach uses the older XML::LibXML 1.69 / XML::LibXSLT 1.68
  # methods of parsing XML documents and stylesheets, in the hopes of broader
  # compatibility with distributions
  my $parser = $_SHARED{'_xslt_process'}{parsers}{xml} || XML::LibXML->new();

  # Cache the XML parser, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xml} = $parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xml});

  my $xslt_parser = $_SHARED{'_xslt_process'}{parsers}{xslt} || XML::LibXSLT->new();

  # Cache the XSLT processor, if we do not already have one
  $_SHARED{'_xslt_process'}{parsers}{xslt} = $xslt_parser
    unless ($_SHARED{'_xslt_process'}{parsers}{xslt});

  my $stylesheet = $_SHARED{'_xslt_process'}{stylesheets}{$xslt} ||
    $xslt_parser->parse_stylesheet( $parser->parse_string($xslt) );

  $_SHARED{'_xslt_process'}{stylesheets}{$xslt} = $stylesheet
    unless ($_SHARED{'_xslt_process'}{stylesheets}{$xslt});

  return $stylesheet->output_as_chars(
    $stylesheet->transform(
      $parser->parse_string($doc)
    )
  );

$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

SELECT evergreen.upgrade_deps_block_check('1031', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype) 
VALUES (
    'ebook_api.oneclickdigital.base_uri',
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.base_uri',
        'OneClickdigital Base URI',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ebook_api.oneclickdigital.base_uri',
        'Base URI for OneClickdigital API (defaults to https://api.oneclickdigital.com/v1). Using HTTPS here is strongly encouraged.',
        'coust',
        'description'
    ),
    'ebook_api',
    'string'
);

COMMIT;

\qecho Running some data updates outside of the main transaction
\qecho =========================================================
\qecho Update some indexes on actor.usr
REINDEX INDEX actor.actor_usr_first_given_name_unaccent_idx;
REINDEX INDEX actor.actor_usr_second_given_name_unaccent_idx;
REINDEX INDEX actor.actor_usr_family_name_unaccent_idx;

\qecho Recalculating bib fingerprints; this may take a while
ALTER TABLE biblio.record_entry DISABLE TRIGGER USER;
UPDATE biblio.record_entry SET fingerprint = biblio.extract_fingerprint(marc) WHERE NOT deleted;
ALTER TABLE biblio.record_entry ENABLE TRIGGER USER;

\qecho Remapping metarecords
SELECT metabib.remap_metarecord_for_bib(id, fingerprint)
FROM biblio.record_entry
WHERE NOT deleted;

\qecho Running a browse and reingest of your bib records. It may take a while.
\qecho You may cancel now without losing the effect of the rest of the
\qecho upgrade script, and arrange the reingest later.
\qecho .
SELECT metabib.reingest_metabib_field_entries(id, FALSE, FALSE, TRUE)
    FROM biblio.record_entry;

