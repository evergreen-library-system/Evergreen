BEGIN;

SELECT evergreen.upgrade_deps_block_check('1323', :eg_version);

-- VIEWS for the oai service
CREATE SCHEMA oai;

-- The view presents a lean table with unique bre.tc-numbers for oai paging;
CREATE VIEW oai.biblio AS
  SELECT
    bre.id                             AS rec_id,
    bre.edit_date AT TIME ZONE 'UTC'   AS datestamp,
    bre.deleted                        AS deleted
  FROM
    biblio.record_entry bre
  ORDER BY
    bre.id;

-- The view presents a lean table with unique are.tc-numbers for oai paging;
CREATE VIEW oai.authority AS
  SELECT
    are.id                           AS rec_id,
    are.edit_date AT TIME ZONE 'UTC' AS datestamp,
    are.deleted                      AS deleted
  FROM
    authority.record_entry AS are
  ORDER BY
    are.id;

CREATE OR REPLACE function oai.bib_is_visible_at_org_by_copy(bib BIGINT, org INT) RETURNS BOOL AS $F$
WITH corgs AS (SELECT array_agg(id) AS list FROM actor.org_unit_descendants(org))
  SELECT EXISTS (SELECT 1 FROM asset.copy_vis_attr_cache, corgs WHERE vis_attr_vector @@ search.calculate_visibility_attribute_test('circ_lib', corgs.list)::query_int AND bib=record)
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE function oai.bib_is_visible_at_org_by_luri(bib BIGINT, org INT) RETURNS BOOL AS $F$
WITH lorgs AS(SELECT array_agg(id) AS list FROM actor.org_unit_ancestors(org))
  SELECT EXISTS (SELECT 1 FROM biblio.record_entry, lorgs WHERE vis_attr_vector @@ search.calculate_visibility_attribute_test('luri_org', lorgs.list)::query_int AND bib=id)
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE function oai.bib_is_visible_by_source(bib BIGINT, src TEXT) RETURNS BOOL AS $F$
  SELECT EXISTS (SELECT 1 FROM biblio.record_entry b JOIN config.bib_source s ON (b.source = s.id) WHERE transcendant AND s.source = src AND bib=b.id)
$F$ LANGUAGE SQL STABLE;

CREATE OR REPLACE function oai.auth_is_visible_by_axis(auth BIGINT, ax TEXT) RETURNS BOOL AS $F$
  SELECT EXISTS (SELECT 1 FROM authority.browse_axis_authority_field_map m JOIN authority.simple_heading r on (r.atag = m.field AND r.record = auth AND m.axis = ax))
$F$ LANGUAGE SQL STABLE;

COMMIT;

