/*
 * Copyright (C) 2007-2010  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */


DROP SCHEMA IF EXISTS search CASCADE;

BEGIN;

CREATE SCHEMA search;

CREATE OR REPLACE FUNCTION evergreen.pg_statistics (tab TEXT, col TEXT) RETURNS TABLE(element TEXT, frequency INT) AS $$
BEGIN
    -- This query will die on PG < 9.2, but the function can be created. We just won't use it where we can't.
    RETURN QUERY
        SELECT  e,
                f
          FROM  (SELECT ROW_NUMBER() OVER (),
                        (f * 100)::INT AS f
                  FROM  (SELECT UNNEST(most_common_elem_freqs) AS f
                          FROM  pg_stats
                          WHERE tablename = tab
                                AND attname = col
                        )x
                ) AS f
                JOIN (SELECT ROW_NUMBER() OVER (),
                             e
                       FROM (SELECT UNNEST(most_common_elems::text::text[]) AS e
                              FROM  pg_stats
                              WHERE tablename = tab
                                    AND attname = col
                            )y
                ) AS elems USING (row_number);
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.query_int_wrapper (INT[],TEXT) RETURNS BOOL AS $$
BEGIN
    RETURN $1 @@ $2::query_int;
END;
$$ LANGUAGE PLPGSQL STABLE;

CREATE TABLE search.relevance_adjustment (
    id          SERIAL  PRIMARY KEY,
    active      BOOL    NOT NULL DEFAULT TRUE,
    field       INT     NOT NULL REFERENCES config.metabib_field (id) DEFERRABLE INITIALLY DEFERRED,
    bump_type   TEXT    NOT NULL CHECK (bump_type IN ('word_order','first_word','full_match')),
    multiplier  NUMERIC NOT NULL DEFAULT 1.0
);
CREATE UNIQUE INDEX bump_once_per_field_idx ON search.relevance_adjustment ( field, bump_type );

CREATE OR REPLACE FUNCTION search.facets_for_record_set(ignore_facet_classes text[], hits bigint[]) RETURNS TABLE(id integer, value text, count bigint)
AS $f$
    SELECT id, value, count
      FROM (
        SELECT  mfae.field AS id,
                mfae.value,
                COUNT(DISTINCT mfae.source),
                row_number() OVER (
                    PARTITION BY mfae.field ORDER BY COUNT(DISTINCT mfae.source) DESC
                ) AS rownum
          FROM  metabib.facet_entry mfae
                JOIN config.metabib_field cmf ON (cmf.id = mfae.field)
          WHERE mfae.source = ANY ($2)
                AND cmf.facet_field
                AND cmf.field_class NOT IN (SELECT * FROM unnest($1))
          GROUP by 1, 2
      ) all_facets
      WHERE rownum <= (
        SELECT COALESCE(
            (SELECT value::INT FROM config.global_flag WHERE name = 'search.max_facets_per_field' AND enabled),
            1000
        )
      );
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.facets_for_metarecord_set(ignore_facet_classes TEXT[], hits BIGINT[]) RETURNS TABLE (id INT, value TEXT, count BIGINT) AS $$
    SELECT id, value, count FROM (
        SELECT mfae.field AS id,
               mfae.value,
               COUNT(DISTINCT mmrsm.metarecord),
               row_number() OVER (
                PARTITION BY mfae.field ORDER BY COUNT(distinct mmrsm.metarecord) DESC
               ) AS rownum
        FROM metabib.facet_entry mfae
        JOIN metabib.metarecord_source_map mmrsm ON (mfae.source = mmrsm.source)
        JOIN config.metabib_field cmf ON (cmf.id = mfae.field)
        WHERE mmrsm.metarecord IN (SELECT * FROM unnest($2))
        AND cmf.facet_field
        AND cmf.field_class NOT IN (SELECT * FROM unnest($1))
        GROUP by 1, 2
    ) all_facets
    WHERE rownum <= (SELECT COALESCE((SELECT value::INT FROM config.global_flag WHERE name = 'search.max_facets_per_field' AND enabled), 1000));
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.calculate_visibility_attribute ( value INT, attr TEXT ) RETURNS INT AS $f$
SELECT  ((CASE $2

            WHEN 'luri_org'         THEN 0 -- "b" attr
            WHEN 'bib_source'       THEN 1 -- "b" attr

            WHEN 'copy_flags'       THEN 0 -- "c" attr
            WHEN 'owning_lib'       THEN 1 -- "c" attr
            WHEN 'circ_lib'         THEN 2 -- "c" attr
            WHEN 'status'           THEN 3 -- "c" attr
            WHEN 'location'         THEN 4 -- "c" attr
            WHEN 'location_group'   THEN 5 -- "c" attr

        END) << 28 ) | $1;

/* copy_flags bit positions, LSB-first:

 0: asset.copy.opac_visible


   When adding flags, you must update asset.all_visible_flags()

   Because bib and copy values are stored separately, we can reuse
   shifts, saving us some space. We could probably take back a bit
   too, but I'm not sure its worth squeezing that last one out. We'd
   be left with just 2 slots for copy attrs, rather than 10.
*/

$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION search.calculate_visibility_attribute_list ( attr TEXT, value INT[] ) RETURNS INT[] AS $f$
    SELECT ARRAY_AGG(search.calculate_visibility_attribute(x, $1)) FROM UNNEST($2) AS X;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION search.calculate_visibility_attribute_test ( attr TEXT, value INT[], negate BOOL DEFAULT FALSE ) RETURNS TEXT AS $f$
    SELECT  CASE WHEN $3 THEN '!' ELSE '' END || '(' || ARRAY_TO_STRING(search.calculate_visibility_attribute_list($1,$2),'|') || ')';
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.calculate_copy_visibility_attribute_set ( copy_id BIGINT ) RETURNS INT[] AS $f$
DECLARE
    copy_row    asset.copy%ROWTYPE;
    lgroup_map  asset.copy_location_group_map%ROWTYPE;
    attr_set    INT[] := '{}'::INT[];
BEGIN
    SELECT * INTO copy_row FROM asset.copy WHERE id = copy_id;

    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.opac_visible::INT, 'copy_flags');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.circ_lib, 'circ_lib');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.status, 'status');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.location, 'location');

    SELECT  ARRAY_APPEND(
                attr_set,
                search.calculate_visibility_attribute(owning_lib, 'owning_lib')
            ) INTO attr_set
      FROM  asset.call_number
      WHERE id = copy_row.call_number;

    FOR lgroup_map IN SELECT * FROM asset.copy_location_group_map WHERE location = copy_row.location LOOP
        attr_set := attr_set || search.calculate_visibility_attribute(lgroup_map.lgroup, 'location_group');
    END LOOP;

    RETURN attr_set;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.calculate_bib_visibility_attribute_set ( bib_id BIGINT, new_source INT DEFAULT NULL, force_source BOOL DEFAULT FALSE ) RETURNS INT[] AS $f$
DECLARE
    bib_row     biblio.record_entry%ROWTYPE;
    cn_row      asset.call_number%ROWTYPE;
    attr_set    INT[] := '{}'::INT[];
BEGIN
    SELECT * INTO bib_row FROM biblio.record_entry WHERE id = bib_id;

    IF force_source THEN
        IF new_source IS NOT NULL THEN
            attr_set := attr_set || search.calculate_visibility_attribute(new_source, 'bib_source');
        END IF;
    ELSIF bib_row.source IS NOT NULL THEN
        attr_set := attr_set || search.calculate_visibility_attribute(bib_row.source, 'bib_source');
    END IF;

    FOR cn_row IN
        SELECT  *
          FROM  asset.call_number
          WHERE record = bib_id
                AND label = '##URI##'
                AND NOT deleted
    LOOP
        attr_set := attr_set || search.calculate_visibility_attribute(cn_row.owning_lib, 'luri_org');
    END LOOP;

    RETURN attr_set;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    ocn     asset.call_number%ROWTYPE;
    ncn     asset.call_number%ROWTYPE;
    cid     BIGINT;
    dobib   BOOL;
