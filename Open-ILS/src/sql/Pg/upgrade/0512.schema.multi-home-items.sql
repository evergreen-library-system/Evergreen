BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0512'); -- miker

CREATE TABLE biblio.peer_type (
    id      SERIAL  PRIMARY KEY,
    name        TEXT        NOT NULL UNIQUE -- i18n
);

CREATE TABLE biblio.peer_bib_copy_map (
    id      SERIAL  PRIMARY KEY,
    peer_type   INT     NOT NULL REFERENCES biblio.peer_type (id),
    peer_record BIGINT      NOT NULL REFERENCES biblio.record_entry (id),
    target_copy BIGINT      NOT NULL -- can't use fkey because of acp subtables
);
CREATE INDEX peer_bib_copy_map_record_idx ON biblio.peer_bib_copy_map (peer_record);
CREATE INDEX peer_bib_copy_map_copy_idx ON biblio.peer_bib_copy_map (target_copy);

DROP TABLE asset.opac_visible_copies;
CREATE TABLE asset.opac_visible_copies (
  id        BIGSERIAL primary key,
  copy_id   BIGINT,
  record    BIGINT,
  circ_lib  INTEGER
);

INSERT INTO biblio.peer_type (id,name) VALUES
    (1,oils_i18n_gettext(1,'Bound Volume','bpt','name')),
    (2,oils_i18n_gettext(2,'Bilingual','bpt','name')),
    (3,oils_i18n_gettext(3,'Back-to-back','bpt','name')),
    (4,oils_i18n_gettext(4,'Set','bpt','name')),
    (5,oils_i18n_gettext(5,'e-Reader Preload','bpt','name')); 

SELECT SETVAL('biblio.peer_type_id_seq'::TEXT, 100);

