BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

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

COMMIT;