BEGIN

    SELECT enabled = FALSE INTO dobib FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc';

    IF TG_TABLE_NAME = 'peer_bib_copy_map' THEN -- Only needs ON INSERT OR DELETE, so handle separately
        IF TG_OP = 'INSERT' THEN
            INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                NEW.peer_record,
                NEW.target_copy,
                asset.calculate_copy_visibility_attribute_set(NEW.target_copy)
            );

            RETURN NEW;
        ELSIF TG_OP = 'DELETE' THEN
            DELETE FROM asset.copy_vis_attr_cache
              WHERE record = OLD.peer_record AND target_copy = OLD.target_copy;

            RETURN OLD;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN -- Handles ON INSERT. ON UPDATE is below.
        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            SELECT * INTO ncn FROM asset.call_number cn WHERE id = NEW.call_number;
            INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                ncn.record,
                NEW.id,
                asset.calculate_copy_visibility_attribute_set(NEW.id)
            );
        ELSIF TG_TABLE_NAME = 'record_entry' THEN
            NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id, NEW.source, TRUE);
        ELSIF TG_TABLE_NAME = 'call_number' AND NEW.label = '##URI##' AND dobib THEN -- New located URI
            UPDATE  biblio.record_entry
              SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(NEW.record)
              WHERE id = NEW.record;

        END IF;

        RETURN NEW;
    END IF;

    -- handle items first, since with circulation activity
    -- their statuses change frequently
    IF TG_TABLE_NAME IN ('copy', 'unit') THEN -- This handles ON UPDATE OR DELETE. ON INSERT above

        IF TG_OP = 'DELETE' THEN -- Shouldn't get here, normally
            DELETE FROM asset.copy_vis_attr_cache WHERE target_copy = OLD.id;
            RETURN OLD;
        END IF;

        SELECT * INTO ncn FROM asset.call_number cn WHERE id = NEW.call_number;

        IF OLD.deleted <> NEW.deleted THEN
            IF NEW.deleted THEN
                DELETE FROM asset.copy_vis_attr_cache WHERE target_copy = OLD.id;
            ELSE
                INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                    ncn.record,
                    NEW.id,
                    asset.calculate_copy_visibility_attribute_set(NEW.id)
                );
            END IF;

            RETURN NEW;
        ELSIF OLD.location   <> NEW.location OR
            OLD.status       <> NEW.status OR
            OLD.opac_visible <> NEW.opac_visible OR
            OLD.circ_lib     <> NEW.circ_lib OR
            OLD.call_number  <> NEW.call_number
        THEN
            IF OLD.call_number  <> NEW.call_number THEN -- Special check since it's more expensive than the next branch
                SELECT * INTO ocn FROM asset.call_number cn WHERE id = OLD.call_number;

                IF ncn.record <> ocn.record THEN
                    -- We have to use a record-specific WHERE clause
                    -- to avoid modifying the entries for peer-bib copies.
                    UPDATE  asset.copy_vis_attr_cache
                      SET   target_copy = NEW.id,
                            record = ncn.record
                      WHERE target_copy = OLD.id
                            AND record = ocn.record;

                END IF;
            ELSE
                -- Any of these could change visibility, but
                -- we'll save some queries and not try to calculate
                -- the change directly.  We want to update peer-bib
                -- entries in this case, unlike above.
                UPDATE  asset.copy_vis_attr_cache
                  SET   target_copy = NEW.id,
                        vis_attr_vector = asset.calculate_copy_visibility_attribute_set(NEW.id)
                  WHERE target_copy = OLD.id;
            END IF;
        END IF;

    ELSIF TG_TABLE_NAME = 'call_number' THEN

        IF TG_OP = 'DELETE' AND OLD.label = '##URI##' AND dobib THEN -- really deleted located URI, if the delete protection rule is disabled...
            UPDATE  biblio.record_entry
              SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
              WHERE id = OLD.record;
            RETURN OLD;
        END IF;

        IF OLD.label = '##URI##' AND dobib THEN -- Located URI
            IF OLD.deleted <> NEW.deleted OR OLD.record <> NEW.record OR OLD.owning_lib <> NEW.owning_lib THEN
                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(NEW.record)
                  WHERE id = NEW.record;

                IF OLD.record <> NEW.record THEN -- maybe on merge?
                    UPDATE  biblio.record_entry
                      SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
                      WHERE id = OLD.record;
                END IF;
            END IF;

        ELSIF OLD.record <> NEW.record OR OLD.owning_lib <> NEW.owning_lib THEN
            UPDATE  asset.copy_vis_attr_cache
              SET   record = NEW.record,
                    vis_attr_vector = asset.calculate_copy_visibility_attribute_set(target_copy)
              WHERE target_copy IN (SELECT id FROM asset.copy WHERE call_number = NEW.id)
                    AND record = OLD.record;

        END IF;

    ELSIF TG_TABLE_NAME = 'record_entry' AND OLD.source IS DISTINCT FROM NEW.source THEN -- Only handles ON UPDATE, INSERT above
        NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id, NEW.source, TRUE);
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER z_opac_vis_mat_view_tgr BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR DELETE ON biblio.peer_bib_copy_map FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE OR DELETE ON asset.call_number FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_del_tgr BEFORE DELETE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_del_tgr BEFORE DELETE ON serial.unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE ON serial.unit FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();

CREATE OR REPLACE FUNCTION asset.all_visible_flags () RETURNS TEXT AS $f$
    SELECT  '(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(1 << x, 'copy_flags')),'&') || ')'
      FROM  GENERATE_SERIES(0,0) AS x; -- increment as new flags are added.
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.visible_orgs (otype TEXT) RETURNS TEXT AS $f$
    SELECT  '(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, $1)),'|') || ')'
      FROM  actor.org_unit
      WHERE opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.invisible_orgs (otype TEXT) RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, $1)),'|') || ')'
      FROM  actor.org_unit
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

-- Bib-oriented defaults for search
CREATE OR REPLACE FUNCTION asset.bib_source_default () RETURNS TEXT AS $f$
    SELECT  '(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'bib_source')),'|') || ')'
      FROM  config.bib_source
      WHERE transcendant;
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.luri_org_default () RETURNS TEXT AS $f$
    SELECT  * FROM asset.invisible_orgs('luri_org');
$f$ LANGUAGE SQL STABLE;

-- Copy-oriented defaults for search
CREATE OR REPLACE FUNCTION asset.location_group_default () RETURNS TEXT AS $f$
    SELECT '!()'::TEXT; -- For now, as there's no way to cause a location group to hide all copies.
/*
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'location_group')),'|') || ')'
      FROM  asset.copy_location_group
      WHERE NOT opac_visible;
*/
$f$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION asset.location_default () RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'location')),'|') || ')'
      FROM  asset.copy_location
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.status_default () RETURNS TEXT AS $f$
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'status')),'|') || ')'
      FROM  config.copy_status
      WHERE NOT opac_visible;
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.owning_lib_default () RETURNS TEXT AS $f$
    SELECT  * FROM asset.invisible_orgs('owning_lib');
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.circ_lib_default () RETURNS TEXT AS $f$
    SELECT  * FROM asset.invisible_orgs('circ_lib');
$f$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION asset.patron_default_visibility_mask () RETURNS TABLE (b_attrs TEXT, c_attrs TEXT)  AS $f$
DECLARE
    copy_flags      TEXT; -- "c" attr

    owning_lib      TEXT; -- "c" attr
    circ_lib        TEXT; -- "c" attr
    status          TEXT; -- "c" attr
    location        TEXT; -- "c" attr
    location_group  TEXT; -- "c" attr

    luri_org        TEXT; -- "b" attr
    bib_sources     TEXT; -- "b" attr

    bib_tests       TEXT := '';
BEGIN
    copy_flags      := asset.all_visible_flags(); -- Will always have at least one

    owning_lib      := NULLIF(asset.owning_lib_default(),'!()');

    circ_lib        := NULLIF(asset.circ_lib_default(),'!()');
    status          := NULLIF(asset.status_default(),'!()');
    location        := NULLIF(asset.location_default(),'!()');
    location_group  := NULLIF(asset.location_group_default(),'!()');

    -- LURIs will be handled at the perl layer directly
    -- luri_org        := NULLIF(asset.luri_org_default(),'!()');
    bib_sources     := NULLIF(asset.bib_source_default(),'()');


    IF luri_org IS NOT NULL AND bib_sources IS NOT NULL THEN
        bib_tests := '('||ARRAY_TO_STRING( ARRAY[luri_org,bib_sources], '|')||')&('||luri_org||')&';
    ELSIF luri_org IS NOT NULL THEN
        bib_tests := luri_org || '&';
    ELSIF bib_sources IS NOT NULL THEN
        bib_tests := bib_sources || '|';
    END IF;

    RETURN QUERY SELECT bib_tests,
        '('||ARRAY_TO_STRING(
            ARRAY[copy_flags,owning_lib,circ_lib,status,location,location_group]::TEXT[],
            '&'
        )||')';
