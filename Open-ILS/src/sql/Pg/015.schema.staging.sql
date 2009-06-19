DROP SCHEMA staging CASCADE;

BEGIN;

CREATE SCHEMA staging;

CREATE TABLE staging.user_stage (
        row_id                  BIGSERIAL PRIMARY KEY,
        row_date                            TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname                 TEXT NOT NULL,
        profile                 TEXT,
        email                   TEXT,
        passwd                  TEXT,
        ident_type              INT DEFAULT 3,
        first_given_name        TEXT,
        second_given_name       TEXT,
        family_name             TEXT,
        day_phone               TEXT,
        evening_phone           TEXT,
        home_ou                 INT DEFAULT 2,
        dob                     TEXT,
        complete                BOOL DEFAULT FALSE
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
        row_date            TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname         TEXT NOT NULL,  -- user's SIS barcode, for linking
        street1         TEXT,
        street2         TEXT,
        city            TEXT NOT NULL DEFAULT '',
        state           TEXT    NOT NULL DEFAULT 'OK',
        country         TEXT NOT NULL DEFAULT 'US',
        post_code       TEXT NOT NULL,
        complete        BOOL DEFAULT FALSE
);

CREATE TABLE staging.billing_address_stage (
        LIKE staging.mailing_address_stage INCLUDING DEFAULTS
);

CREATE TABLE staging.statcat_stage (
        row_id          BIGSERIAL PRIMARY KEY,
        row_date    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname         TEXT NOT NULL,
        statcat         TEXT NOT NULL, -- for things like 'Year of study'
        value           TEXT NOT NULL, -- and the value, such as 'Freshman'
        complete        BOOL DEFAULT FALSE
);

COMMIT;

