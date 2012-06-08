-- Evergreen DB patch 0717.data.safer-control-set-defaults.sql

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0717', :eg_version);

-- Allow un-mapped thesauri
ALTER TABLE authority.thesaurus ALTER COLUMN control_set DROP NOT NULL;

-- Don't tie "No attempt to code" to LoC
UPDATE authority.thesaurus SET control_set = NULL WHERE code = '|';
UPDATE authority.record_entry SET control_set = NULL WHERE id IN (SELECT record FROM authority.rec_descriptor WHERE thesaurus = '|');

COMMIT;