END;
$f$ LANGUAGE PLPGSQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION metabib.suggest_browse_entries(raw_query_text text, search_class text, headline_opts text, visibility_org integer, query_limit integer, normalization integer)
 RETURNS TABLE(value text, field integer, buoyant_and_class_match boolean, field_match boolean, field_weight integer, rank real, buoyant boolean, match text)
AS $f$
DECLARE
    prepared_query_texts    TEXT[];
    query                   TSQUERY;
    plain_query             TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
    b_tests                 TEXT := '';
BEGIN
    prepared_query_texts := metabib.autosuggest_prepare_tsquery(raw_query_text);

    query := TO_TSQUERY('keyword', prepared_query_texts[1]);
    plain_query := TO_TSQUERY('keyword', prepared_query_texts[2]);

    visibility_org := NULLIF(visibility_org,-1);
    IF visibility_org IS NOT NULL THEN
        PERFORM FROM actor.org_unit WHERE id = visibility_org AND parent_ou IS NULL;
        IF FOUND THEN
            opac_visibility_join := '';
        ELSE
            PERFORM 1 FROM config.internal_flag WHERE enabled AND name = 'opac.located_uri.act_as_copy';
            IF FOUND THEN
                b_tests := search.calculate_visibility_attribute_test(
                    'luri_org',
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_full_path(visibility_org))
                );
            ELSE
                b_tests := search.calculate_visibility_attribute_test(
                    'luri_org',
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_ancestors(visibility_org))
                );
            END IF;
            opac_visibility_join := '
    LEFT JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = x.source)
    LEFT JOIN biblio.record_entry b ON (b.id = x.source)
    JOIN vm ON (acvac.vis_attr_vector @@
            (vm.c_attrs || $$&$$ ||
                search.calculate_visibility_attribute_test(
                    $$circ_lib$$,
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_descendants($4))
                )
            )::query_int
         ) OR (b.vis_attr_vector @@ $$' || b_tests || '$$::query_int)
';
        END IF;
    ELSE
        opac_visibility_join := '';
    END IF;

    -- The following determines whether we only provide suggestsons matching
    -- the user's selected search_class, or whether we show other suggestions
    -- too. The reason for MIN() is that for search_classes like
    -- 'title|proper|uniform' you would otherwise get multiple rows.  The
    -- implication is that if title as a class doesn't have restrict,
    -- nor does the proper field, but the uniform field does, you're going
    -- to get 'false' for your overall evaluation of 'should we restrict?'
    -- To invert that, change from MIN() to MAX().

    SELECT
        INTO r_fields
            MIN(cmc.restrict::INT) AS restrict_class,
            MIN(cmf.restrict::INT) AS restrict_field
        FROM metabib.search_class_to_registered_components(search_class)
            AS _registered (field_class TEXT, field INT)
        JOIN
            config.metabib_class cmc ON (cmc.name = _registered.field_class)
        LEFT JOIN
            config.metabib_field cmf ON (cmf.id = _registered.field);

    -- evaluate 'should we restrict?'
    IF r_fields.restrict_field::BOOL OR r_fields.restrict_class::BOOL THEN
        search_class_join := '
    JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            (_registered.field IS NULL AND
                _registered.field_class = cmf.field_class) OR
            (_registered.field = cmf.id)
        )
    ';
    ELSE
        search_class_join := '
    LEFT JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            _registered.field_class = cmc.name
        )
    ';
    END IF;

    RETURN QUERY EXECUTE '
WITH vm AS ( SELECT * FROM asset.patron_default_visibility_mask() ),
     mbe AS (SELECT * FROM metabib.browse_entry WHERE index_vector @@ $1 LIMIT 10000)
SELECT  DISTINCT
        x.value,
        x.id,
        x.push,
        x.restrict,
        x.weight,
        x.ts_rank_cd,
        x.buoyant,
        TS_HEADLINE(value, $7, $3)
  FROM  (SELECT DISTINCT
                mbe.value,
                cmf.id,
                cmc.buoyant AND _registered.field_class IS NOT NULL AS push,
                _registered.field = cmf.id AS restrict,
                cmf.weight,
                TS_RANK_CD(mbe.index_vector, $1, $6),
                cmc.buoyant,
                mbedm.source
          FROM  metabib.browse_entry_def_map mbedm
                JOIN mbe ON (mbe.id = mbedm.entry)
                JOIN config.metabib_field cmf ON (cmf.id = mbedm.def)
                JOIN config.metabib_class cmc ON (cmf.field_class = cmc.name)
                '  || search_class_join || '
          ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
          LIMIT 1000) AS x
        ' || opac_visibility_join || '
  ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
  LIMIT $5
'   -- sic, repeat the order by clause in the outer select too
    USING
        query, search_class, headline_opts,
        visibility_org, query_limit, normalization, plain_query
        ;

    -- sort order:
    --  buoyant AND chosen class = match class
    --  chosen field = match field
    --  field weight
    --  rank
    --  buoyancy
    --  value itself

END;
$f$ LANGUAGE plpgsql ROWS 10;

CREATE OR REPLACE FUNCTION metabib.staged_browse(query text, fields integer[], context_org integer, context_locations integer[], staff boolean, browse_superpage_size integer, count_up_from_zero boolean, result_limit integer, next_pivot_pos integer)
 RETURNS SETOF metabib.flat_browse_entry_appearance
