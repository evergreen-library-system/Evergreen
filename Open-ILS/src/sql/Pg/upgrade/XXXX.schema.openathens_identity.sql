BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TABLE config.openathens_uid_field (
    id      SERIAL  PRIMARY KEY,
    name    TEXT    NOT NULL
);

INSERT INTO config.openathens_uid_field
    (id, name)
VALUES
    (1,'id'),
    (2,'usrname')
;

SELECT SETVAL('config.openathens_uid_field_id_seq'::TEXT, 100);

CREATE TABLE config.openathens_name_field (
    id      SERIAL  PRIMARY KEY,
    name    TEXT    NOT NULL
);

INSERT INTO config.openathens_name_field
    (id, name)
VALUES
    (1,'id'),
    (2,'usrname'),
    (3,'fullname')
;

SELECT SETVAL('config.openathens_name_field_id_seq'::TEXT, 100);

CREATE TABLE config.openathens_identity (
    id                          SERIAL  PRIMARY KEY,
    active                      BOOL    NOT NULL DEFAULT true,
    org_unit                    INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    api_key                     TEXT    NOT NULL,
    connection_id               TEXT    NOT NULL,
    connection_uri              TEXT    NOT NULL,
    auto_signon_enabled         BOOL    NOT NULL DEFAULT true,
    auto_signout_enabled        BOOL    NOT NULL DEFAULT false,
    unique_identifier           INT     NOT NULL REFERENCES config.openathens_uid_field (id) DEFAULT 1,
    display_name                INT     NOT NULL REFERENCES config.openathens_name_field (id) DEFAULT 1,
    release_prefix              BOOL    NOT NULL DEFAULT false,
    release_first_given_name    BOOL    NOT NULL DEFAULT false,
    release_second_given_name   BOOL    NOT NULL DEFAULT false,
    release_family_name         BOOL    NOT NULL DEFAULT false,
    release_suffix              BOOL    NOT NULL DEFAULT false,
    release_email               BOOL    NOT NULL DEFAULT false,
    release_home_ou             BOOL    NOT NULL DEFAULT false
);

COMMIT;
