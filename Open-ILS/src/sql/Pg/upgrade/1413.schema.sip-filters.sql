
BEGIN;

SELECT evergreen.upgrade_deps_block_check('1413', :eg_version);

CREATE TABLE sip.filter (
    id              SERIAL PRIMARY KEY,
    enabled         BOOLEAN NOT NULL DEFAULT FALSE,
    setting_group   INTEGER NOT NULL REFERENCES sip.setting_group (id)
                    ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    identifier      TEXT NOT NULL,
    strip           BOOLEAN NOT NULL DEFAULT FALSE,
    replace_with    TEXT
);

COMMIT;