AS $f$
DECLARE
    curs                    REFCURSOR;
    rec                     RECORD;
    qpfts_query             TEXT;
    aqpfts_query            TEXT;
    afields                 INT[];
    bfields                 INT[];
    result_row              metabib.flat_browse_entry_appearance%ROWTYPE;
    results_skipped         INT := 0;
    row_counter             INT := 0;
    row_number              INT;
    slice_start             INT;
    slice_end               INT;
    full_end                INT;
    all_records             BIGINT[];
    all_brecords             BIGINT[];
    all_arecords            BIGINT[];
    superpage_of_records    BIGINT[];
    superpage_size          INT;
    c_tests                 TEXT := '';
    b_tests                 TEXT := '';
    c_orgs                  INT[];
    unauthorized_entry      RECORD;
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    IF NOT staff THEN
        SELECT x.c_attrs, x.b_attrs INTO c_tests, b_tests FROM asset.patron_default_visibility_mask() x;
    END IF;

    -- b_tests supplies its own query_int operator, c_tests does not
    IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;

    SELECT ARRAY_AGG(id) INTO c_orgs FROM actor.org_unit_descendants(context_org);

    c_tests := c_tests || search.calculate_visibility_attribute_test('circ_lib',c_orgs)
               || '&' || search.calculate_visibility_attribute_test('owning_lib',c_orgs);

    PERFORM 1 FROM config.internal_flag WHERE enabled AND name = 'opac.located_uri.act_as_copy';
    IF FOUND THEN
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_full_path(context_org) x)
        );
    ELSE
        b_tests := b_tests || search.calculate_visibility_attribute_test(
            'luri_org',
            (SELECT ARRAY_AGG(id) FROM actor.org_unit_ancestors(context_org) x)
        );
    END IF;

    IF context_locations THEN
        IF c_tests <> '' THEN c_tests := c_tests || '&'; END IF;
        c_tests := c_tests || search.calculate_visibility_attribute_test('location',context_locations);
    END IF;

    OPEN curs NO SCROLL FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;

        --Is unauthorized?
        SELECT INTO unauthorized_entry *
        FROM metabib.browse_entry_simple_heading_map mbeshm
        INNER JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
        INNER JOIN authority.control_set_authority_field acsaf ON ( acsaf.id = ash.atag )
        JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
        WHERE mbeshm.entry = rec.id
        AND   ahf.heading_purpose = 'variant';

        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
        IF (unauthorized_entry.record IS NOT NULL) THEN
            --unauthorized term belongs to an auth linked to a bib?
            SELECT INTO all_arecords, result_row.sees, afields
                    ARRAY_AGG(DISTINCT abl.bib),
                    STRING_AGG(DISTINCT abl.authority::TEXT, $$,$$),
                    ARRAY_AGG(DISTINCT map.metabib_field)
            FROM authority.bib_linking abl
            INNER JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                    map.authority_field = unauthorized_entry.atag
                    AND map.metabib_field = ANY(fields)
            )
            WHERE abl.authority = unauthorized_entry.record;
        ELSE
            --do usual procedure
            SELECT INTO all_arecords, result_row.sees, afields
                    ARRAY_AGG(DISTINCT abl.bib), -- bibs to check for visibility
                    STRING_AGG(DISTINCT aal.source::TEXT, $$,$$), -- authority record ids
                    ARRAY_AGG(DISTINCT map.metabib_field) -- authority-tag-linked CMF rows

            FROM  metabib.browse_entry_simple_heading_map mbeshm
                    JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                    JOIN authority.authority_linking aal ON ( ash.record = aal.source )
                    JOIN authority.bib_linking abl ON ( aal.target = abl.authority )
                    JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                        ash.atag = map.authority_field
                        AND map.metabib_field = ANY(fields)
                    )
                    JOIN authority.control_set_authority_field acsaf ON (
                        map.authority_field = acsaf.id
                    )
                    JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
              WHERE mbeshm.entry = rec.id
              AND   ahf.heading_purpose = 'variant';

        END IF;

        -- Gather aggregate data based on the MBE row we're looking at now, bib axis
        SELECT INTO all_brecords, result_row.authorities, bfields
                ARRAY_AGG(DISTINCT source),
                STRING_AGG(DISTINCT authority::TEXT, $$,$$),
                ARRAY_AGG(DISTINCT def)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        SELECT INTO result_row.fields STRING_AGG(DISTINCT x::TEXT, $$,$$) FROM UNNEST(afields || bfields) x;

        result_row.sources := 0;
        result_row.asources := 0;

        -- Bib-linked vis checking
        IF ARRAY_UPPER(all_brecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.sources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    LEFT JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_brecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.accurate := TRUE;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            SELECT  INTO result_row.asources COUNT(DISTINCT b.id)
              FROM  biblio.record_entry b
                    LEFT JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = b.id)
              WHERE b.id = ANY(all_arecords[1:browse_superpage_size])
                    AND (
                        acvac.vis_attr_vector @@ c_tests::query_int
                        OR b.vis_attr_vector @@ b_tests::query_int
                    );

            result_row.aaccurate := TRUE;

        END IF;

        IF result_row.sources > 0 OR result_row.asources > 0 THEN

            -- The function that calls this function needs row_number in order
            -- to correctly order results from two different runs of this
            -- functions.
            result_row.row_number := row_number;

            -- Now, if row_counter is still less than limit, return a row.  If
            -- not, but it is less than next_pivot_pos, continue on without
            -- returning actual result rows until we find
            -- that next pivot, and return it.

            IF row_counter < result_limit THEN
                result_row.browse_entry := rec.id;
                result_row.value := rec.value;

                RETURN NEXT result_row;
            ELSE
                result_row.browse_entry := NULL;
                result_row.authorities := NULL;
                result_row.fields := NULL;
                result_row.value := NULL;
                result_row.sources := NULL;
                result_row.sees := NULL;
                result_row.accurate := NULL;
                result_row.aaccurate := NULL;
                result_row.pivot_point := rec.id;

                IF row_counter >= next_pivot_pos THEN
                    RETURN NEXT result_row;
                    RETURN;
                END IF;
            END IF;

            IF count_up_from_zero THEN
                row_number := row_number + 1;
            ELSE
                row_number := row_number - 1;
            END IF;

            -- row_counter is different from row_number.
            -- It simply counts up from zero so that we know when
            -- we've reached our limit.
            row_counter := row_counter + 1;
        END IF;
    END LOOP;
END;
$f$ LANGUAGE plpgsql ROWS 10;

CREATE OR REPLACE FUNCTION metabib.browse(search_field integer[], browse_term text, context_org integer DEFAULT NULL::integer, context_loc_group integer DEFAULT NULL::integer, staff boolean DEFAULT false, pivot_id bigint DEFAULT NULL::bigint, result_limit integer DEFAULT 10)
 RETURNS SETOF metabib.flat_browse_entry_appearance
AS $f$
DECLARE
    core_query              TEXT;
    back_query              TEXT;
    forward_query           TEXT;
    pivot_sort_value        TEXT;
    pivot_sort_fallback     TEXT;
    context_locations       INT[];
    browse_superpage_size   INT;
    results_skipped         INT := 0;
    back_limit              INT;
    back_to_pivot           INT;
    forward_limit           INT;
    forward_to_pivot        INT;
BEGIN
    -- First, find the pivot if we were given a browse term but not a pivot.
    IF pivot_id IS NULL THEN
        pivot_id := metabib.browse_pivot(search_field, browse_term);
    END IF;

    SELECT INTO pivot_sort_value, pivot_sort_fallback
        sort_value, value FROM metabib.browse_entry WHERE id = pivot_id;

    -- Bail if we couldn't find a pivot.
    IF pivot_sort_value IS NULL THEN
        RETURN;
    END IF;

    -- Transform the context_loc_group argument (if any) (logc at the
    -- TPAC layer) into a form we'll be able to use.
    IF context_loc_group IS NOT NULL THEN
        SELECT INTO context_locations ARRAY_AGG(location)
            FROM asset.copy_location_group_map
            WHERE lgroup = context_loc_group;
    END IF;

    -- Get the configured size of browse superpages.
    SELECT INTO browse_superpage_size COALESCE(value::INT,100)     -- NULL ok
        FROM config.global_flag
        WHERE enabled AND name = 'opac.browse.holdings_visibility_test_limit';

    -- First we're going to search backward from the pivot, then we're going
    -- to search forward.  In each direction, we need two limits.  At the
    -- lesser of the two limits, we delineate the edge of the result set
    -- we're going to return.  At the greater of the two limits, we find the
    -- pivot value that would represent an offset from the current pivot
    -- at a distance of one "page" in either direction, where a "page" is a
    -- result set of the size specified in the "result_limit" argument.
    --
    -- The two limits in each direction make four derived values in total,
    -- and we calculate them now.
    back_limit := CEIL(result_limit::FLOAT / 2);
    back_to_pivot := result_limit;
    forward_limit := result_limit / 2;
    forward_to_pivot := result_limit - 1;

    -- This is the meat of the SQL query that finds browse entries.  We'll
    -- pass this to a function which uses it with a cursor, so that individual
    -- rows may be fetched in a loop until some condition is satisfied, without
    -- waiting for a result set of fixed size to be collected all at once.
    core_query := '
SELECT  mbe.id,
        mbe.value,
        mbe.sort_value
  FROM  metabib.browse_entry mbe
  WHERE (
            EXISTS ( -- are there any bibs using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_def_map mbedm
                  WHERE mbedm.entry = mbe.id AND mbedm.def = ANY(' || quote_literal(search_field) || ')
            ) OR EXISTS ( -- are there any authorities using this mbe via the requested fields?
                SELECT  1
                  FROM  metabib.browse_entry_simple_heading_map mbeshm
                        JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                        JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                            ash.atag = map.authority_field
                            AND map.metabib_field = ANY(' || quote_literal(search_field) || ')
                        )
                        JOIN authority.control_set_authority_field acsaf ON (
                            map.authority_field = acsaf.id
                        )
                        JOIN authority.heading_field ahf ON (ahf.id = acsaf.heading_field)
                  WHERE mbeshm.entry = mbe.id
                    AND ahf.heading_purpose IN (' || $$'variant'$$ || ')
                    -- and authority that variant is coming from is linked to a bib
                    AND EXISTS (
                        SELECT  1
                        FROM  metabib.browse_entry_def_map mbedm2
                        WHERE mbedm2.authority = ash.record AND mbedm2.def = ANY(' || quote_literal(search_field) || ')
                    )

            )
        ) AND ';

    -- This is the variant of the query for browsing backward.
    back_query := core_query ||
        ' mbe.sort_value <= ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value DESC, mbe.value DESC LIMIT 1000';

    -- This variant browses forward.
    forward_query := core_query ||
        ' mbe.sort_value > ' || quote_literal(pivot_sort_value) ||
    ' ORDER BY mbe.sort_value, mbe.value LIMIT 1000';

    -- We now call the function which applies a cursor to the provided
    -- queries, stopping at the appropriate limits and also giving us
    -- the next page's pivot.
    RETURN QUERY
        SELECT * FROM metabib.staged_browse(
            back_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, TRUE, back_limit, back_to_pivot
        ) UNION
        SELECT * FROM metabib.staged_browse(
            forward_query, search_field, context_org, context_locations,
            staff, browse_superpage_size, FALSE, forward_limit, forward_to_pivot
        ) ORDER BY row_number DESC;

