BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0233'); -- senator

ALTER TABLE acq.invoice
    ADD CONSTRAINT inv_ident_once_per_provider UNIQUE(provider, inv_ident);

COMMIT;
