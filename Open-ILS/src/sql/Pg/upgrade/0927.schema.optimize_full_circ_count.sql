BEGIN;

SELECT evergreen.upgrade_deps_block_check('0927', :eg_version);

CREATE OR REPLACE VIEW extend_reporter.full_circ_count AS
   SELECT cp.id,
   COALESCE((SELECT circ_count FROM extend_reporter.legacy_circ_count WHERE id = cp.id), 0)
   + (SELECT COUNT(*) FROM action.circulation WHERE target_copy = cp.id)
   + (SELECT COUNT(*) FROM action.aged_circulation WHERE target_copy = cp.id) AS circ_count
   FROM asset.copy cp;

COMMIT;
