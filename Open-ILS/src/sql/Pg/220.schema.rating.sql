DROP SCHEMA IF EXISTS rating CASCADE;

BEGIN;

-- Create these so that the queries in the UDFs will validate
CREATE TEMP TABLE precalc_filter_bib_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bib_filter_bib_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_src_filter_bib_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_copy_filter_bib_list (
    id  BIGINT,
    copy  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_circ_mod_filter_bib_list (
    id  BIGINT,
    copy  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_location_filter_bib_list (
    id  BIGINT,
    copy  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_attr_filter_bib_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bibs_by_copy_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bibs_by_uri_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bibs_by_copy_or_uri_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bib_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE SCHEMA rating;

CREATE TABLE rating.popularity_parameter (
    id          INT     PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE, -- i18n
    description TEXT,
    func        TEXT,
    require_horizon     BOOL    NOT NULL DEFAULT FALSE,
    require_importance  BOOL    NOT NULL DEFAULT FALSE,
    require_percentile  BOOL    NOT NULL DEFAULT FALSE
);

INSERT INTO rating.popularity_parameter (id,name,func,require_horizon,require_importance,require_percentile) VALUES
    (1,'Holds Filled Over Time','rating.holds_filled_over_time',TRUE,FALSE,TRUE),
    (2,'Holds Requested Over Time','rating.holds_placed_over_time',TRUE,FALSE,TRUE),
    (3,'Current Hold Count','rating.current_hold_count',FALSE,FALSE,TRUE),
    (4,'Circulations Over Time','rating.circs_over_time',TRUE,FALSE,TRUE),
    (5,'Current Circulation Count','rating.current_circ_count',FALSE,FALSE,TRUE),
    (6,'Out/Total Ratio','rating.checked_out_total_ratio',FALSE,FALSE,TRUE),
    (7,'Holds/Total Ratio','rating.holds_total_ratio',FALSE,FALSE,TRUE),
    (8,'Holds/Holdable Ratio','rating.holds_holdable_ratio',FALSE,FALSE,TRUE),
    (9,'Percent of Time Circulating','rating.percent_time_circulating',FALSE,FALSE,TRUE),
    (10,'Bibliographic Record Age (days, newer is better)','rating.bib_record_age',FALSE,FALSE,TRUE),
    (11,'Publication Age (days, newer is better)','rating.bib_pub_age',FALSE,FALSE,TRUE),
    (12,'On-line Bib has attributes','rating.generic_fixed_rating_by_uri',FALSE,FALSE,FALSE),
    (13,'Bib has attributes and copies','rating.generic_fixed_rating_by_copy',FALSE,FALSE,FALSE),
    (14,'Bib has attributes and copies or URIs','rating.generic_fixed_rating_by_copy_or_uri',FALSE,FALSE,FALSE),
    (15,'Bib has attributes','rating.generic_fixed_rating_global',FALSE,FALSE,FALSE),
    (16,'Copy Count','rating.copy_count',FALSE,FALSE,TRUE),
    (17,'Circulation Library Count', 'rating.org_unit_count',FALSE,FALSE, TRUE),
    (18, 'In-House Use Over Time', 'rating.inhouse_over_time',TRUE,FALSE,TRUE);


CREATE TABLE rating.badge (
    id                      SERIAL      PRIMARY KEY,
    name                    TEXT        NOT NULL,
    description             TEXT,
    scope                   INT         NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    weight                  INT         NOT NULL DEFAULT 1,
    horizon_age             INTERVAL,
    importance_age          INTERVAL,
    importance_interval     INTERVAL    NOT NULL DEFAULT '1 day',
    importance_scale        NUMERIC     CHECK (importance_scale IS NULL OR importance_scale > 0.0),
    recalc_interval         INTERVAL    NOT NULL DEFAULT '1 month',
    attr_filter             TEXT,
    src_filter              INT         REFERENCES config.bib_source (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    circ_mod_filter         TEXT        REFERENCES config.circ_modifier (code) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    loc_grp_filter          INT         REFERENCES asset.copy_location_group (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    popularity_parameter    INT         NOT NULL REFERENCES rating.popularity_parameter (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    fixed_rating            INT         CHECK (fixed_rating IS NULL OR fixed_rating BETWEEN -5 AND 5),
    percentile              NUMERIC     CHECK (percentile IS NULL OR (percentile >= 50.0 AND percentile < 100.0)),
    discard                 INT         NOT NULL DEFAULT 0, 
    last_calc               TIMESTAMPTZ,
    CONSTRAINT unique_name_scope UNIQUE (name,scope)
);

CREATE TABLE rating.record_badge_score (
    id          BIGSERIAL   PRIMARY KEY,
    record      BIGINT      NOT NULL REFERENCES biblio.record_entry (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    badge       INT         NOT NULL REFERENCES rating.badge (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    score       INT         NOT NULL CHECK (score BETWEEN -5 AND 5),
    CONSTRAINT unique_record_badge UNIQUE (record,badge)
);
CREATE INDEX record_badge_score_badge_idx ON rating.record_badge_score (badge);
CREATE INDEX record_badge_score_record_idx ON rating.record_badge_score (record);

CREATE OR REPLACE VIEW rating.badge_with_orgs AS
    WITH    org_scope AS (
                SELECT  id,
                        array_agg(tree) AS orgs
                  FROM  (SELECT id,
                                (actor.org_unit_descendants(id)).id AS tree
                          FROM  actor.org_unit
                        ) x
                  GROUP BY 1
            )
    SELECT  b.*,
            s.orgs
      FROM  rating.badge b
            JOIN org_scope s ON (b.scope = s.id);

CREATE OR REPLACE FUNCTION rating.precalc_src_filter(src INT)
    RETURNS INT AS $f$
DECLARE
    cnt     INT     := 0;
BEGIN

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_src_filter_bib_list;
    IF src IS NOT NULL THEN
        CREATE TEMP TABLE precalc_src_filter_bib_list ON COMMIT DROP AS
            SELECT id FROM biblio.record_entry
            WHERE source = src AND NOT deleted;
    ELSE
        CREATE TEMP TABLE precalc_src_filter_bib_list ON COMMIT DROP AS
            SELECT id FROM biblio.record_entry
            WHERE id > 0 AND NOT deleted;
    END IF;

    SELECT count(*) INTO cnt FROM precalc_src_filter_bib_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_circ_mod_filter(cm TEXT)
    RETURNS INT AS $f$
DECLARE
    cnt     INT     := 0;
BEGIN

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_circ_mod_filter_bib_list;
    IF cm IS NOT NULL THEN
        CREATE TEMP TABLE precalc_circ_mod_filter_bib_list ON COMMIT DROP AS
            SELECT  cn.record AS id,
                    cp.id AS copy
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cn.id = cp.call_number)
              WHERE cp.circ_modifier = cm
                    AND NOT cp.deleted;
    ELSE
        CREATE TEMP TABLE precalc_circ_mod_filter_bib_list ON COMMIT DROP AS
            SELECT  cn.record AS id,
                    cp.id AS copy
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cn.id = cp.call_number)
              WHERE NOT cp.deleted;
    END IF;

    SELECT count(*) INTO cnt FROM precalc_circ_mod_filter_bib_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_location_filter(loc INT)
    RETURNS INT AS $f$
DECLARE
    cnt     INT     := 0;
BEGIN

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_location_filter_bib_list;
    IF loc IS NOT NULL THEN
        CREATE TEMP TABLE precalc_location_filter_bib_list ON COMMIT DROP AS
            SELECT  cn.record AS id,
                    cp.id AS copy
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cn.id = cp.call_number)
                    JOIN asset.copy_location_group_map lg ON (cp.location = lg.location)
              WHERE lg.lgroup = loc
                    AND NOT cp.deleted;
    ELSE
        CREATE TEMP TABLE precalc_location_filter_bib_list ON COMMIT DROP AS
            SELECT  cn.record AS id,
                    cp.id AS copy
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cn.id = cp.call_number)
              WHERE NOT cp.deleted;
    END IF;

    SELECT count(*) INTO cnt FROM precalc_location_filter_bib_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

-- all or limited...
CREATE OR REPLACE FUNCTION rating.precalc_attr_filter(attr_filter TEXT)
    RETURNS INT AS $f$
DECLARE
    cnt     INT := 0;
    afilter TEXT;
BEGIN

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_attr_filter_bib_list;
    IF attr_filter IS NOT NULL THEN
        afilter := metabib.compile_composite_attr(attr_filter);
        CREATE TEMP TABLE precalc_attr_filter_bib_list ON COMMIT DROP AS
            SELECT source AS id FROM metabib.record_attr_vector_list
            WHERE vlist @@ metabib.compile_composite_attr(attr_filter);
    ELSE
        CREATE TEMP TABLE precalc_attr_filter_bib_list ON COMMIT DROP AS
            SELECT source AS id FROM metabib.record_attr_vector_list;
    END IF;

    SELECT count(*) INTO cnt FROM precalc_attr_filter_bib_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_bibs_by_copy(badge_id INT)
    RETURNS INT AS $f$
DECLARE
    cnt         INT     := 0;
    badge_row   rating.badge_with_orgs%ROWTYPE;
    base        TEXT;
    whr         TEXT;
BEGIN

    SELECT * INTO badge_row FROM rating.badge_with_orgs WHERE id = badge_id;

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bibs_by_copy_list;
    CREATE TEMP TABLE precalc_bibs_by_copy_list ON COMMIT DROP AS
        SELECT  DISTINCT cn.record AS id
          FROM  asset.call_number cn
                JOIN asset.copy cp ON (cp.call_number = cn.id AND NOT cp.deleted)
                JOIN precalc_copy_filter_bib_list f ON (cp.id = f.copy)
          WHERE cn.owning_lib = ANY (badge_row.orgs)
                AND NOT cn.deleted;

    SELECT count(*) INTO cnt FROM precalc_bibs_by_copy_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_bibs_by_uri(badge_id INT)
    RETURNS INT AS $f$
DECLARE
    cnt         INT     := 0;
    badge_row   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge_row FROM rating.badge_with_orgs WHERE id = badge_id;

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bibs_by_uri_list;
    CREATE TEMP TABLE precalc_bibs_by_uri_list ON COMMIT DROP AS
        SELECT  DISTINCT record AS id
          FROM  asset.call_number cn
                JOIN asset.uri_call_number_map urim ON (urim.call_number = cn.id)
                JOIN asset.uri uri ON (urim.uri = uri.id AND uri.active)
          WHERE cn.owning_lib = ANY (badge_row.orgs)
                AND cn.label = '##URI##'
                AND NOT cn.deleted;

    SELECT count(*) INTO cnt FROM precalc_bibs_by_uri_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_bibs_by_copy_or_uri(badge_id INT)
    RETURNS INT AS $f$
DECLARE
    cnt         INT     := 0;
BEGIN

    PERFORM rating.precalc_bibs_by_copy(badge_id);
    PERFORM rating.precalc_bibs_by_uri(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bibs_by_copy_or_uri_list;
    CREATE TEMP TABLE precalc_bibs_by_copy_or_uri_list ON COMMIT DROP AS
        SELECT id FROM precalc_bibs_by_copy_list
            UNION
        SELECT id FROM precalc_bibs_by_uri_list;

    SELECT count(*) INTO cnt FROM precalc_bibs_by_copy_or_uri_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION rating.recalculate_badge_score ( badge_id INT, setup_only BOOL DEFAULT FALSE ) RETURNS VOID AS $f$
DECLARE
    badge_row           rating.badge%ROWTYPE;
    param           rating.popularity_parameter%ROWTYPE;
BEGIN
    SET LOCAL client_min_messages = error;

    -- Find what we're doing    
    SELECT * INTO badge_row FROM rating.badge WHERE id = badge_id;
    SELECT * INTO param FROM rating.popularity_parameter WHERE id = badge_row.popularity_parameter;

    -- Calculate the filtered bib set, or all bibs if none
    PERFORM rating.precalc_attr_filter(badge_row.attr_filter);
    PERFORM rating.precalc_src_filter(badge_row.src_filter);
    PERFORM rating.precalc_circ_mod_filter(badge_row.circ_mod_filter);
    PERFORM rating.precalc_location_filter(badge_row.loc_grp_filter);

    -- Bring the bib-level filter lists together
    DROP TABLE IF EXISTS precalc_bib_filter_bib_list;
    CREATE TEMP TABLE precalc_bib_filter_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_attr_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_src_filter_bib_list;

    -- Bring the copy-level filter lists together. We're keeping this for bib_by_copy filtering later.
    DROP TABLE IF EXISTS precalc_copy_filter_bib_list;
    CREATE TEMP TABLE precalc_copy_filter_bib_list ON COMMIT DROP AS
        SELECT id, copy FROM precalc_circ_mod_filter_bib_list
            INTERSECT
        SELECT id, copy FROM precalc_location_filter_bib_list;

    -- Bring the collapsed filter lists together
    DROP TABLE IF EXISTS precalc_filter_bib_list;
    CREATE TEMP TABLE precalc_filter_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_bib_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_copy_filter_bib_list;

    CREATE INDEX precalc_filter_bib_list_idx
        ON precalc_filter_bib_list (id);

    IF setup_only THEN
        RETURN;
    END IF;

    -- If it's a fixed-rating badge, just do it ...
    IF badge_row.fixed_rating IS NOT NULL THEN
        DELETE FROM rating.record_badge_score WHERE badge = badge_id;
        EXECUTE $e$
            INSERT INTO rating.record_badge_score (record, badge, score)
                SELECT record, $1, $2 FROM $e$ || param.func || $e$($1)$e$
        USING badge_id, badge_row.fixed_rating;

        UPDATE rating.badge SET last_calc = NOW() WHERE id = badge_id;

        RETURN;
    END IF;
    -- else, calculate!

    -- Make a session-local scratchpad for calculating scores
    CREATE TEMP TABLE record_score_scratchpad (
        bib     BIGINT,
        value   NUMERIC
    ) ON COMMIT DROP;

    -- Gather raw values
    EXECUTE $e$
        INSERT INTO record_score_scratchpad (bib, value)
            SELECT * FROM $e$ || param.func || $e$($1)$e$
    USING badge_id;

    IF badge_row.discard > 0 OR badge_row.percentile IS NOT NULL THEN
        -- To speed up discard-common
        CREATE INDEX record_score_scratchpad_score_idx ON record_score_scratchpad (value);
        ANALYZE record_score_scratchpad;
    END IF;

    IF badge_row.discard > 0 THEN -- Remove common low values (trim the long tail)
        DELETE FROM record_score_scratchpad WHERE value IN (
            SELECT DISTINCT value FROM record_score_scratchpad ORDER BY value LIMIT badge_row.discard
        );
    END IF;

    IF badge_row.percentile IS NOT NULL THEN -- Cut population down to exceptional records
        DELETE FROM record_score_scratchpad WHERE value <= (
            SELECT value FROM (
                SELECT  value,
                        CUME_DIST() OVER (ORDER BY value) AS p
                  FROM  record_score_scratchpad
            ) x WHERE p < badge_row.percentile / 100.0 ORDER BY p DESC LIMIT 1
        );
    END IF;


    -- And, finally, push new data in
    DELETE FROM rating.record_badge_score WHERE badge = badge_id;
    INSERT INTO rating.record_badge_score (badge, record, score)
        SELECT  badge_id,
                bib,
                GREATEST(ROUND((CUME_DIST() OVER (ORDER BY value)) * 5), 1) AS value
          FROM  record_score_scratchpad;

    DROP TABLE record_score_scratchpad;

    -- Now, finally-finally, mark the badge as recalculated
    UPDATE rating.badge SET last_calc = NOW() WHERE id = badge_id;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.holds_filled_over_time(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
    iage    INT     := 1;
    iint    INT     := NULL;
    iscale  NUMERIC := NULL;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    IF badge.horizon_age IS NULL THEN
        RAISE EXCEPTION 'Badge "%" with id % requires a horizon age but has none.',
            badge.name,
            badge.id;
    END IF;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bib_list;
    CREATE TEMP TABLE precalc_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list;

    iint := EXTRACT(EPOCH FROM badge.importance_interval);
    IF badge.importance_age IS NOT NULL THEN
        iage := (EXTRACT(EPOCH FROM badge.importance_age) / iint)::INT;
    END IF;

    -- if iscale is smaller than 1, scaling slope will be shallow ... BEWARE!
    iscale := COALESCE(badge.importance_scale, 1.0);

    RETURN QUERY
     SELECT bib,
            SUM( holds * GREATEST( iscale * (iage - hage), 1.0 ))
      FROM (
         SELECT f.id AS bib,
                (1 + EXTRACT(EPOCH FROM AGE(h.fulfillment_time)) / iint)::INT AS hage,
                COUNT(h.id)::INT AS holds
          FROM  action.hold_request h
                JOIN reporter.hold_request_record rhrr ON (rhrr.id = h.id)
                JOIN precalc_bib_list f ON (f.id = rhrr.bib_record)
          WHERE h.fulfillment_time >= NOW() - badge.horizon_age
                AND h.request_lib = ANY (badge.orgs)
          GROUP BY 1, 2
      ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.holds_placed_over_time(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
    iage    INT     := 1;
    iint    INT     := NULL;
    iscale  NUMERIC := NULL;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    IF badge.horizon_age IS NULL THEN
        RAISE EXCEPTION 'Badge "%" with id % requires a horizon age but has none.',
            badge.name,
            badge.id;
    END IF;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bib_list;
    CREATE TEMP TABLE precalc_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list;

    iint := EXTRACT(EPOCH FROM badge.importance_interval);
    IF badge.importance_age IS NOT NULL THEN
        iage := (EXTRACT(EPOCH FROM badge.importance_age) / iint)::INT;
    END IF;

    -- if iscale is smaller than 1, scaling slope will be shallow ... BEWARE!
    iscale := COALESCE(badge.importance_scale, 1.0);

    RETURN QUERY
     SELECT bib,
            SUM( holds * GREATEST( iscale * (iage - hage), 1.0 ))
      FROM (
         SELECT f.id AS bib,
                (1 + EXTRACT(EPOCH FROM AGE(h.request_time)) / iint)::INT AS hage,
                COUNT(h.id)::INT AS holds
          FROM  action.hold_request h
                JOIN reporter.hold_request_record rhrr ON (rhrr.id = h.id)
                JOIN precalc_bib_list f ON (f.id = rhrr.bib_record)
          WHERE h.request_time >= NOW() - badge.horizon_age
                AND h.request_lib = ANY (badge.orgs)
          GROUP BY 1, 2
      ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.current_hold_count(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT rhrr.bib_record AS bib,
            COUNT(DISTINCT h.id)::NUMERIC AS holds
      FROM  action.hold_request h
            JOIN reporter.hold_request_record rhrr ON (rhrr.id = h.id)
            JOIN action.hold_copy_map m ON (m.hold = h.id)
            JOIN precalc_copy_filter_bib_list cf ON (rhrr.bib_record = cf.id AND m.target_copy = cf.copy)
      WHERE h.fulfillment_time IS NULL
            AND h.request_lib = ANY (badge.orgs)
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.circs_over_time(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
    iage    INT     := 1;
    iint    INT     := NULL;
    iscale  NUMERIC := NULL;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    IF badge.horizon_age IS NULL THEN
        RAISE EXCEPTION 'Badge "%" with id % requires a horizon age but has none.',
            badge.name,
            badge.id;
    END IF;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    iint := EXTRACT(EPOCH FROM badge.importance_interval);
    IF badge.importance_age IS NOT NULL THEN
        iage := (EXTRACT(EPOCH FROM badge.importance_age) / iint)::INT;
    END IF;

    -- if iscale is smaller than 1, scaling slope will be shallow ... BEWARE!
    iscale := COALESCE(badge.importance_scale, 1.0);

    RETURN QUERY
     SELECT bib,
            SUM( circs * GREATEST( iscale * (iage - cage), 1.0 ))
      FROM (
         SELECT cn.record AS bib,
                (1 + EXTRACT(EPOCH FROM AGE(c.xact_start)) / iint)::INT AS cage,
                COUNT(c.id)::INT AS circs
          FROM  action.circulation c
                JOIN precalc_copy_filter_bib_list cf ON (c.target_copy = cf.copy)
                JOIN asset.copy cp ON (cp.id = c.target_copy)
                JOIN asset.call_number cn ON (cn.id = cp.call_number)
          WHERE c.xact_start >= NOW() - badge.horizon_age
                AND cn.owning_lib = ANY (badge.orgs)
                AND c.phone_renewal IS FALSE  -- we don't count renewals
                AND c.desk_renewal IS FALSE
                AND c.opac_renewal IS FALSE
          GROUP BY 1, 2
      ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.current_circ_count(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT cn.record AS bib,
            COUNT(c.id)::NUMERIC AS circs
      FROM  action.circulation c
            JOIN precalc_copy_filter_bib_list cf ON (c.target_copy = cf.copy)
            JOIN asset.copy cp ON (cp.id = c.target_copy)
            JOIN asset.call_number cn ON (cn.id = cp.call_number)
      WHERE c.checkin_time IS NULL
            AND cn.owning_lib = ANY (badge.orgs)
      GROUP BY 1;

END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.checked_out_total_ratio(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT bib,
            SUM(checked_out)::NUMERIC / SUM(total)::NUMERIC
      FROM  (SELECT cn.record AS bib,
                    (cp.status = 1)::INT AS checked_out,
                    1 AS total
              FROM  asset.copy cp
                    JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
                    JOIN asset.call_number cn ON (cn.id = cp.call_number)
              WHERE cn.owning_lib = ANY (badge.orgs)
            ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.holds_total_ratio(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT cn.record AS bib,
            COUNT(DISTINCT m.hold)::NUMERIC / COUNT(DISTINCT cp.id)::NUMERIC
      FROM  asset.copy cp
            JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
            JOIN asset.call_number cn ON (cn.id = cp.call_number)
            JOIN action.hold_copy_map m ON (m.target_copy = cp.id)
      WHERE cn.owning_lib = ANY (badge.orgs)
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.holds_holdable_ratio(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT cn.record AS bib,
            COUNT(DISTINCT m.hold)::NUMERIC / COUNT(DISTINCT cp.id)::NUMERIC
      FROM  asset.copy cp
            JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
            JOIN asset.copy_location cl ON (cl.id = cp.location)
            JOIN config.copy_status cs ON (cs.id = cp.status)
            JOIN asset.call_number cn ON (cn.id = cp.call_number)
            JOIN action.hold_copy_map m ON (m.target_copy = cp.id)
      WHERE cn.owning_lib = ANY (badge.orgs)
            AND cp.holdable IS TRUE
            AND cl.holdable IS TRUE
            AND cs.holdable IS TRUE
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.bib_record_age(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy_or_uri(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bib_list;
    CREATE TEMP TABLE precalc_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_or_uri_list;

    RETURN QUERY
     SELECT b.id,
            1.0 / EXTRACT(EPOCH FROM AGE(b.create_date))::NUMERIC + 1.0
      FROM  precalc_bib_list pop
            JOIN biblio.record_entry b ON (b.id = pop.id);
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.bib_pub_age(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy_or_uri(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bib_list;
    CREATE TEMP TABLE precalc_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_or_uri_list;

    RETURN QUERY
     SELECT pop.id AS bib,
            s.value::NUMERIC
      FROM  precalc_bib_list pop
            JOIN metabib.record_sorter s ON (
                s.source = pop.id
                AND s.attr = 'pubdate'
                AND s.value ~ '^\d+$'
            )
      WHERE s.value::INT <= EXTRACT(YEAR FROM NOW())::INT;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.percent_time_circulating(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT bib,
            SUM(COALESCE(circ_time,0))::NUMERIC / SUM(age)::NUMERIC
      FROM  (SELECT cn.record AS bib,
                    cp.id,
                    EXTRACT( EPOCH FROM AGE(cp.active_date) ) + 1 AS age,
                    SUM(  -- time copy spent circulating
                        EXTRACT(
                            EPOCH FROM
                            AGE(
                                COALESCE(circ.checkin_time, circ.stop_fines_time, NOW()),
                                circ.xact_start
                            )
                        )
                    )::NUMERIC AS circ_time
              FROM  asset.copy cp
                    JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
                    JOIN asset.call_number cn ON (cn.id = cp.call_number)
                    LEFT JOIN action.all_circulation_slim circ ON (
                        circ.target_copy = cp.id
                        AND stop_fines NOT IN (
                            'LOST',
                            'LONGOVERDUE',
                            'CLAIMSRETURNED',
                            'LONGOVERDUE'
                        )
                        AND NOT (
                            checkin_time IS NULL AND
                            stop_fines = 'MAXFINES'
                        )
                    )
              WHERE cn.owning_lib = ANY (badge.orgs)
                    AND cp.active_date IS NOT NULL
                    -- Next line requires that copies with no circs (circ.id IS NULL) also not be deleted
                    AND ((circ.id IS NULL AND NOT cp.deleted) OR circ.id IS NOT NULL)
              GROUP BY 1,2,3
            ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.generic_fixed_rating_by_copy(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
BEGIN
    PERFORM rating.precalc_bibs_by_copy(badge_id);
    RETURN QUERY
        SELECT id, 1.0 FROM precalc_filter_bib_list
            INTERSECT
        SELECT id, 1.0 FROM precalc_bibs_by_copy_list;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.generic_fixed_rating_by_uri(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
BEGIN
    PERFORM rating.precalc_bibs_by_uri(badge_id);
    RETURN QUERY
        SELECT id, 1.0 FROM precalc_bib_filter_bib_list
            INTERSECT
        SELECT id, 1.0 FROM precalc_bibs_by_uri_list;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.generic_fixed_rating_by_copy_or_uri(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
BEGIN
    PERFORM rating.precalc_bibs_by_copy_or_uri(badge_id);
    RETURN QUERY
        (SELECT id, 1.0 FROM precalc_filter_bib_list
            INTERSECT
        SELECT id, 1.0 FROM precalc_bibs_by_copy_list)
            UNION
        (SELECT id, 1.0 FROM precalc_bib_filter_bib_list
            INTERSECT
        SELECT id, 1.0 FROM precalc_bibs_by_uri_list);
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.generic_fixed_rating_global(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
BEGIN
    RETURN QUERY
        SELECT id, 1.0 FROM precalc_bib_filter_bib_list;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.copy_count(badge_id INT)
    RETURNS TABLE (record INT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );
    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT f.id::INT AS bib,
            COUNT(f.copy)::NUMERIC
      FROM  precalc_copy_filter_bib_list f
            JOIN asset.copy cp ON (f.copy = cp.id)
            JOIN asset.call_number cn ON (cn.id = cp.call_number)
      WHERE cn.owning_lib = ANY (badge.orgs) GROUP BY 1;

END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.org_unit_count(badge_id INT)
    RETURNS TABLE (record INT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );
    ANALYZE precalc_copy_filter_bib_list;

    -- Use circ rather than owning lib here as that means "on the shelf at..."
    RETURN QUERY
     SELECT f.id::INT AS bib,
            COUNT(DISTINCT cp.circ_lib)::NUMERIC
     FROM asset.copy cp
          JOIN precalc_copy_filter_bib_list f ON (cp.id = f.copy)
     WHERE cp.circ_lib = ANY (badge.orgs) GROUP BY 1;

END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.inhouse_over_time(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
    iage    INT     := 1;
    iint    INT     := NULL;
    iscale  NUMERIC := NULL;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    IF badge.horizon_age IS NULL THEN
        RAISE EXCEPTION 'Badge "%" with id % requires a horizon age but has none.',
            badge.name,
            badge.id;
    END IF;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    iint := EXTRACT(EPOCH FROM badge.importance_interval);
    IF badge.importance_age IS NOT NULL THEN
        iage := (EXTRACT(EPOCH FROM badge.importance_age) / iint)::INT;
    END IF;

    -- if iscale is smaller than 1, scaling slope will be shallow ... BEWARE!
    iscale := COALESCE(badge.importance_scale, 1.0);

    RETURN QUERY
     SELECT bib,
            SUM( uses * GREATEST( iscale * (iage - cage), 1.0 ))
      FROM (
         SELECT cn.record AS bib,
                (1 + EXTRACT(EPOCH FROM AGE(u.use_time)) / iint)::INT AS cage,
                COUNT(u.id)::INT AS uses
          FROM  action.in_house_use u
                JOIN precalc_copy_filter_bib_list cf ON (u.item = cf.copy)
                JOIN asset.copy cp ON (cp.id = u.item)
                JOIN asset.call_number cn ON (cn.id = cp.call_number)
          WHERE u.use_time >= NOW() - badge.horizon_age
                AND cn.owning_lib = ANY (badge.orgs)
          GROUP BY 1, 2
      ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

COMMIT;

