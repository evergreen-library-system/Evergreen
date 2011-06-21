BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0560'); -- miker

CREATE INDEX metabib_full_rec_tnf_idx ON metabib.real_full_rec (record, tag, subfield) WHERE tag = 'tnf' AND subfield = 'a';

COMMIT;

