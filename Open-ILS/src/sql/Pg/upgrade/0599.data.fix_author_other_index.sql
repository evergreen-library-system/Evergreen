-- Evergreen DB patch XXXX.fix_author_other_index.sql
--
-- Fix author|other index so that it doesn't exclude 700
-- fields that contain relator values in the $e or $4.
--
BEGIN;

-- check whether patch can be applied
INSERT INTO config.upgrade_log (version) VALUES ('0599'); -- miker/gmc

UPDATE config.metabib_field 
SET xpath = $$//mods32:mods/mods32:name[@type='personal' and not(mods32:role/mods32:roleTerm[text()='creator'])]$$
WHERE field_class = 'author'
AND name = 'other'
AND xpath = $$//mods32:mods/mods32:name[@type='personal' and not(mods32:role)]$$
AND format = 'mods32';

-- To reindex the affected bibs, you can run something like this:
--
-- SELECT metabib.reingest_metabib_field_entries(record)
-- FROM (
--   SELECT DISTINCT record
--   FROM metabib.real_full_rec
--   WHERE tag IN ('600', '700', '720', '800')
--   AND   subfield IN ('4', 'e')
-- ) a;

COMMIT;
