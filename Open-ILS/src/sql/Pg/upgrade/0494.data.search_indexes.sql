BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0494'); -- dbs

UPDATE config.metabib_field
    SET xpath = $$//mods32:mods/mods32:subject$$
    WHERE field_class = 'subject' AND name = 'complete';

UPDATE config.metabib_field
    SET xpath = $$//marc:datafield[@tag='099']$$
    WHERE field_class = 'identifier' AND name = 'bibcn';

COMMIT;
