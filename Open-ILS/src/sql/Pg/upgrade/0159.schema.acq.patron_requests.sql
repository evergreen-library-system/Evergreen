BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0159');  -- miker

CREATE TABLE acq.user_request_type (
    id      SERIAL  PRIMARY KEY,
    label   TEXT    NOT NULL UNIQUE -- i18n-ize
);

INSERT INTO acq.user_request_type (id,label) VALUES (1, oils_i18n_gettext('1', 'Books', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (2, oils_i18n_gettext('2', 'Journal/Magazine & Newspaper Articles', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (3, oils_i18n_gettext('3', 'Audiobooks', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (4, oils_i18n_gettext('4', 'Music', 'aurt', 'label'));
INSERT INTO acq.user_request_type (id,label) VALUES (5, oils_i18n_gettext('5', 'DVDs', 'aurt', 'label'));

SELECT SETVAL('acq.user_request_type_id_seq'::TEXT, 6);

CREATE TABLE acq.user_request (
    id                  SERIAL  PRIMARY KEY,
    usr                 INT     NOT NULL REFERENCES actor.usr (id), -- requesting user
    hold                BOOL    NOT NULL DEFAULT TRUE,

    pickup_lib          INT     NOT NULL REFERENCES actor.org_unit (id), -- pickup lib
    holdable_formats    TEXT,           -- nullable, for use in hold creation
    phone_notify        TEXT,
    email_notify        BOOL    NOT NULL DEFAULT TRUE,
    lineitem            INT     REFERENCES acq.lineitem (id) ON DELETE CASCADE,
    eg_bib              BIGINT  REFERENCES biblio.record_entry (id) ON DELETE CASCADE,
    request_date        TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- when they requested it
    need_before         TIMESTAMPTZ,    -- don't create holds after this
    max_fee             TEXT,

    request_type        INT     NOT NULL REFERENCES acq.user_request_type (id), 
    isxn                TEXT,
    title               TEXT,
    volume              TEXT,
    author              TEXT,
    article_title       TEXT,
    article_pages       TEXT,
    publisher           TEXT,
    location            TEXT,
    pubdate             TEXT,
    mentioned           TEXT,
    other_info          TEXT
);


COMMIT;

