BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

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

COMMIT;