END;
$f$ LANGUAGE plpgsql ROWS 10;

CREATE OR REPLACE FUNCTION metabib.browse(
    search_class        TEXT,
    browse_term         TEXT,
    context_org         INT DEFAULT NULL,
    context_loc_group   INT DEFAULT NULL,
    staff               BOOL DEFAULT FALSE,
    pivot_id            BIGINT DEFAULT NULL,
    result_limit        INT DEFAULT 10
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
BEGIN
    RETURN QUERY SELECT * FROM metabib.browse(
        (SELECT COALESCE(ARRAY_AGG(id), ARRAY[]::INT[])
            FROM config.metabib_field WHERE field_class = search_class),
        browse_term,
        context_org,
        context_loc_group,
        staff,
        pivot_id,
        result_limit
    );
END;
$p$ LANGUAGE PLPGSQL ROWS 10;

CREATE OR REPLACE VIEW search.best_tsconfig AS
    SELECT  m.id AS id,
            COALESCE(f.ts_config, c.ts_config, 'simple') AS ts_config
      FROM  config.metabib_field m
            LEFT JOIN config.metabib_class_ts_map c ON (c.field_class = m.field_class AND c.index_weight = 'C')
            LEFT JOIN config.metabib_field_ts_map f ON (f.metabib_field = m.id AND f.index_weight = 'C');

CREATE TYPE search.highlight_result AS ( id BIGINT, source BIGINT, field INT, value TEXT, highlight TEXT );

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

    opts := opts || $$, StopSel=</b>, StartSel="<b class='$$ || v_css_class; -- "

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

CREATE OR REPLACE FUNCTION evergreen.escape_for_html (TEXT) RETURNS TEXT AS $$
    SELECT  regexp_replace(
                regexp_replace(
                    regexp_replace(
                        $1,
                        '&',
                        '&amp;',
                        'g'
                    ),
                    '<',
                    '&lt;',
                    'g'
                ),
                '>',
                '&gt;',
                'g'
            );
$$ LANGUAGE SQL IMMUTABLE LEAKPROOF STRICT COST 10;

CREATE OR REPLACE FUNCTION search.highlight_display_fields(
    rid         BIGINT,
    tsq_map     TEXT, -- { '(a | b) & c' => '1,2,3,4', ...}
    css_class   TEXT DEFAULT 'oils_SH',
    hl_all      BOOL DEFAULT TRUE,
    minwords    INT DEFAULT 5,
    maxwords    INT DEFAULT 25,
    shortwords  INT DEFAULT 0,
    maxfrags    INT DEFAULT 0,
    delimiter   TEXT DEFAULT ' ... '
) RETURNS SETOF search.highlight_result AS $f$
DECLARE
    tsq_hstore  TEXT;
    tsq         TEXT;
    fields      TEXT;
    afields     INT[];
    seen        INT[];
BEGIN
    IF (tsq_map ILIKE 'hstore%') THEN
        EXECUTE 'SELECT ' || tsq_map INTO tsq_hstore;
    ELSE
        tsq_hstore := tsq_map::HSTORE;
    END IF;

    FOR tsq, fields IN SELECT key, value FROM each(tsq_hstore::HSTORE) LOOP
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

-- SymSpell implementation follows

-- We don't pass this function arrays with nulls, so we save 5% not testing for that
CREATE OR REPLACE FUNCTION evergreen.text_array_merge_unique (
    TEXT[], TEXT[]
) RETURNS TEXT[] AS $F$
    SELECT NULLIF(ARRAY(
        SELECT * FROM UNNEST($1) x
            UNION
        SELECT * FROM UNNEST($2) y
    ),'{}');
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION evergreen.qwerty_keyboard_distance ( a TEXT, b TEXT ) RETURNS NUMERIC AS $F$
use String::KeyboardDistance qw(:all);
return qwerty_keyboard_distance(@_);
$F$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.qwerty_keyboard_distance_match ( a TEXT, b TEXT ) RETURNS NUMERIC AS $F$
use String::KeyboardDistance qw(:all);
return qwerty_keyboard_distance_match(@_);
$F$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION evergreen.levenshtein_damerau_edistance ( a TEXT, b TEXT, INT ) RETURNS NUMERIC AS $F$
use Text::Levenshtein::Damerau::XS qw/xs_edistance/;
return xs_edistance(@_);
$F$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE TABLE search.symspell_dictionary (
    keyword_count           INT     NOT NULL DEFAULT 0,
    title_count             INT     NOT NULL DEFAULT 0,
    author_count            INT     NOT NULL DEFAULT 0,
    subject_count           INT     NOT NULL DEFAULT 0,
    series_count            INT     NOT NULL DEFAULT 0,
    identifier_count        INT     NOT NULL DEFAULT 0,

    prefix_key              TEXT    PRIMARY KEY,

    keyword_suggestions     TEXT[],
    title_suggestions       TEXT[],
    author_suggestions      TEXT[],
    subject_suggestions     TEXT[],
    series_suggestions      TEXT[],
    identifier_suggestions  TEXT[]
) WITH (fillfactor = 80);

-- INSERT-only table that catches updates to be reconciled
CREATE UNLOGGED TABLE search.symspell_dictionary_updates (
    transaction_id          BIGINT,
    keyword_count           INT     NOT NULL DEFAULT 0,
    title_count             INT     NOT NULL DEFAULT 0,
    author_count            INT     NOT NULL DEFAULT 0,
    subject_count           INT     NOT NULL DEFAULT 0,
    series_count            INT     NOT NULL DEFAULT 0,
    identifier_count        INT     NOT NULL DEFAULT 0,

    prefix_key              TEXT    NOT NULL,

    keyword_suggestions     TEXT[],
    title_suggestions       TEXT[],
    author_suggestions      TEXT[],
    subject_suggestions     TEXT[],
    series_suggestions      TEXT[],
    identifier_suggestions  TEXT[]
);
CREATE INDEX symspell_dictionary_updates_tid_idx ON search.symspell_dictionary_updates (transaction_id);

CREATE OR REPLACE FUNCTION search.symspell_dictionary_reify () RETURNS SETOF search.symspell_dictionary AS $f$
 WITH new_rows AS (
    DELETE FROM search.symspell_dictionary_updates WHERE transaction_id = txid_current() RETURNING *
 ), computed_rows AS ( -- this collapses the rows deleted into the format we need for UPSERT
    SELECT  SUM(keyword_count)    AS keyword_count,
            SUM(title_count)      AS title_count,
            SUM(author_count)     AS author_count,
            SUM(subject_count)    AS subject_count,
            SUM(series_count)     AS series_count,
            SUM(identifier_count) AS identifier_count,

            prefix_key,

            ARRAY_REMOVE(ARRAY_AGG(DISTINCT keyword_suggestions[1]), NULL)    AS keyword_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT title_suggestions[1]), NULL)      AS title_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT author_suggestions[1]), NULL)     AS author_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT subject_suggestions[1]), NULL)    AS subject_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT series_suggestions[1]), NULL)     AS series_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT identifier_suggestions[1]), NULL) AS identifier_suggestions
      FROM  new_rows
      GROUP BY prefix_key
 )
 INSERT INTO search.symspell_dictionary AS d SELECT * FROM computed_rows
 ON CONFLICT (prefix_key) DO UPDATE SET
    keyword_count = GREATEST(0, d.keyword_count + EXCLUDED.keyword_count),
    keyword_suggestions = evergreen.text_array_merge_unique(EXCLUDED.keyword_suggestions,d.keyword_suggestions),

    title_count = GREATEST(0, d.title_count + EXCLUDED.title_count),
    title_suggestions = evergreen.text_array_merge_unique(EXCLUDED.title_suggestions,d.title_suggestions),

    author_count = GREATEST(0, d.author_count + EXCLUDED.author_count),
    author_suggestions = evergreen.text_array_merge_unique(EXCLUDED.author_suggestions,d.author_suggestions),

    subject_count = GREATEST(0, d.subject_count + EXCLUDED.subject_count),
    subject_suggestions = evergreen.text_array_merge_unique(EXCLUDED.subject_suggestions,d.subject_suggestions),

    series_count = GREATEST(0, d.series_count + EXCLUDED.series_count),
    series_suggestions = evergreen.text_array_merge_unique(EXCLUDED.series_suggestions,d.series_suggestions),

    identifier_count = GREATEST(0, d.identifier_count + EXCLUDED.identifier_count),
    identifier_suggestions = evergreen.text_array_merge_unique(EXCLUDED.identifier_suggestions,d.identifier_suggestions)

    WHERE (
        EXCLUDED.keyword_count <> 0 OR
        EXCLUDED.title_count <> 0 OR
        EXCLUDED.author_count <> 0 OR
        EXCLUDED.subject_count <> 0 OR
        EXCLUDED.series_count <> 0 OR
        EXCLUDED.identifier_count <> 0 OR
        NOT (EXCLUDED.keyword_suggestions <@ d.keyword_suggestions) OR
        NOT (EXCLUDED.title_suggestions <@ d.title_suggestions) OR
        NOT (EXCLUDED.author_suggestions <@ d.author_suggestions) OR
        NOT (EXCLUDED.subject_suggestions <@ d.subject_suggestions) OR
        NOT (EXCLUDED.series_suggestions <@ d.series_suggestions) OR
        NOT (EXCLUDED.identifier_suggestions <@ d.identifier_suggestions)
    )
 RETURNING *;
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.disable_symspell_reification () RETURNS VOID AS $f$
    INSERT INTO config.internal_flag (name,enabled)
      VALUES ('ingest.disable_symspell_reification',TRUE)
    ON CONFLICT (name) DO UPDATE SET enabled = TRUE;
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.enable_symspell_reification () RETURNS VOID AS $f$
    UPDATE config.internal_flag SET enabled = FALSE WHERE name = 'ingest.disable_symspell_reification';
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.symspell_dictionary_full_reify () RETURNS SETOF search.symspell_dictionary AS $f$
 WITH new_rows AS (
    DELETE FROM search.symspell_dictionary_updates RETURNING *
 ), computed_rows AS ( -- this collapses the rows deleted into the format we need for UPSERT
    SELECT  SUM(keyword_count)    AS keyword_count,
            SUM(title_count)      AS title_count,
            SUM(author_count)     AS author_count,
            SUM(subject_count)    AS subject_count,
            SUM(series_count)     AS series_count,
            SUM(identifier_count) AS identifier_count,

            prefix_key,

            ARRAY_REMOVE(ARRAY_AGG(DISTINCT keyword_suggestions[1]), NULL)    AS keyword_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT title_suggestions[1]), NULL)      AS title_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT author_suggestions[1]), NULL)     AS author_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT subject_suggestions[1]), NULL)    AS subject_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT series_suggestions[1]), NULL)     AS series_suggestions,
            ARRAY_REMOVE(ARRAY_AGG(DISTINCT identifier_suggestions[1]), NULL) AS identifier_suggestions
      FROM  new_rows
      GROUP BY prefix_key
 )
 INSERT INTO search.symspell_dictionary AS d SELECT * FROM computed_rows
 ON CONFLICT (prefix_key) DO UPDATE SET
    keyword_count = GREATEST(0, d.keyword_count + EXCLUDED.keyword_count),
    keyword_suggestions = evergreen.text_array_merge_unique(EXCLUDED.keyword_suggestions,d.keyword_suggestions),

    title_count = GREATEST(0, d.title_count + EXCLUDED.title_count),
    title_suggestions = evergreen.text_array_merge_unique(EXCLUDED.title_suggestions,d.title_suggestions),

    author_count = GREATEST(0, d.author_count + EXCLUDED.author_count),
    author_suggestions = evergreen.text_array_merge_unique(EXCLUDED.author_suggestions,d.author_suggestions),

    subject_count = GREATEST(0, d.subject_count + EXCLUDED.subject_count),
    subject_suggestions = evergreen.text_array_merge_unique(EXCLUDED.subject_suggestions,d.subject_suggestions),

    series_count = GREATEST(0, d.series_count + EXCLUDED.series_count),
    series_suggestions = evergreen.text_array_merge_unique(EXCLUDED.series_suggestions,d.series_suggestions),

    identifier_count = GREATEST(0, d.identifier_count + EXCLUDED.identifier_count),
    identifier_suggestions = evergreen.text_array_merge_unique(EXCLUDED.identifier_suggestions,d.identifier_suggestions)
 RETURNING *;
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.symspell_parse_words ( phrase TEXT )
RETURNS SETOF TEXT AS $F$
    SELECT UNNEST(x) FROM regexp_matches($1, '([[:alnum:]]+''*[[:alnum:]]*)', 'g') x;
