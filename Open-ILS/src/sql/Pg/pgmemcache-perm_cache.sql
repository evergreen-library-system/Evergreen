BEGIN;

/*
 * Use pgmemcache and memcached to increase the speed of permission tests
 * ----------------------------------------------------------------------
 *
 * This set of functions allows the use of memcached as a caching mechanism for
 * permission checks.  It is transparent and optional.  If memcache is not set
 * up, either by not running or the lack of the pgmemcache postgres addon,
 * then the default, existing behaviour is preserved and live database queries
 * are used to test all permissions.
 *
 *
 * On postgres 8.2 and before, pgmemcache 1.1 is required.  For this older
 * version of pgmemcache, configuration of memcached servers is performed by
 * stored procs.  Therefore, the installer of this Evergreen addition must
 * edit the stored proc called permission.old_mc_servers() to initialize the
 * appropriate set of memcached servers.  For simple, single-database
 * installations, the default of 'localhost' is most likely the desired
 * setting.
 *
 *
 * On postgres 8.3 and later, pgmemcache 2.x is required.  In this new
 * pgmemcache the server configuration is controlled from within the
 * postgresql.conf file via user-defined variables read by the pgmemcache
 * intialization routines.  Please see the README for pgmemcache at
 *
 *    http://cvs.pgfoundry.org/cgi-bin/cvsweb.cgi/pgmemcache/pgmemcache/README.pgmemcache?rev=1.21&content-type=text/plain
 *
 * or in the release tarball that was installed for details on configuration.
 *
 *
 * TODO: Make the cache timeout configurable via a global setting for EG 2.0
 *
 */

CREATE OR REPLACE FUNCTION permission.old_mc_servers() RETURNS BOOL AS $f$
BEGIN
    PERFORM memcache_server_add('localhost', '11211');
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION permission.mc_init() RETURNS BOOL AS $f$
DECLARE
    old_memcache BOOL;
BEGIN
    old_memcache = FALSE;
    IF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT < 8.3 THEN
        old_memcache = TRUE;
        IF memcache_init() THEN
            PERFORM permission.old_mc_servers();
        END IF;
        -- RAISE NOTICE 'Old postgres, must be old pgmemcache';
    ELSE
        BEGIN
            old_memcache = TRUE; 
            IF memcache_init() THEN
                PERFORM permission.old_mc_servers();
            END IF;
            -- RAISE NOTICE 'New postgres, but old pgmemcache';
        EXCEPTION WHEN OTHERS THEN
            old_memcache = FALSE;
        END;
    END IF;

    IF NOT old_memcache THEN
        PERFORM current_setting('pgmemcache.default_servers');
        -- RAISE NOTICE 'New postgres, new pgmemcache';
    END IF;

    -- no exception, we're good
    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION permission.set_cached_perm( iusr INT, tperm TEXT, iorg INT, bool_value BOOL, timeout INTERVAL ) RETURNS BOOL AS $f$
BEGIN
    IF permission.mc_init() THEN
        -- RAISE NOTICE 'Setting perm cache';
        IF bool_value THEN
            EXECUTE $$SELECT memcache_set('oils_permcache_$$ || iusr || tperm || iorg || $$', 't',$$ || quote_literal(timeout) || $$::INTERVAL);$$;
        ELSE
            EXECUTE $$SELECT memcache_set('oils_permcache_$$ || iusr || tperm || iorg || $$', 'f',$$ || quote_literal(timeout) || $$::INTERVAL);$$;
        END IF;
    END IF;

    RETURN bool_value;
EXCEPTION WHEN OTHERS THEN
    RETURN bool_value;
END;
$f$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION permission.set_cached_perm( iusr INT, tperm TEXT, iorg INT, bool_value BOOL ) RETURNS BOOL AS $f$
    SELECT permission.set_cached_perm( $1, $2, $3, $4, '10 minutes'::INTERVAL);
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION permission.check_cached_perm( iusr INT, tperm TEXT, iorg INT ) RETURNS BOOL AS $f$
DECLARE
    cached_value  RECORD;
    bool_value    BOOL;
BEGIN
    IF permission.mc_init() THEN
        -- RAISE NOTICE 'Getting perm from cache';
        EXECUTE $$SELECT memcache_get('oils_permcache_$$ || iusr || tperm || iorg || $$') AS x;$$ INTO cached_value;
        bool_value := cached_value.x = 't';
    END IF;

    RETURN bool_value;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$f$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION permission.usr_has_perm ( INT, TEXT, INT ) RETURNS BOOL AS $f$
    SELECT  CASE
            WHEN permission.check_cached_perm( $1, $2, $3 ) IS NOT NULL THEN permission.check_cached_perm( $1, $2, $3 )
            WHEN permission.set_cached_perm($1, $2, $3, permission.usr_has_home_perm( $1, $2, $3 )) THEN TRUE
            WHEN permission.set_cached_perm($1, $2, $3, permission.usr_has_work_perm( $1, $2, $3 )) THEN TRUE
            ELSE FALSE
        END;
$f$ LANGUAGE SQL;

COMMIT;

