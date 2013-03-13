
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0774', :eg_version);

CREATE TABLE config.z3950_source_credentials (
    id SERIAL PRIMARY KEY,
    owner INTEGER NOT NULL REFERENCES actor.org_unit(id),
    source TEXT NOT NULL REFERENCES config.z3950_source(name) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
    -- do some Z servers require a username but no password or vice versa?
    username TEXT,
    password TEXT,
    CONSTRAINT czsc_source_once_per_lib UNIQUE (source, owner)
);

-- find the most relevant set of credentials for the Z source and org
CREATE OR REPLACE FUNCTION config.z3950_source_credentials_lookup
        (source TEXT, owner INTEGER) 
        RETURNS config.z3950_source_credentials AS $$

    SELECT creds.* 
    FROM config.z3950_source_credentials creds
        JOIN actor.org_unit aou ON (aou.id = creds.owner)
        JOIN actor.org_unit_type aout ON (aout.id = aou.ou_type)
    WHERE creds.source = $1 AND creds.owner IN ( 
        SELECT id FROM actor.org_unit_ancestors($2) 
    )
    ORDER BY aout.depth DESC LIMIT 1;

$$ LANGUAGE SQL STABLE;

-- since we are not exposing config.z3950_source_credentials
-- via the IDL, providing a stored proc gives us a way to
-- set values in the table via cstore
CREATE OR REPLACE FUNCTION config.z3950_source_credentials_apply
        (src TEXT, org INTEGER, uname TEXT, passwd TEXT) 
        RETURNS VOID AS $$
BEGIN
    PERFORM 1 FROM config.z3950_source_credentials
        WHERE owner = org AND source = src;

    IF FOUND THEN
        IF COALESCE(uname, '') = '' AND COALESCE(passwd, '') = '' THEN
            DELETE FROM config.z3950_source_credentials 
                WHERE owner = org AND source = src;
        ELSE 
            UPDATE config.z3950_source_credentials 
                SET username = uname, password = passwd
                WHERE owner = org AND source = src;
        END IF;
    ELSE
        IF COALESCE(uname, '') <> '' OR COALESCE(passwd, '') <> '' THEN
            INSERT INTO config.z3950_source_credentials
                (source, owner, username, password) 
                VALUES (src, org, uname, passwd);
        END IF;
    END IF;
END;
$$ LANGUAGE PLPGSQL;


COMMIT;