CREATE OR REPLACE FUNCTION search.query_parser_fts (

    param_search_ou INT,
    param_depth     INT,
    param_query     TEXT,
    param_statuses  INT[],
    param_locations INT[],
    param_offset    INT,
    param_check     INT,
    param_limit     INT,
    metarecord      BOOL,
    staff           BOOL
 
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];

    check_limit         INT;
    core_limit          INT;
    core_offset         INT;
    tmp_int             INT;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;
    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;
    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );
        IF NOT FOUND THEN
            -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
            deleted_count := deleted_count + 1;
            CONTINUE;
        END IF;

        PERFORM 1
          FROM  biblio.record_entry b
                JOIN config.bib_source s ON (b.source = s.id)
          WHERE s.transcendant
                AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );

        IF FOUND THEN
            -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        PERFORM 1
          FROM  asset.call_number cn
                JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                JOIN asset.uri uri ON (map.uri = uri.id)
          WHERE NOT cn.deleted
                AND cn.label = '##URI##'
                AND uri.active
                AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                AND cn.owning_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
          LIMIT 1;

        IF FOUND THEN
            -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.status IN ( SELECT * FROM search.explode_array( param_statuses ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.status IN ( SELECT * FROM search.explode_array( param_statuses ) )
                        AND pr.peer_record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                -- RAISE NOTICE ' % and multi-home linked records were all status-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;
            END IF;

        END IF;

        IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.location IN ( SELECT * FROM search.explode_array( param_locations ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.location IN ( SELECT * FROM search.explode_array( param_locations ) )
                        AND pr.peer_record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    -- RAISE NOTICE ' % and multi-home linked records were all copy_location-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;
            END IF;

        END IF;

        IF staff IS NULL OR NOT staff THEN

            PERFORM 1
              FROM  asset.opac_visible_copies
              WHERE circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN
                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                  WHERE cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                        AND pr.peer_record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;
            END IF;

        ELSE

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN

                PERFORM 1
                  FROM  biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                  WHERE NOT cp.deleted
                        AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                        AND pr.peer_record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    PERFORM 1
                      FROM  asset.call_number cn
                      WHERE cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                      LIMIT 1;

                    IF FOUND THEN
                        -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION unapi.holdings_xml (bid BIGINT, ouid INT, org TEXT, depth INT DEFAULT NULL, includes TEXT[] DEFAULT NULL::TEXT[], slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE) RETURNS XML AS $F$
     SELECT  XMLELEMENT(
                 name holdings,
                 XMLATTRIBUTES(
                    CASE WHEN $8 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                    CASE WHEN ('bre' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN 'tag:open-ils.org:U2@bre/' || $1 || '/' || $3 ELSE NULL END AS id
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
                                     ORDER BY 1
                     )x)
                 ),
                 CASE
                     WHEN ('bmp' = ANY ($5)) THEN
                        XMLELEMENT( name monograph_parts,
                            XMLAGG((SELECT unapi.bmp( id, 'xml', 'monograph_part', evergreen.array_remove_item_by_value( evergreen.array_remove_item_by_value($5,'bre'), 'holdings_xml'), $3, $4, $6, $7, FALSE) FROM biblio.monograph_part WHERE record = $1))
                        )
                     ELSE NULL
                 END,
                 CASE WHEN ('acn' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN
                     XMLELEMENT(
                         name volumes,
                         (SELECT XMLAGG(acn) FROM (
                            SELECT  unapi.acn(acn.id,'xml','volume',evergreen.array_remove_item_by_value(evergreen.array_remove_item_by_value('{acn,auri}'::TEXT[] || $5,'holdings_xml'),'bre'), $3, $4, $6, $7, FALSE)
                              FROM  asset.call_number acn
                              WHERE acn.record = $1
                                    AND EXISTS (
                                        SELECT  1
                                          FROM  asset.copy acp
                                                JOIN actor.org_unit_descendants(
                                                    $2,
                                                    (COALESCE(
                                                        $4,
                                                        (SELECT aout.depth
                                                          FROM  actor.org_unit_type aout
                                                                JOIN actor.org_unit aou ON (aou.ou_type = aout.id AND aou.id = $2)
                                                        )
                                                    ))
                                                ) aoud ON (acp.circ_lib = aoud.id)
                                          LIMIT 1
                                    )
                              ORDER BY label_sortkey
                              LIMIT $6
                              OFFSET $7
                         )x)
                     )
                 ELSE NULL END,
                 CASE WHEN ('ssub' = ANY ('{acn,auri}'::TEXT[] || $5)) THEN
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
                            SELECT  unapi.acp(p.target_copy,'xml','copy','{}'::TEXT[], $3, $4, $6, $7, FALSE)
                              FROM  biblio.peer_bib_copy_map p
                                    JOIN asset.copy c ON (p.target_copy = c.id)
                              WHERE NOT c.deleted AND peer_record = $1
                        )x)
                     )
                 ELSE NULL END
             );
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION unapi.acp ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit INT DEFAULT NULL, soffset INT DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name copy,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acp/' || id AS id,
                        create_date, edit_date, copy_number, circulate, deposit,
                        ref, holdable, deleted, deposit_amount, price, barcode,
                        circ_modifier, circ_as_type, opac_visible
                    ),
                    unapi.ccs( status, $2, 'status', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.acl( location, $2, 'location', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE),
                    unapi.aou( circ_lib, $2, 'circ_lib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    unapi.aou( circ_lib, $2, 'circlib', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8),
                    CASE WHEN ('acn' = ANY ($4)) THEN unapi.acn( call_number, $2, 'call_number', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) ELSE NULL END,
                    XMLELEMENT( name copy_notes,
                        CASE
                            WHEN ('acpn' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.acpn( id, 'xml', 'copy_note', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.copy_note WHERE owning_copy = cp.id AND pub))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name statcats,
                        CASE
                            WHEN ('ascecm' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.ascecm( stat_cat_entry, 'xml', 'statcat', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.stat_cat_entry_copy_map WHERE owning_copy = cp.id))
                            ELSE NULL
                        END
                    ),
                    XMLELEMENT( name foreign_records,
                        CASE
                            WHEN ('bre' = ANY ($4)) THEN
                                XMLAGG((SELECT unapi.bre(peer_record,'marcxml','record','{}'::TEXT[], $5, $6, $7, $8, FALSE) FROM biblio.peer_bib_copy_map WHERE target_copy = cp.id))
                            ELSE NULL
                        END

                    ),
                    CASE
                        WHEN ('bmp' = ANY ($4)) THEN
                            XMLELEMENT( name monograph_parts,
                                XMLAGG((SELECT unapi.bmp( part, 'xml', 'monograph_part', evergreen.array_remove_item_by_value($4,'acp'), $5, $6, $7, $8, FALSE) FROM asset.copy_part_map WHERE target_copy = cp.id))
                            )
                        ELSE NULL
                    END
                )
          FROM  asset.copy cp
          WHERE id = $1
          GROUP BY id, status, location, circ_lib, call_number, create_date, edit_date, copy_number, circulate, deposit, ref, holdable, deleted, deposit_amount, price, barcode, circ_modifier, circ_as_type, opac_visible;
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION asset.refresh_opac_visible_copies_mat_view () RETURNS VOID AS $$

    TRUNCATE TABLE asset.opac_visible_copies;

    INSERT INTO asset.opac_visible_copies (copy_id, circ_lib, record)
    SELECT  cp.id, cp.circ_lib, cn.record
    FROM  asset.copy cp
        JOIN asset.call_number cn ON (cn.id = cp.call_number)
        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
        JOIN asset.copy_location cl ON (cp.location = cl.id)
        JOIN config.copy_status cs ON (cp.status = cs.id)
        JOIN biblio.record_entry b ON (cn.record = b.id)
    WHERE NOT cp.deleted
        AND NOT cn.deleted
        AND NOT b.deleted
        AND cs.opac_visible
        AND cl.opac_visible
        AND cp.opac_visible
        AND a.opac_visible
            UNION
    SELECT  cp.id, cp.circ_lib, pbcm.peer_record AS record
    FROM  asset.copy cp
        JOIN biblio.peer_bib_copy_map pbcm ON (pbcm.target_copy = cp.id)
        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
        JOIN asset.copy_location cl ON (cp.location = cl.id)
        JOIN config.copy_status cs ON (cp.status = cs.id)
    WHERE NOT cp.deleted
        AND cs.opac_visible
        AND cl.opac_visible
        AND cp.opac_visible
        AND a.opac_visible;

$$ LANGUAGE SQL;
COMMENT ON FUNCTION asset.refresh_opac_visible_copies_mat_view() IS $$
Rebuild the copy OPAC visibility cache.  Useful during migrations.
$$;

SELECT asset.refresh_opac_visible_copies_mat_view();
CREATE INDEX opac_visible_copies_idx1 on asset.opac_visible_copies (record, circ_lib);
CREATE INDEX opac_visible_copies_copy_id_idx on asset.opac_visible_copies (copy_id);
CREATE UNIQUE INDEX opac_visible_copies_once_per_record_idx on asset.opac_visible_copies (copy_id, record);
 
CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    add_query       TEXT;
    remove_query    TEXT;
    do_add          BOOLEAN := false;
    do_remove       BOOLEAN := false;
BEGIN
    add_query := $$
            INSERT INTO asset.opac_visible_copies (copy_id, circ_lib, record)
              SELECT id, circ_lib, record FROM (
                SELECT  cp.id, cp.circ_lib, cn.record, cn.id AS call_number
                  FROM  asset.copy cp
                        JOIN asset.call_number cn ON (cn.id = cp.call_number)
                        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                        JOIN asset.copy_location cl ON (cp.location = cl.id)
                        JOIN config.copy_status cs ON (cp.status = cs.id)
                        JOIN biblio.record_entry b ON (cn.record = b.id)
                  WHERE NOT cp.deleted
                        AND NOT cn.deleted
                        AND NOT b.deleted
                        AND cs.opac_visible
                        AND cl.opac_visible
                        AND cp.opac_visible
                        AND a.opac_visible
                            UNION
                SELECT  cp.id, cp.circ_lib, pbcm.peer_record AS record, NULL AS call_number
                  FROM  asset.copy cp
                        JOIN biblio.peer_bib_copy_map pbcm ON (pbcm.target_copy = cp.id)
                        JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                        JOIN asset.copy_location cl ON (cp.location = cl.id)
                        JOIN config.copy_status cs ON (cp.status = cs.id)
                  WHERE NOT cp.deleted
                        AND cs.opac_visible
                        AND cl.opac_visible
                        AND cp.opac_visible
                        AND a.opac_visible
                    ) AS x 

    $$;
 
    remove_query := $$ DELETE FROM asset.opac_visible_copies WHERE copy_id IN ( SELECT id FROM asset.copy WHERE $$;

    IF TG_TABLE_NAME = 'peer_bib_copy_map' THEN
        IF TG_OP = 'INSERT' THEN
            add_query := add_query || 'WHERE x.id = ' || NEW.target_copy || ' AND x.record = ' || NEW.peer_record || ';';
            EXECUTE add_query;
            RETURN NEW;
        ELSE
            remove_query := 'DELETE FROM asset.opac_visible_copies WHERE copy_id = ' || OLD.target_copy || ' AND record = ' || OLD.peer_record || ';';
            EXECUTE remove_query;
            RETURN OLD;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN

        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            add_query := add_query || 'WHERE x.id = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    -- handle items first, since with circulation activity
    -- their statuses change frequently
    IF TG_TABLE_NAME IN ('copy', 'unit') THEN

        IF OLD.location    <> NEW.location OR
           OLD.call_number <> NEW.call_number OR
           OLD.status      <> NEW.status OR
           OLD.circ_lib    <> NEW.circ_lib THEN
            -- any of these could change visibility, but
            -- we'll save some queries and not try to calculate
            -- the change directly
            do_remove := true;
            do_add := true;
        ELSE

            IF OLD.deleted <> NEW.deleted THEN
                IF NEW.deleted THEN
                    do_remove := true;
                ELSE
                    do_add := true;
                END IF;
            END IF;

            IF OLD.opac_visible <> NEW.opac_visible THEN
                IF OLD.opac_visible THEN
                    do_remove := true;
                ELSIF NOT do_remove THEN -- handle edge case where deleted item
                                        -- is also marked opac_visible
                    do_add := true;
                END IF;
            END IF;

        END IF;

        IF do_remove THEN
            DELETE FROM asset.opac_visible_copies WHERE id = NEW.id;
        END IF;
        IF do_add THEN
            add_query := add_query || 'WHERE x.id = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('call_number', 'record_entry') THEN -- these have a 'deleted' column
 
        IF OLD.deleted AND NEW.deleted THEN -- do nothing

            RETURN NEW;
 
        ELSIF NEW.deleted THEN -- remove rows
 
            IF TG_TABLE_NAME = 'call_number' THEN
                DELETE FROM asset.opac_visible_copies WHERE id IN (SELECT id FROM asset.copy WHERE call_number = NEW.id);
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                DELETE FROM asset.opac_visible_copies WHERE record = NEW.id;
            END IF;
 
            RETURN NEW;
 
        ELSIF OLD.deleted THEN -- add rows
 
            IF TG_TABLE_NAME IN ('copy','unit') THEN
                add_query := add_query || 'WHERE x.id = ' || NEW.id || ';';
            ELSIF TG_TABLE_NAME = 'call_number' THEN
                add_query := add_query || 'WHERE x.call_number = ' || NEW.id || ';';
            ELSIF TG_TABLE_NAME = 'record_entry' THEN
                add_query := add_query || 'WHERE x.record = ' || NEW.id || ';';
            END IF;
 
            EXECUTE add_query;
            RETURN NEW;
 
        END IF;
 
    END IF;

    IF TG_TABLE_NAME = 'call_number' THEN

        IF OLD.record <> NEW.record THEN
            -- call number is linked to different bib
            remove_query := remove_query || 'call_number = ' || NEW.id || ');';
            EXECUTE remove_query;
            add_query := add_query || 'WHERE x.call_number = ' || NEW.id || ';';
            EXECUTE add_query;
        END IF;

        RETURN NEW;

    END IF;

    IF TG_TABLE_NAME IN ('record_entry') THEN
        RETURN NEW; -- don't have 'opac_visible'
    END IF;

    -- actor.org_unit, asset.copy_location, asset.copy_status
    IF NEW.opac_visible = OLD.opac_visible THEN -- do nothing

        RETURN NEW;

    ELSIF NEW.opac_visible THEN -- add rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            add_query := add_query || 'AND cp.circ_lib = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            add_query := add_query || 'AND cp.location = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            add_query := add_query || 'AND cp.status = ' || NEW.id || ';';
        END IF;
 
        EXECUTE add_query;
 
    ELSE -- delete rows

        IF TG_TABLE_NAME = 'org_unit' THEN
            remove_query := 'DELETE FROM asset.opac_visible_copies WHERE circ_lib = ' || NEW.id || ';';
        ELSIF TG_TABLE_NAME = 'copy_location' THEN
            remove_query := remove_query || 'location = ' || NEW.id || ');';
        ELSIF TG_TABLE_NAME = 'copy_status' THEN
            remove_query := remove_query || 'status = ' || NEW.id || ');';
        END IF;
 
        EXECUTE remove_query;
 
    END IF;
 
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;
COMMENT ON FUNCTION asset.cache_copy_visibility() IS $$
Trigger function to update the copy OPAC visiblity cache.
$$;

CREATE TRIGGER a_opac_vis_mat_view_tgr AFTER INSERT OR DELETE ON biblio.peer_bib_copy_map FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();

CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this bib is deleted
        DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id; -- Rid ourselves of the search-estimate-killing linkage
        DELETE FROM metabib.record_attr WHERE id = NEW.id; -- Kill the attrs hash, useless on deleted records
        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            FOR attr_def IN SELECT * FROM config.record_attr_definition ORDER BY format LOOP

                IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
                    SELECT  ARRAY_TO_STRING(ARRAY_ACCUM(value), COALESCE(attr_def.joiner,' ')) INTO attr_value
                      FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
                      WHERE record = NEW.id
                            AND tag LIKE attr_def.tag
                            AND CASE
                                WHEN attr_def.sf_list IS NOT NULL 
                                    THEN POSITION(subfield IN attr_def.sf_list) > 0
                                ELSE TRUE
                                END
                      GROUP BY tag
                      ORDER BY tag
                      LIMIT 1;

                ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
                    attr_value := biblio.marc21_extract_fixed_field(NEW.id, attr_def.fixed_field);

                ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

                    SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
            
                    -- See if we can skip the XSLT ... it's expensive
                    IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                        -- Can't skip the transform
                        IF xfrm.xslt <> '---' THEN
                            transformed_xml := oils_xslt_process(NEW.marc,xfrm.xslt);
                        ELSE
                            transformed_xml := NEW.marc;
                        END IF;
            
                        prev_xfrm := xfrm.name;
                    END IF;

                    IF xfrm.name IS NULL THEN
                        -- just grab the marcxml (empty) transform
                        SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                        prev_xfrm := xfrm.name;
                    END IF;

                    attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

                ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
                    SELECT  value::TEXT INTO attr_value
                      FROM  biblio.marc21_physical_characteristics(NEW.id)
                      WHERE subfield = attr_def.phys_char_sf
                      LIMIT 1; -- Just in case ...

                END IF;

                -- apply index normalizers to attr_value
                FOR normalizer IN
                    SELECT  n.func AS func,
                            n.param_count AS param_count,
                            m.params AS params
                      FROM  config.index_normalizer n
                            JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                      WHERE attr = attr_def.name
                      ORDER BY m.pos LOOP
                        EXECUTE 'SELECT ' || normalizer.func || '(' ||
                            quote_literal( attr_value ) ||
                            CASE
                                WHEN normalizer.param_count > 0
                                    THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                    ELSE ''
                                END ||
                            ')' INTO attr_value;
        
                END LOOP;

                -- Add the new value to the hstore
                new_attrs := new_attrs || hstore( attr_def.name, attr_value );

            END LOOP;

            IF TG_OP = 'INSERT' OR OLD.deleted THEN -- initial insert OR revivication
                INSERT INTO metabib.record_attr (id, attrs) VALUES (NEW.id, new_attrs);
            ELSE
                UPDATE metabib.record_attr SET attrs = attrs || new_attrs WHERE id = NEW.id;
            END IF;

        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