$F$ LANGUAGE SQL STRICT IMMUTABLE;

-- This version does not preserve input word order!
CREATE OR REPLACE FUNCTION search.symspell_parse_words_distinct ( phrase TEXT )
RETURNS SETOF TEXT AS $F$
    SELECT DISTINCT UNNEST(x) FROM regexp_matches($1, '([[:alnum:]]+''*[[:alnum:]]*)', 'g') x;
$F$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.symspell_transfer_casing ( withCase TEXT, withoutCase TEXT )
RETURNS TEXT AS $F$
DECLARE
    woChars TEXT[];
    curr    TEXT;
    ind     INT := 1;
BEGIN
    woChars := regexp_split_to_array(withoutCase,'');
    FOR curr IN SELECT x FROM regexp_split_to_table(withCase, '') x LOOP
        IF curr = evergreen.uppercase(curr) THEN
            woChars[ind] := evergreen.uppercase(woChars[ind]);
        END IF;
        ind := ind + 1;
    END LOOP;
    RETURN ARRAY_TO_STRING(woChars,'');
END;
$F$ LANGUAGE PLPGSQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.symspell_generate_edits (
    raw_word    TEXT,
    dist        INT DEFAULT 1,
    maxED       INT DEFAULT 3
) RETURNS TEXT[] AS $F$
DECLARE
    item    TEXT;
    list    TEXT[] := '{}';
    sublist TEXT[] := '{}';
BEGIN
    FOR I IN 1 .. CHARACTER_LENGTH(raw_word) LOOP
        item := SUBSTRING(raw_word FROM 1 FOR I - 1) || SUBSTRING(raw_word FROM I + 1);
        IF NOT list @> ARRAY[item] THEN
            list := item || list;
            IF dist < maxED AND CHARACTER_LENGTH(raw_word) > dist + 1 THEN
                sublist := search.symspell_generate_edits(item, dist + 1, maxED) || sublist;
            END IF;
        END IF;
    END LOOP;

    IF dist = 1 THEN
        RETURN evergreen.text_array_merge_unique(list, sublist);
    ELSE
        RETURN list || sublist;
    END IF;
END;
$F$ LANGUAGE PLPGSQL STRICT IMMUTABLE;

-- DROP TYPE search.symspell_lookup_output CASCADE;
CREATE TYPE search.symspell_lookup_output AS (
    suggestion          TEXT,
    suggestion_count    INT,
    lev_distance        INT,
    pg_trgm_sim         NUMERIC,
    qwerty_kb_match     NUMERIC,
    soundex_sim         NUMERIC,
    input               TEXT,
    norm_input          TEXT,
    prefix_key          TEXT,
    prefix_key_count    INT,
    word_pos            INT
);


CREATE OR REPLACE FUNCTION search.symspell_lookup(
    raw_input text,
    search_class text,
    verbosity integer DEFAULT 2,
    xfer_case boolean DEFAULT false,
    count_threshold integer DEFAULT 1,
    soundex_weight integer DEFAULT 0,
    pg_trgm_weight integer DEFAULT 0,
    kbdist_weight integer DEFAULT 0
) RETURNS SETOF search.symspell_lookup_output LANGUAGE plpgsql AS $function$
DECLARE
    prefix_length INT;
    maxED         INT;
    good_suggs  HSTORE;
    word_list   TEXT[];
    edit_list   TEXT[] := '{}';
    seen_list   TEXT[] := '{}';
    output      search.symspell_lookup_output;
    output_list search.symspell_lookup_output[];
    entry       RECORD;
    entry_key   TEXT;
    prefix_key  TEXT;
    sugg        TEXT;
    input       TEXT;
    word        TEXT;
    w_pos       INT := -1;
    smallest_ed INT := -1;
    global_ed   INT;
    i_len       INT;
    l_maxED     INT;
