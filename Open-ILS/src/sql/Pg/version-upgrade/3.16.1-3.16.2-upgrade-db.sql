--Upgrade Script for 3.16.1 to 3.16.2
\set eg_version '''3.16.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.16.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1505', :eg_version);

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
        SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_i_rl.limit_interval) - NOW())) INTO i_wait
          FROM  (SELECT l.attempt_time,
                        COUNT(*) OVER (PARTITION BY l.ip_addr ORDER BY l.attempt_time DESC) AS running_count
                  FROM  openapi.endpoint_access_attempt_log l
                  WHERE l.endpoint = target_endpoint
                        AND l.ip_addr = from_ip_addr
                        AND l.attempt_time > NOW() - def_i_rl.limit_interval
                ) x
          WHERE running_count = def_i_rl.limit_count;
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
        SELECT  CEIL(EXTRACT(EPOCH FROM (x.attempt_time + def_i_rl.limit_interval) - NOW())) INTO i_wait
          FROM  (SELECT l.attempt_time,
                        COUNT(*) OVER (PARTITION BY l.ip_addr ORDER BY l.attempt_time DESC) AS running_count
                  FROM  openapi.authen_attempt_log l
                  WHERE l.ip_addr = from_ip_addr
                        AND l.attempt_time > NOW() - def_i_rl.limit_interval
                ) x
          WHERE running_count = def_i_rl.limit_count;
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



SELECT evergreen.upgrade_deps_block_check('1506', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.setup_delete_protect_rule (
    t_schema TEXT,
    t_table TEXT,
    t_additional TEXT DEFAULT '',
    t_pkey TEXT DEFAULT 'id',
    t_deleted TEXT DEFAULT 'deleted'
) RETURNS VOID AS $$
DECLARE
    rule_name   TEXT;
    table_name  TEXT;
    fq_pkey     TEXT;
BEGIN

    rule_name := 'protect_' || t_schema || '_' || t_table || '_delete';
    table_name := t_schema || '.' || t_table;
    fq_pkey := table_name || '.' || t_pkey;

    EXECUTE 'DROP RULE IF EXISTS ' || rule_name || ' ON ' || table_name;
    EXECUTE 'CREATE RULE ' || rule_name
            || ' AS ON DELETE TO ' || table_name
            || ' DO INSTEAD (UPDATE ' || table_name
            || '   SET ' || t_deleted || ' = TRUE '
            || '   WHERE OLD.' || t_pkey || ' = ' || fq_pkey
            || '   ; ' || t_additional || ')';

END;
$$ STRICT LANGUAGE PLPGSQL;

-- Open-ILS/src/sql/Pg/005.schema.actors.sql
DROP RULE IF EXISTS protect_user_delete ON actor.usr;
SELECT evergreen.setup_delete_protect_rule('actor','usr');

DROP RULE IF EXISTS protect_usr_message_delete ON actor.usr_message;
SELECT evergreen.setup_delete_protect_rule('actor','usr_message');

-- Open-ILS/src/sql/Pg/011.schema.authority.sql
DROP RULE IF EXISTS protect_authority_rec_delete ON authority.record_entry;
SELECT evergreen.setup_delete_protect_rule('authority','record_entry','DELETE FROM authority.full_rec WHERE record = OLD.id');

-- Open-ILS/src/sql/Pg/040.schema.asset.sql
DROP RULE IF EXISTS protect_copy_delete ON asset.copy;
SELECT evergreen.setup_delete_protect_rule('asset','copy');

DROP RULE IF EXISTS protect_cn_delete ON asset.call_number;
SELECT evergreen.setup_delete_protect_rule('asset','call_number');

-- Open-ILS/src/sql/Pg/210.schema.serials.sql
DROP RULE IF EXISTS protect_mfhd_delete ON serial.record_entry;
SELECT evergreen.setup_delete_protect_rule('serial','record_entry');

DROP RULE IF EXISTS protect_serial_unit_delete ON serial.unit;
SELECT evergreen.setup_delete_protect_rule('serial','unit');

-- Open-ILS/src/sql/Pg/800.fkeys.sql
DROP RULE IF EXISTS protect_bib_rec_delete ON biblio.record_entry;
SELECT evergreen.setup_delete_protect_rule('biblio','record_entry');

DROP RULE IF EXISTS protect_mono_part_delete ON biblio.record_entry;
SELECT evergreen.setup_delete_protect_rule('biblio','monograph_part','DELETE FROM asset.copy_part_map WHERE part = OLD.id');

DROP RULE IF EXISTS protect_copy_location_delete ON asset.copy_location;
SELECT evergreen.setup_delete_protect_rule(
    'asset', 'copy_location',
    'SELECT asset.check_delete_copy_location(OLD.id);'
      || ' UPDATE acq.lineitem_detail SET location = NULL WHERE location = OLD.id;'
      || ' DELETE FROM asset.copy_location_order WHERE location = OLD.id;'
      || ' DELETE FROM asset.copy_location_group_map WHERE location = OLD.id;'
      || ' DELETE FROM config.circ_limit_set_copy_loc_map WHERE copy_loc = OLD.id;'
);


COMMIT;
