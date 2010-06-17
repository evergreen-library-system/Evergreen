BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0310'); --miker

UPDATE config.metabib_field SET facet_xpath = '//' || facet_xpath WHERE facet_xpath IS NOT NULL;

COMMIT;