BEGIN
    SELECT value::INT INTO prefix_length FROM config.internal_flag WHERE name = 'symspell.prefix_length' AND enabled;
    prefix_length := COALESCE(prefix_length, 6);

    SELECT value::INT INTO maxED FROM config.internal_flag WHERE name = 'symspell.max_edit_distance' AND enabled;
    maxED := COALESCE(maxED, 3);

    word_list := ARRAY_AGG(x) FROM search.symspell_parse_words(raw_input) x;

    -- Common case exact match test for preformance
    IF verbosity = 0 AND CARDINALITY(word_list) = 1 AND CHARACTER_LENGTH(word_list[1]) <= prefix_length THEN
        EXECUTE
          'SELECT  '||search_class||'_suggestions AS suggestions,
                   '||search_class||'_count AS count,
                   prefix_key
             FROM  search.symspell_dictionary
             WHERE prefix_key = $1
                   AND '||search_class||'_count >= $2
                   AND '||search_class||'_suggestions @> ARRAY[$1]'
          INTO entry USING evergreen.lowercase(word_list[1]), COALESCE(count_threshold,1);
        IF entry.prefix_key IS NOT NULL THEN
            output.lev_distance := 0; -- definitionally
            output.prefix_key := entry.prefix_key;
            output.prefix_key_count := entry.count;
            output.suggestion_count := entry.count;
            output.input := word_list[1];
            IF xfer_case THEN
                output.suggestion := search.symspell_transfer_casing(output.input, entry.prefix_key);
            ELSE
                output.suggestion := entry.prefix_key;
            END IF;
            output.norm_input := entry.prefix_key;
            output.qwerty_kb_match := 1;
            output.pg_trgm_sim := 1;
            output.soundex_sim := 1;
            RETURN NEXT output;
            RETURN;
        END IF;
    END IF;

    <<word_loop>>
    FOREACH word IN ARRAY word_list LOOP
        w_pos := w_pos + 1;
        input := evergreen.lowercase(word);
        i_len := CHARACTER_LENGTH(input);
        l_maxED := maxED;

        IF CHARACTER_LENGTH(input) > prefix_length THEN
            prefix_key := SUBSTRING(input FROM 1 FOR prefix_length);
            edit_list := ARRAY[input,prefix_key] || search.symspell_generate_edits(prefix_key, 1, l_maxED);
        ELSE
            edit_list := input || search.symspell_generate_edits(input, 1, l_maxED);
        END IF;

        SELECT ARRAY_AGG(x ORDER BY CHARACTER_LENGTH(x) DESC) INTO edit_list FROM UNNEST(edit_list) x;

        output_list := '{}';
        seen_list := '{}';
        global_ed := NULL;

        <<entry_key_loop>>
        FOREACH entry_key IN ARRAY edit_list LOOP
            smallest_ed := -1;
            IF global_ed IS NOT NULL THEN
                smallest_ed := global_ed;
            END IF;

            FOR entry IN EXECUTE
                'SELECT  '||search_class||'_suggestions AS suggestions,
                         '||search_class||'_count AS count,
                         prefix_key
                   FROM  search.symspell_dictionary
                   WHERE prefix_key = $1
                         AND '||search_class||'_suggestions IS NOT NULL'
                USING entry_key
            LOOP

                SELECT  HSTORE(
                            ARRAY_AGG(
                                ARRAY[s, evergreen.levenshtein_damerau_edistance(input,s,l_maxED)::TEXT]
                                    ORDER BY evergreen.levenshtein_damerau_edistance(input,s,l_maxED) DESC
                            )
                        )
                  INTO  good_suggs
                  FROM  UNNEST(entry.suggestions) s
                  WHERE (ABS(CHARACTER_LENGTH(s) - i_len) <= maxEd AND evergreen.levenshtein_damerau_edistance(input,s,l_maxED) BETWEEN 0 AND l_maxED)
                        AND NOT seen_list @> ARRAY[s];

                CONTINUE WHEN good_suggs IS NULL;

                FOR sugg, output.suggestion_count IN EXECUTE
                    'SELECT  prefix_key, '||search_class||'_count
                       FROM  search.symspell_dictionary
                       WHERE prefix_key = ANY ($1)
                             AND '||search_class||'_count >= $2'
                    USING AKEYS(good_suggs), COALESCE(count_threshold,1)
                LOOP

                    output.lev_distance := good_suggs->sugg;
                    seen_list := seen_list || sugg;

                    -- Track the smallest edit distance among suggestions from this prefix key.
                    IF smallest_ed = -1 OR output.lev_distance < smallest_ed THEN
                        smallest_ed := output.lev_distance;
                    END IF;

                    -- Track the smallest edit distance for all prefix keys for this word.
                    IF global_ed IS NULL OR smallest_ed < global_ed THEN
                        global_ed = smallest_ed;
                        -- And if low verbosity, ignore suggs with a larger distance from here on.
                        IF verbosity <= 1 THEN
                            l_maxED := global_ed;
                        END IF;
                    END IF;

                    -- Lev distance is our main similarity measure. While
                    -- trgm or soundex similarity could be the main filter,
                    -- Lev is both language agnostic and faster.
                    --
                    -- Here we will skip suggestions that have a longer edit distance
                    -- than the shortest we've already found. This is simply an
                    -- optimization that allows us to avoid further processing
                    -- of this entry. It would be filtered out later.
                    CONTINUE WHEN output.lev_distance > global_ed AND verbosity <= 1;

                    -- If we have an exact match on the suggestion key we can also avoid
                    -- some function calls.
                    IF output.lev_distance = 0 THEN
                        output.qwerty_kb_match := 1;
                        output.pg_trgm_sim := 1;
                        output.soundex_sim := 1;
                    ELSE
                        IF kbdist_weight THEN
                            output.qwerty_kb_match := evergreen.qwerty_keyboard_distance_match(input, sugg);
                        ELSE
                            output.qwerty_kb_match := 0;
                        END IF;
                        IF pg_trgm_weight THEN
                            output.pg_trgm_sim := similarity(input, sugg);
                        ELSE
                            output.pg_trgm_sim := 0;
                        END IF;
                        IF soundex_weight THEN
                            output.soundex_sim := difference(input, sugg) / 4.0;
                        ELSE
                            output.soundex_sim := 0;
                        END IF;
                    END IF;

                    -- Fill in some fields
                    IF xfer_case AND input <> word THEN
                        output.suggestion := search.symspell_transfer_casing(word, sugg);
                    ELSE
                        output.suggestion := sugg;
                    END IF;
                    output.prefix_key := entry.prefix_key;
                    output.prefix_key_count := entry.count;
                    output.input := word;
                    output.norm_input := input;
                    output.word_pos := w_pos;

                    -- We can't "cache" a set of generated records directly, so
                    -- here we build up an array of search.symspell_lookup_output
                    -- records that we can revivicate later as a table using UNNEST().
                    output_list := output_list || output;

                    EXIT entry_key_loop WHEN smallest_ed = 0 AND verbosity = 0; -- exact match early exit
                    CONTINUE entry_key_loop WHEN smallest_ed = 0 AND verbosity = 1; -- exact match early jump to the next key

                END LOOP; -- loop over suggestions
            END LOOP; -- loop over entries
        END LOOP; -- loop over entry_keys

        -- Now we're done examining this word
        IF verbosity = 0 THEN
            -- Return the "best" suggestion from the smallest edit
            -- distance group.  We define best based on the weighting
            -- of the non-lev similarity measures and use the suggestion
            -- use count to break ties.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC
                        LIMIT 1;
        ELSIF verbosity = 1 THEN
            -- Return all suggestions from the smallest
            -- edit distance group.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list) WHERE lev_distance = smallest_ed
                    ORDER BY (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        ELSIF verbosity = 2 THEN
            -- Return everything we find, along with relevant stats
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        ELSIF verbosity = 3 THEN
            -- Return everything we find from the two smallest edit distance groups
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        ELSIF verbosity = 4 THEN
            -- Return everything we find from the two smallest edit distance groups that are NOT 0 distance
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) WHERE lev_distance > 0 ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        END IF;
    END LOOP; -- loop over words
