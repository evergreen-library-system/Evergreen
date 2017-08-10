BEGIN;

SELECT evergreen.upgrade_deps_block_check('1053', :eg_version);

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

INSERT INTO rating.popularity_parameter (id, name, func, require_percentile) VALUES
    (17,'Circulation Library Count', 'rating.org_unit_count', TRUE);

COMMIT;

