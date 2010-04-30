BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0248'); -- miker

CREATE TABLE config.global_flag (
    label   TEXT    NOT NULL
) INHERITS (config.internal_flag);
ALTER TABLE config.global_flag ADD PRIMARY KEY (name);

COMMIT;
