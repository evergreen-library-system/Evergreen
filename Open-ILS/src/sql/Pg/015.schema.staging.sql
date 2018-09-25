DROP SCHEMA IF EXISTS staging CASCADE;

BEGIN;

CREATE SCHEMA staging;

CREATE TABLE staging.user_stage (
        row_id                  BIGSERIAL PRIMARY KEY,
        row_date                TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname                 TEXT NOT NULL,
        profile                 TEXT,
        email                   TEXT,
        passwd                  TEXT,
        ident_type              INT DEFAULT 3,
        first_given_name        TEXT,
        second_given_name       TEXT,
        family_name             TEXT,
        pref_first_given_name   TEXT,
        pref_second_given_name  TEXT,
        pref_family_name        TEXT,
        day_phone               TEXT,
        evening_phone           TEXT,
        home_ou                 INT DEFAULT 2,
        dob                     TEXT,
        complete                BOOL DEFAULT FALSE,
        requesting_usr          INT REFERENCES actor.usr(id) ON DELETE SET NULL
);

CREATE TABLE staging.card_stage ( -- for new library barcodes
        row_id          BIGSERIAL PRIMARY KEY,
        row_date        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname         TEXT NOT NULL,
        barcode         TEXT NOT NULL,
        complete        BOOL DEFAULT FALSE
);

CREATE TABLE staging.mailing_address_stage (
        row_id          BIGSERIAL PRIMARY KEY,
        row_date        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname         TEXT NOT NULL,  -- user's SIS barcode, for linking
        street1         TEXT,
        street2         TEXT,
        city            TEXT NOT NULL DEFAULT '',
        county          TEXT,
        state           TEXT,
        country         TEXT NOT NULL DEFAULT 'US',
        post_code       TEXT NOT NULL,
        complete        BOOL DEFAULT FALSE
);

CREATE TABLE staging.billing_address_stage (
        LIKE staging.mailing_address_stage INCLUDING DEFAULTS
);

ALTER TABLE staging.billing_address_stage ADD PRIMARY KEY (row_id);

CREATE TABLE staging.statcat_stage (
        row_id          BIGSERIAL PRIMARY KEY,
        row_date    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname         TEXT NOT NULL,
        statcat         TEXT NOT NULL, -- for things like 'Year of study'
        value           TEXT NOT NULL, -- and the value, such as 'Freshman'
        complete        BOOL DEFAULT FALSE
);

CREATE TABLE staging.setting_stage (
        row_id          BIGSERIAL PRIMARY KEY,
        row_date        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname         TEXT NOT NULL,
        setting         TEXT NOT NULL,
        value           TEXT NOT NULL,
        complete        BOOL DEFAULT FALSE
);

-- stored procedure for deleting expired pending patrons
CREATE OR REPLACE FUNCTION staging.purge_pending_users() RETURNS VOID AS $$
DECLARE
    org_id INT;
    intvl TEXT;
BEGIN
    FOR org_id IN SELECT DISTINCT(home_ou) FROM staging.user_stage LOOP

        SELECT INTO intvl value FROM 
            actor.org_unit_ancestor_setting(
                'opac.pending_user_expire_interval', org_id);

        CONTINUE WHEN intvl IS NULL OR intvl ILIKE 'null';

        -- de-JSON-ify the string
        SELECT INTO intvl TRIM(BOTH '"' FROM intvl);

        DELETE FROM staging.user_stage 
            WHERE home_ou = org_id AND row_date + intvl::INTERVAL < NOW();

    END LOOP;
END;
$$ LANGUAGE PLPGSQL;

COMMIT;

