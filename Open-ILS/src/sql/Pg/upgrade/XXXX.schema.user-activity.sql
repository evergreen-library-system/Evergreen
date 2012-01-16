-- Evergreen DB patch XXXX.schema.user-activity.sql
--
BEGIN;

-- check whether patch can be applied
-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

-- SCHEMA --

CREATE TYPE config.usr_activity_group AS ENUM ('authen','authz','circ','hold','search');

CREATE TABLE config.usr_activity_type (
    id          SERIAL                      PRIMARY KEY, 
    ewho        TEXT,
    ewhat       TEXT,
    ehow        TEXT,
    label       TEXT                        NOT NULL, -- i18n
    egroup      config.usr_activity_group   NOT NULL,
    enabled     BOOL                        NOT NULL DEFAULT TRUE,
    transient   BOOL                        NOT NULL DEFAULT FALSE,
    CONSTRAINT  one_of_wwh CHECK (COALESCE(ewho,ewhat,ehow) IS NOT NULL)
);

CREATE UNIQUE INDEX unique_wwh ON config.usr_activity_type 
    (COALESCE(ewho,''), COALESCE (ewhat,''), COALESCE(ehow,''));

CREATE TABLE actor.usr_activity (
    id          BIGSERIAL   PRIMARY KEY,
    usr         INT         REFERENCES actor.usr (id) ON DELETE SET NULL,
    etype       INT         NOT NULL REFERENCES config.usr_activity_type (id),
    event_time  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- remove transient activity entries on insert of new entries
CREATE OR REPLACE FUNCTION actor.usr_activity_transient_trg () RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM actor.usr_activity USING config.usr_activity_type atype
        WHERE atype.transient AND NEW.etype = atype.id;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER remove_transient_usr_activity
    BEFORE INSERT ON actor.usr_activity
    FOR EACH ROW EXECUTE PROCEDURE actor.usr_activity_transient_trg();

-- given a set of activity criteria, find the most approprate activity type
CREATE OR REPLACE FUNCTION actor.usr_activity_get_type (
        ewho TEXT, 
        ewhat TEXT, 
        ehow TEXT
    ) RETURNS SETOF config.usr_activity_type AS $$
SELECT * FROM config.usr_activity_type 
    WHERE 
        enabled AND 
        (ewho  IS NULL OR ewho  = $1) AND
        (ewhat IS NULL OR ewhat = $2) AND
        (ehow  IS NULL OR ehow  = $3) 
    ORDER BY 
        -- BOOL comparisons sort false to true
        COALESCE(ewho, '')  != COALESCE($1, ''),
        COALESCE(ewhat,'')  != COALESCE($2, ''),
        COALESCE(ehow, '')  != COALESCE($3, '') 
    LIMIT 1;
$$ LANGUAGE SQL;

-- given a set of activity criteria, finds the best
-- activity type and inserts the activity entry
CREATE OR REPLACE FUNCTION actor.insert_usr_activity (
        usr INT,
        ewho TEXT, 
        ewhat TEXT, 
        ehow TEXT
    ) RETURNS SETOF actor.usr_activity AS $$
DECLARE
    new_row actor.usr_activity%ROWTYPE;
BEGIN
    SELECT id INTO new_row.etype FROM actor.usr_activity_get_type(ewho, ewhat, ehow);
    IF FOUND THEN
        new_row.usr := usr;
        INSERT INTO actor.usr_activity (usr, etype) 
            VALUES (usr, new_row.etype)
            RETURNING * INTO new_row;
        RETURN NEXT new_row;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- SEED DATA --

INSERT INTO config.usr_activity_type (id, ewho, ewhat, ehow, egroup, label) VALUES

     -- authen/authz actions
     -- note: "opensrf" is the default ingress/ehow
     (1,  NULL, 'login',  'opensrf',      'authen', oils_i18n_gettext(1 , 'Login via opensrf', 'cuat', 'label'))
    ,(2,  NULL, 'login',  'srfsh',        'authen', oils_i18n_gettext(2 , 'Login via srfsh', 'cuat', 'label'))
    ,(3,  NULL, 'login',  'gateway-v1',   'authen', oils_i18n_gettext(3 , 'Login via gateway-v1', 'cuat', 'label'))
    ,(4,  NULL, 'login',  'translator-v1','authen', oils_i18n_gettext(4 , 'Login via translator-v1', 'cuat', 'label'))
    ,(5,  NULL, 'login',  'xmlrpc',       'authen', oils_i18n_gettext(5 , 'Login via xmlrpc', 'cuat', 'label'))
    ,(6,  NULL, 'login',  'remoteauth',   'authen', oils_i18n_gettext(6 , 'Login via remoteauth', 'cuat', 'label'))
    ,(7,  NULL, 'login',  'sip2',         'authen', oils_i18n_gettext(7 , 'SIP2 Proxy Login', 'cuat', 'label'))
    ,(8,  NULL, 'login',  'apache',       'authen', oils_i18n_gettext(8 , 'Login via Apache module', 'cuat', 'label'))

    ,(9,  NULL, 'verify', 'opensrf',      'authz',  oils_i18n_gettext(9 , 'Verification via opensrf', 'cuat', 'label'))
    ,(10, NULL, 'verify', 'srfsh',        'authz',  oils_i18n_gettext(10, 'Verification via srfsh', 'cuat', 'label'))
    ,(11, NULL, 'verify', 'gateway-v1',   'authz',  oils_i18n_gettext(11, 'Verification via gateway-v1', 'cuat', 'label'))
    ,(12, NULL, 'verify', 'translator-v1','authz',  oils_i18n_gettext(12, 'Verification via translator-v1', 'cuat', 'label'))
    ,(13, NULL, 'verify', 'xmlrpc',       'authz',  oils_i18n_gettext(13, 'Verification via xmlrpc', 'cuat', 'label'))
    ,(14, NULL, 'verify', 'remoteauth',   'authz',  oils_i18n_gettext(14, 'Verification via remoteauth', 'cuat', 'label'))
    ,(15, NULL, 'verify', 'sip2',         'authz',  oils_i18n_gettext(15, 'SIP2 User Verification', 'cuat', 'label'))

     -- authen/authz actions w/ known uses of "who"
    ,(16, 'opac',        'login',  'gateway-v1',   'authen', oils_i18n_gettext(16, 'OPAC Login (jspac)', 'cuat', 'label'))
    ,(17, 'opac',        'login',  'apache',       'authen', oils_i18n_gettext(17, 'OPAC Login (tpac)', 'cuat', 'label'))
    ,(18, 'staffclient', 'login',  'gateway-v1',   'authen', oils_i18n_gettext(18, 'Staff Client Login', 'cuat', 'label'))
    ,(19, 'selfcheck',   'login',  'translator-v1','authen', oils_i18n_gettext(19, 'Self-Check Proxy Login', 'cuat', 'label'))
    ,(20, 'ums',         'login',  'xmlrpc',       'authen', oils_i18n_gettext(20, 'Unique Mgt Login', 'cuat', 'label'))
    ,(21, 'authproxy',   'login',  'apache',       'authen', oils_i18n_gettext(21, 'Apache Auth Proxy Login', 'cuat', 'label'))
    ,(22, 'libraryelf',  'login',  'xmlrpc',       'authz',  oils_i18n_gettext(22, 'LibraryElf Login', 'cuat', 'label'))

    ,(23, 'selfcheck',   'verify', 'translator-v1','authz',  oils_i18n_gettext(23, 'Self-Check User Verification', 'cuat', 'label'))
    ,(24, 'ezproxy',     'verify', 'remoteauth',   'authz',  oils_i18n_gettext(24, 'EZProxy Verification', 'cuat', 'label'))
    -- ...
    ;

-- reserve the first 1000 slots
SELECT SETVAL('config.usr_activity_type_id_seq'::TEXT, 1000);

COMMIT;

/* 
-- UNDO SQL --
BEGIN;
DELETE FROM actor.usr_activity;
DELETE FROM config.usr_activity_type;
DROP TRIGGER remove_transient_usr_activity ON actor.usr_activity;
DROP FUNCTION actor.usr_activity_transient_trg();
DROP FUNCTION actor.insert_usr_activity(INT, TEXT, TEXT, TEXT);
DROP FUNCTION actor.usr_activity_get_type(TEXT, TEXT, TEXT);
DROP TABLE actor.usr_activity;
DROP TABLE config.usr_activity_type;
DROP TYPE config.usr_activity_group;
COMMIT;
*/
