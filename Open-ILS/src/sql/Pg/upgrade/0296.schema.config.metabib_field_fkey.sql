BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0296'); --gmc

ALTER TABLE config.metabib_field ADD CONSTRAINT metabib_field_format_fkey FOREIGN KEY (format) REFERENCES config.xml_transform (name);

COMMIT;
