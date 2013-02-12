BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE acq.distribution_formula_entry
    ADD COLUMN fund INT REFERENCES acq.fund (id),
    ADD COLUMN circ_modifier TEXT REFERENCES config.circ_modifier (code),
    ADD COLUMN collection_code TEXT ;

COMMIT;
