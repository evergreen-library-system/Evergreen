BEGIN;

/*
 * Use pgmemcache and memcached to increase the speed of org tree traversal
 * ------------------------------------------------------------------------
 *
 * This set of functions allows the use of memcached as a caching mechanism for
 * org tree traversal checks.  It is transparent and optional.  If memcache is
 * not set up, either by not running or the lack of the pgmemcache postgres
 * addon, then the default, existing behaviour is preserved and live database
 * queries are used to test all org tree traversals.
 *
 * This Evergreen addon extention requires the pgmemcache-perm_cache.sql to be
 * installed as well.  See that extention script for details on pgmemcache
 * setup and installation.
 *
 * TODO: Make the cache timeout configurable via a global setting for EG 2.0
 *
 */


CREATE OR REPLACE FUNCTION actor.org_unit_descendants ( INT, INT ) RETURNS SETOF actor.org_unit AS $$
    SELECT  *
      FROM  actor.org_unit_descendants(
                CASE WHEN $2 IS NOT NULL THEN
                    (actor.org_unit_ancestor_at_depth($1,$2)).id
                ELSE 
                    $1
                END
    );
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.noncached_org_unit_descendants ( org INT ) RETURNS SETOF actor.org_unit AS $$
DECLARE
    kid             actor.org_unit%ROWTYPE;
    curr_org        actor.org_unit%ROWTYPE;
BEGIN

    SELECT * INTO curr_org FROM actor.org_unit WHERE id = org;
    RETURN NEXT curr_org;

    FOR kid IN SELECT * FROM actor.org_unit WHERE parent_ou = org LOOP
        FOR curr_org IN SELECT * FROM actor.noncached_org_unit_descendants(kid.id) LOOP
            RETURN NEXT curr_org;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION actor.org_unit_descendants ( org INT ) RETURNS SETOF actor.org_unit AS $func$
DECLARE
    kid             actor.org_unit%ROWTYPE;
    curr_org        actor.org_unit%ROWTYPE;
    idlist          INT[] := '{}'::INT[];
    cached_value    RECORD;
BEGIN

    IF org IS NULL THEN
        RETURN;
    END IF;

    IF permission.mc_init() THEN
        -- RAISE NOTICE 'Getting perm from cache';
        EXECUTE $$SELECT memcache_get('oils_orgcache_$$ || org || $$') AS x;$$ INTO cached_value;

        IF cached_value.x IS NOT NULL AND cached_value.x <> '' THEN
            FOR curr_org IN
                SELECT  *
                  FROM  actor.org_unit
                  WHERE id IN ( SELECT * FROM unnest( STRING_TO_ARRAY( cached_value.x, ',' ) ) )
            LOOP
                RETURN NEXT curr_org;
            END LOOP;
    
            RETURN;
        END IF;

    END IF;

    SELECT * INTO curr_org FROM actor.org_unit WHERE id = org;
    RETURN NEXT curr_org;

    idlist := ARRAY_APPEND( idlist, curr_org.id );

    FOR kid IN SELECT * FROM actor.org_unit WHERE parent_ou = org LOOP
        FOR curr_org IN SELECT * FROM actor.noncached_org_unit_descendants(kid.id) LOOP
            RETURN NEXT curr_org;
            idlist := ARRAY_APPEND( idlist, curr_org.id );
        END LOOP;
    END LOOP;

    IF permission.mc_init() THEN
        EXECUTE $$
            SELECT memcache_set(
                'oils_orgcache_$$ || org || $$',
                $$ || QUOTE_LITERAL(ARRAY_TO_STRING(idlist,',')) || $$,
                '10 minutes'::INTERVAL
            );
        $$;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