END;
$function$;

CREATE OR REPLACE FUNCTION search.symspell_build_raw_entry (
    raw_input       TEXT,
    source_class    TEXT,
    no_limit        BOOL DEFAULT FALSE,
    prefix_length   INT DEFAULT 6,
    maxED           INT DEFAULT 3
) RETURNS SETOF search.symspell_dictionary AS $F$
DECLARE
    key         TEXT;
    del_key     TEXT;
    key_list    TEXT[];
    entry       search.symspell_dictionary%ROWTYPE;
BEGIN
    key := raw_input;

    IF NOT no_limit AND CHARACTER_LENGTH(raw_input) > prefix_length THEN
        key := SUBSTRING(key FROM 1 FOR prefix_length);
        key_list := ARRAY[raw_input, key];
    ELSE
        key_list := ARRAY[key];
    END IF;

    FOREACH del_key IN ARRAY key_list LOOP
        -- skip empty keys
        CONTINUE WHEN del_key IS NULL OR CHARACTER_LENGTH(del_key) = 0;

        entry.prefix_key := del_key;

        entry.keyword_count := 0;
        entry.title_count := 0;
        entry.author_count := 0;
        entry.subject_count := 0;
        entry.series_count := 0;
        entry.identifier_count := 0;

        entry.keyword_suggestions := '{}';
        entry.title_suggestions := '{}';
        entry.author_suggestions := '{}';
        entry.subject_suggestions := '{}';
        entry.series_suggestions := '{}';
        entry.identifier_suggestions := '{}';

        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'title' THEN entry.title_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'author' THEN entry.author_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'subject' THEN entry.subject_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'series' THEN entry.series_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'identifier' THEN entry.identifier_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;

        IF del_key = raw_input THEN
            IF source_class = 'keyword' THEN entry.keyword_count := 1; END IF;
            IF source_class = 'title' THEN entry.title_count := 1; END IF;
            IF source_class = 'author' THEN entry.author_count := 1; END IF;
            IF source_class = 'subject' THEN entry.subject_count := 1; END IF;
            IF source_class = 'series' THEN entry.series_count := 1; END IF;
            IF source_class = 'identifier' THEN entry.identifier_count := 1; END IF;
        END IF;

        RETURN NEXT entry;
    END LOOP;

    FOR del_key IN SELECT x FROM UNNEST(search.symspell_generate_edits(key, 1, maxED)) x LOOP

        -- skip empty keys
        CONTINUE WHEN del_key IS NULL OR CHARACTER_LENGTH(del_key) = 0;
        -- skip suggestions that are already too long for the prefix key
        CONTINUE WHEN CHARACTER_LENGTH(del_key) <= (prefix_length - maxED) AND CHARACTER_LENGTH(raw_input) > prefix_length;

        entry.keyword_suggestions := '{}';
        entry.title_suggestions := '{}';
        entry.author_suggestions := '{}';
        entry.subject_suggestions := '{}';
        entry.series_suggestions := '{}';
        entry.identifier_suggestions := '{}';

        IF source_class = 'keyword' THEN entry.keyword_count := 0; END IF;
        IF source_class = 'title' THEN entry.title_count := 0; END IF;
        IF source_class = 'author' THEN entry.author_count := 0; END IF;
        IF source_class = 'subject' THEN entry.subject_count := 0; END IF;
        IF source_class = 'series' THEN entry.series_count := 0; END IF;
        IF source_class = 'identifier' THEN entry.identifier_count := 0; END IF;

        entry.prefix_key := del_key;

        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'title' THEN entry.title_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'author' THEN entry.author_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'subject' THEN entry.subject_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'series' THEN entry.series_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'identifier' THEN entry.identifier_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;

        RETURN NEXT entry;
    END LOOP;

END;
$F$ LANGUAGE PLPGSQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.symspell_build_entries (
    full_input      TEXT,
    source_class    TEXT,
    old_input       TEXT DEFAULT NULL,
    include_phrases BOOL DEFAULT FALSE
) RETURNS SETOF search.symspell_dictionary AS $F$
DECLARE
    prefix_length   INT;
    maxED           INT;
    word_list   TEXT[];
    input       TEXT;
    word        TEXT;
    entry       search.symspell_dictionary;
BEGIN
    IF full_input IS NOT NULL THEN
        SELECT value::INT INTO prefix_length FROM config.internal_flag WHERE name = 'symspell.prefix_length' AND enabled;
        prefix_length := COALESCE(prefix_length, 6);

        SELECT value::INT INTO maxED FROM config.internal_flag WHERE name = 'symspell.max_edit_distance' AND enabled;
        maxED := COALESCE(maxED, 3);

        input := evergreen.lowercase(full_input);
        word_list := ARRAY_AGG(x) FROM search.symspell_parse_words_distinct(input) x;
        IF word_list IS NULL THEN
            RETURN;
        END IF;
    
        IF CARDINALITY(word_list) > 1 AND include_phrases THEN
            RETURN QUERY SELECT * FROM search.symspell_build_raw_entry(input, source_class, TRUE, prefix_length, maxED);
        END IF;

        FOREACH word IN ARRAY word_list LOOP
            -- Skip words that have runs of 5 or more digits (I'm looking at you, ISxNs)
            CONTINUE WHEN CHARACTER_LENGTH(word) > 4 AND word ~ '\d{5,}';
            RETURN QUERY SELECT * FROM search.symspell_build_raw_entry(word, source_class, FALSE, prefix_length, maxED);
        END LOOP;
    END IF;

    IF old_input IS NOT NULL THEN
        input := evergreen.lowercase(old_input);

        FOR word IN SELECT x FROM search.symspell_parse_words_distinct(input) x LOOP
            -- similarly skip words that have 5 or more digits here to
            -- avoid adding erroneous prefix deletion entries to the dictionary
            CONTINUE WHEN CHARACTER_LENGTH(word) > 4 AND word ~ '\d{5,}';
            entry.prefix_key := word;

            entry.keyword_count := 0;
            entry.title_count := 0;
            entry.author_count := 0;
            entry.subject_count := 0;
            entry.series_count := 0;
            entry.identifier_count := 0;

            entry.keyword_suggestions := '{}';
            entry.title_suggestions := '{}';
            entry.author_suggestions := '{}';
            entry.subject_suggestions := '{}';
            entry.series_suggestions := '{}';
            entry.identifier_suggestions := '{}';

            IF source_class = 'keyword' THEN entry.keyword_count := -1; END IF;
            IF source_class = 'title' THEN entry.title_count := -1; END IF;
            IF source_class = 'author' THEN entry.author_count := -1; END IF;
            IF source_class = 'subject' THEN entry.subject_count := -1; END IF;
            IF source_class = 'series' THEN entry.series_count := -1; END IF;
            IF source_class = 'identifier' THEN entry.identifier_count := -1; END IF;

            RETURN NEXT entry;
        END LOOP;
    END IF;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION search.symspell_maintain_entries () RETURNS TRIGGER AS $f$
DECLARE
    search_class    TEXT;
    new_value       TEXT := NULL;
    old_value       TEXT := NULL;
BEGIN
    search_class := COALESCE(TG_ARGV[0], SPLIT_PART(TG_TABLE_NAME,'_',1));

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        new_value := NEW.value;
    END IF;

    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        old_value := OLD.value;
    END IF;

    IF new_value = old_value THEN
        -- same, move along
    ELSE
        INSERT INTO search.symspell_dictionary_updates
            SELECT  txid_current(), *
              FROM  search.symspell_build_entries(
                        new_value,
                        search_class,
                        old_value
                    );
    END IF;

    RETURN NULL; -- always fired AFTER
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.title_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.author_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.subject_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.series_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.keyword_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

CREATE TRIGGER maintain_symspell_entries_tgr
    AFTER INSERT OR UPDATE OR DELETE ON metabib.identifier_field_entry
    FOR EACH ROW EXECUTE PROCEDURE search.symspell_maintain_entries();

COMMIT;

