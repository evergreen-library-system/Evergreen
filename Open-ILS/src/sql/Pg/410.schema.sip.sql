BEGIN;

DROP SCHEMA IF EXISTS sip CASCADE;

CREATE SCHEMA sip;

-- Collections of settings that can be linked to one or more SIP accounts.
CREATE TABLE sip.setting_group (
    id          SERIAL PRIMARY KEY,
    label       TEXT UNIQUE NOT NULL,
    institution TEXT NOT NULL -- Duplicates OK
);

-- Key/value setting pairs
CREATE TABLE sip.setting (
    id SERIAL       PRIMARY KEY,
    setting_group   INTEGER NOT NULL REFERENCES sip.setting_group (id)
                    ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    value           JSON NOT NULL,
    CONSTRAINT      name_once_per_inst UNIQUE (setting_group, name)
);

CREATE TABLE sip.account (
    id              SERIAL PRIMARY KEY,
    enabled         BOOLEAN NOT NULL DEFAULT TRUE,
    setting_group   INTEGER NOT NULL REFERENCES sip.setting_group (id)
                    DEFERRABLE INITIALLY DEFERRED,
    sip_username    TEXT UNIQUE NOT NULL,
    usr             BIGINT NOT NULL REFERENCES actor.usr(id)
                    DEFERRABLE INITIALLY DEFERRED,
    workstation     INTEGER REFERENCES actor.workstation(id),
    -- sessions for transient accounts are not tracked in sip.session
    transient       BOOLEAN NOT NULL DEFAULT FALSE,
    activity_who    TEXT -- config.usr_activity_type.ewho
);

CREATE TABLE sip.session (
    key         TEXT PRIMARY KEY,
    ils_token   TEXT NOT NULL UNIQUE,
    account     INTEGER NOT NULL REFERENCES sip.account(id)
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sip.screen_message (
    key     TEXT PRIMARY KEY,
    message TEXT NOT NULL
);

COMMIT;

