BEGIN;

SELECT evergreen.upgrade_deps_block_check('1052', :eg_version);

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

INSERT INTO rating.popularity_parameter (id, name, func, require_horizon,require_percentile) VALUES
    (18,'In-House Use Over Time', 'rating.inhouse_over_time', TRUE, TRUE);

COMMIT;

