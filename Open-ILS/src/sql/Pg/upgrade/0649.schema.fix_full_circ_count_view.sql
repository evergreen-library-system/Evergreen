-- Evergreen DB patch 0649.schema.fix_full_circ_count_view.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0649', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
CREATE OR REPLACE VIEW extend_reporter.full_circ_count AS
 SELECT cp.id, COALESCE(c.circ_count, 0::bigint) + COALESCE(count(DISTINCT circ.id), 0::bigint) + COALESCE(count(DISTINCT acirc.id), 0::bigint) AS circ_count
   FROM asset."copy" cp
   LEFT JOIN extend_reporter.legacy_circ_count c USING (id)
   LEFT JOIN "action".circulation circ ON circ.target_copy = cp.id
   LEFT JOIN "action".aged_circulation acirc ON acirc.target_copy = cp.id
  GROUP BY cp.id, c.circ_count;


COMMIT;
