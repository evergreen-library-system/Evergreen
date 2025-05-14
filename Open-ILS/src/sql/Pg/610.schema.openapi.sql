BEGIN;

DROP SCHEMA IF EXISTS openapi CASCADE;
CREATE SCHEMA IF NOT EXISTS openapi;

CREATE TABLE IF NOT EXISTS openapi.integrator (
    id      INT     PRIMARY KEY REFERENCES actor.usr (id),
    enabled BOOL    NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS openapi.json_schema_datatype (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE IF NOT EXISTS openapi.json_schema_format (
    name        TEXT    PRIMARY KEY,
    label       TEXT    NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE IF NOT EXISTS openapi.rate_limit_definition (
    id              SERIAL      PRIMARY KEY,
    name            TEXT        UNIQUE NOT NULL, -- i18n
    limit_interval  INTERVAL    NOT NULL,
    limit_count     INT         NOT NULL
);
SELECT SETVAL('openapi.rate_limit_definition_id_seq'::TEXT, 100);

CREATE TABLE IF NOT EXISTS openapi.endpoint (
    operation_id    TEXT    PRIMARY KEY,
    path            TEXT    NOT NULL,
    http_method     TEXT    NOT NULL CHECK (http_method IN ('get','put','post','delete','patch')),
    security        TEXT    NOT NULL DEFAULT 'bearerAuth' CHECK (security IN ('bearerAuth','basicAuth','cookieAuth','paramAuth')),
    summary         TEXT    NOT NULL,
    method_source   TEXT    NOT NULL, -- perl module or opensrf application, tested by regex and assumes opensrf app name contains a "."
    method_name     TEXT    NOT NULL,
    method_params   TEXT,             -- eg, 'eg_auth_token hold' or 'eg_auth_token eg_user_id circ req.json'
    active          BOOL    NOT NULL DEFAULT TRUE,
    rate_limit      INT     REFERENCES openapi.rate_limit_definition (id),
    CONSTRAINT path_and_method_once UNIQUE (path, http_method)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_param (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    name            TEXT    NOT NULL CHECK (name ~ '^\w+$'),
    required        BOOL    NOT NULL DEFAULT FALSE,
    in_part         TEXT    NOT NULL DEFAULT 'query' CHECK (in_part IN ('path','query','header','cookie')),
    fm_type         TEXT,
    schema_type     TEXT    REFERENCES openapi.json_schema_datatype (name),
    schema_format   TEXT    REFERENCES openapi.json_schema_format (name),
    array_items     TEXT    REFERENCES openapi.json_schema_datatype (name),
    default_value   TEXT,
    CONSTRAINT endpoint_and_name_once UNIQUE (endpoint, name),
    CONSTRAINT format_requires_type CHECK (schema_format IS NULL OR schema_type IS NOT NULL),
    CONSTRAINT array_items_requires_array_type CHECK (array_items IS NULL OR schema_type = 'array')
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_response (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    validate        BOOL    NOT NULL DEFAULT TRUE,
    status          INT     NOT NULL DEFAULT 200,
    content_type    TEXT    NOT NULL DEFAULT 'application/json',
    description     TEXT    NOT NULL DEFAULT 'Success',
    fm_type         TEXT,
    schema_type     TEXT    REFERENCES openapi.json_schema_datatype (name),
    schema_format   TEXT    REFERENCES openapi.json_schema_format (name),
    array_items     TEXT    REFERENCES openapi.json_schema_datatype (name),
    CONSTRAINT endpoint_status_content_type_once UNIQUE (endpoint, status, content_type)
);

CREATE TABLE IF NOT EXISTS openapi.perm_set (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    NOT NULL
); -- push sequence value
SELECT SETVAL('openapi.perm_set_id_seq'::TEXT, 1001);

CREATE TABLE IF NOT EXISTS openapi.perm_set_perm_map (
    id          SERIAL  PRIMARY KEY,
    perm_set    INT     NOT NULL REFERENCES openapi.perm_set (id) ON UPDATE CASCADE ON DELETE CASCADE,
    perm        INT     NOT NULL REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_perm_set_map (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint(operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    perm_set        INT     NOT NULL REFERENCES openapi.perm_set (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set (
    name            TEXT    PRIMARY KEY,
    description     TEXT    NOT NULL,
    active          BOOL    NOT NULL DEFAULT TRUE,
    rate_limit      INT     REFERENCES openapi.rate_limit_definition (id)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_user_rate_limit_map (
    id              SERIAL  PRIMARY KEY,
    accessor        INT     NOT NULL REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    rate_limit      INT     NOT NULL REFERENCES openapi.rate_limit_definition (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_accessor_once UNIQUE (accessor, endpoint)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_user_rate_limit_map (
    id              SERIAL  PRIMARY KEY,
    accessor        INT     NOT NULL REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    rate_limit      INT     NOT NULL REFERENCES openapi.rate_limit_definition (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_set_accessor_once UNIQUE (accessor, endpoint_set)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_ip_rate_limit_map (
    id              SERIAL  PRIMARY KEY,
    ip_range        INET    NOT NULL,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    rate_limit      INT     NOT NULL REFERENCES openapi.rate_limit_definition (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_ip_range_once UNIQUE (ip_range, endpoint)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_ip_rate_limit_map (
    id              SERIAL  PRIMARY KEY,
    ip_range        INET    NOT NULL,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    rate_limit      INT     NOT NULL REFERENCES openapi.rate_limit_definition (id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_set_ip_range_once UNIQUE (ip_range, endpoint_set)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_endpoint_map (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT endpoint_set_endpoint_once UNIQUE (endpoint_set, endpoint)
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_perm_map (
    id              SERIAL  PRIMARY KEY,
    endpoint        TEXT    NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    perm            INT     NOT NULL REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_perm_set_map (
    id              SERIAL  PRIMARY KEY,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    perm_set        INT     NOT NULL REFERENCES openapi.perm_set (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS openapi.endpoint_set_perm_map (
    id              SERIAL  PRIMARY KEY,
    endpoint_set    TEXT    NOT NULL REFERENCES openapi.endpoint_set (name) ON UPDATE CASCADE ON DELETE CASCADE,
    perm            INT     NOT NULL REFERENCES permission.perm_list (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS openapi.authen_attempt_log (
    request_id      TEXT        PRIMARY KEY,
    attempt_time    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ip_addr         INET,
    cred_user       TEXT,
    token           TEXT
);
CREATE INDEX authen_cred_user_attempt_time_idx ON openapi.authen_attempt_log (attempt_time, cred_user);
CREATE INDEX authen_ip_addr_attempt_time_idx ON openapi.authen_attempt_log (attempt_time, ip_addr);

CREATE TABLE IF NOT EXISTS openapi.endpoint_access_attempt_log (
    request_id      TEXT        PRIMARY KEY,
    attempt_time    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    endpoint        TEXT        NOT NULL REFERENCES openapi.endpoint (operation_id) ON UPDATE CASCADE ON DELETE CASCADE,
    allowed         BOOL        NOT NULL,
    ip_addr         INET,
    accessor        INT         REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    token           TEXT
);
CREATE INDEX access_accessor_attempt_time_idx ON openapi.endpoint_access_attempt_log (accessor, attempt_time);

CREATE TABLE IF NOT EXISTS openapi.endpoint_dispatch_log (
    request_id      TEXT        PRIMARY KEY,
    complete_time   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    error           BOOL        NOT NULL
);

CREATE OR REPLACE FUNCTION openapi.find_default_endpoint_rate_limit (target_endpoint TEXT) RETURNS openapi.rate_limit_definition AS $f$
DECLARE
    def_rl    openapi.rate_limit_definition%ROWTYPE;
BEGIN
    -- Default rate limits can be applied at the endpoint or endpoint_set level;
    -- endpoint overrides endpoint_set, and we choose the most restrictive from
    -- the set if we have to look there.
    SELECT  d.* INTO def_rl
      FROM  openapi.rate_limit_definition d
            JOIN openapi.endpoint e ON (e.rate_limit = d.id)
      WHERE e.operation_id = target_endpoint;

    IF NOT FOUND THEN
        SELECT  d.* INTO def_rl
          FROM  openapi.rate_limit_definition d
                JOIN openapi.endpoint_set es ON (es.rate_limit = d.id)
                JOIN openapi.endpoint_set_endpoint_map m ON (es.name = m.endpoint_set AND m.endpoint = target_endpoint)
           -- This ORDER BY calculates the avg time between requests the user would have to wait to perfectly
           -- avoid rate limiting.  So, a bigger wait means it's more restrictive.  We take the most restrictive
           -- set-applied one.
          ORDER BY EXTRACT(EPOCH FROM d.limit_interval) / d.limit_count::NUMERIC DESC
          LIMIT 1;
    END IF;

    -- If there's no default for the endpoint or set, we provide 1/sec.
    IF NOT FOUND THEN
        def_rl.limit_interval := '1 second'::INTERVAL;
        def_rl.limit_count := 1;
    END IF;

    RETURN def_rl;
END;
$f$ STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION openapi.find_user_endpoint_rate_limit (target_endpoint TEXT, accessing_usr INT) RETURNS openapi.rate_limit_definition AS $f$
DECLARE
    def_u_rl    openapi.rate_limit_definition%ROWTYPE;
BEGIN
    SELECT  d.* INTO def_u_rl
      FROM  openapi.rate_limit_definition d
            JOIN openapi.endpoint_user_rate_limit_map e ON (e.rate_limit = d.id)
      WHERE e.endpoint = target_endpoint
            AND e.accessor = accessing_usr;

    IF NOT FOUND THEN
        SELECT  d.* INTO def_u_rl
          FROM  openapi.rate_limit_definition d
                JOIN openapi.endpoint_set_user_rate_limit_map e ON (e.rate_limit = d.id AND e.accessor = accessing_usr)
                JOIN openapi.endpoint_set_endpoint_map m ON (e.endpoint_set = m.endpoint_set AND m.endpoint = target_endpoint)
          ORDER BY EXTRACT(EPOCH FROM d.limit_interval) / d.limit_count::NUMERIC DESC
          LIMIT 1;
    END IF;

    RETURN def_u_rl;
END;
$f$ STABLE LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION openapi.find_ip_addr_endpoint_rate_limit (target_endpoint TEXT, from_ip_addr INET) RETURNS openapi.rate_limit_definition AS $f$
DECLARE
    def_i_rl    openapi.rate_limit_definition%ROWTYPE;
BEGIN
    SELECT  d.* INTO def_i_rl
      FROM  openapi.rate_limit_definition d
            JOIN openapi.endpoint_ip_rate_limit_map e ON (e.rate_limit = d.id)
      WHERE e.endpoint = target_endpoint
            AND e.ip_range && from_ip_addr
       -- For IPs, we order first by the size of the ranges that we
       -- matched (mask length), most specific (smallest block of IPs)
       -- first, then by the restrictiveness of the limit, more restrictive first.
      ORDER BY MASKLEN(e.ip_range) DESC, EXTRACT(EPOCH FROM d.limit_interval) / d.limit_count::NUMERIC DESC
      LIMIT 1;

    IF NOT FOUND THEN
        SELECT  d.* INTO def_i_rl
          FROM  openapi.rate_limit_definition d
                JOIN openapi.endpoint_set_ip_rate_limit_map e ON (e.rate_limit = d.id AND ip_range && from_ip_addr)
                JOIN openapi.endpoint_set_endpoint_map m ON (e.endpoint_set = m.endpoint_set AND m.endpoint = target_endpoint)
          ORDER BY MASKLEN(e.ip_range) DESC, EXTRACT(EPOCH FROM d.limit_interval) / d.limit_count::NUMERIC DESC
          LIMIT 1;
    END IF;

    RETURN def_i_rl;
END;
$f$ STABLE LANGUAGE PLPGSQL;

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
