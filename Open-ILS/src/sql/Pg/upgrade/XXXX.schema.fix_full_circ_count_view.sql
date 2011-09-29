CREATE OR REPLACE VIEW extend_reporter.full_circ_count AS
 SELECT cp.id, COALESCE(c.circ_count, 0::bigint) + COALESCE(count(circ.id), 0::bigint) + COALESCE(count(acirc.id), 0::bigint) AS circ_count
   FROM asset."copy" cp
   LEFT JOIN extend_reporter.legacy_circ_count c USING (id)
   LEFT JOIN "action".circulation circ ON circ.target_copy = cp.id
   LEFT JOIN "action".aged_circulation acirc ON acirc.target_copy = cp.id
  GROUP BY cp.id, c.circ_count;
