
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0188'); -- miker

CREATE TABLE vandelay.merge_profile (
    id              BIGSERIAL   PRIMARY KEY,
    owner           INT         NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT        NOT NULL,
    add_spec        TEXT,
    replace_spec    TEXT,
    strip_spec      TEXT,
    preserve_spec   TEXT,
    CONSTRAINT vand_merge_prof_owner_name_idx UNIQUE (owner,name),
    CONSTRAINT add_replace_strip_or_preserve CHECK (preserve_spec IS NULL OR (add_spec IS NULL AND replace_spec IS NULL AND strip_spec IS NULL))
);

COMMIT;

