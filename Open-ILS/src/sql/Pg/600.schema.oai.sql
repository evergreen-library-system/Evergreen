-- VIEWS for the oai service
CREATE SCHEMA oai;

-- The view presents a lean table with unique bre.tc-numbers for oai paging;
CREATE VIEW oai.biblio AS
  SELECT
    bre.id                             AS rec_id,
    bre.edit_date                      AS datestamp,
    bre.deleted                        AS deleted
  FROM
    biblio.record_entry bre
  ORDER BY
    bre.id;

-- The view presents a lean table with unique are.tc-numbers for oai paging;
CREATE VIEW oai.authority AS
  SELECT
    are.id               AS rec_id,
    are.edit_date        AS datestamp,
    are.deleted          AS deleted
  FROM
    authority.record_entry AS are
  ORDER BY
    are.id;

CREATE OR REPLACE function oai.bib_is_visible_at_org(bib BIGINT, org INT) RETURNS BOOL AS $F$
WITH orgs AS (SELECT array_accum(id) id FROM actor.org_unit_descendants(org))
SELECT EXISTS (SELECT 1 FROM asset.copy_vis_attr_cache, orgs WHERE vis_attr_vector @@ search.calculate_visibility_attribute_test('circ_lib', orgs.id)::query_int AND bib=record)
$F$ LANGUAGE SQL STABLE;

