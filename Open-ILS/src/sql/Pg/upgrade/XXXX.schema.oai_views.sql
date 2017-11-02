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


-- OPTIONAL PORTION

\qecho If an edit date changes in the asset.call_number or asset.copy and you want this to persist to an OAI2 datestamp,
\qecho then add these stored procedures and triggers:
\qecho
\qecho 'CREATE OR REPLACE FUNCTION oai.datestamp(rid BIGINT)'
\qecho '  RETURNS VOID AS $$'
\qecho 'BEGIN'
\qecho '  UPDATE biblio.record_entry AS bre'
\qecho '  SET edit_date = now()'
\qecho '  WHERE bre.id = rid;'
\qecho 'END'
\qecho '$$ LANGUAGE plpgsql;'
\qecho
\qecho 'CREATE OR REPLACE FUNCTION oai.call_number_datestamp()'
\qecho '  RETURNS TRIGGER AS $$'
\qecho 'BEGIN'
\qecho '  IF TG_OP = ''DELETE'''
\qecho '  THEN'
\qecho '    PERFORM oai.datestamp(OLD.record);'
\qecho '    RETURN OLD;'
\qecho '  END IF;'
\qecho
\qecho '  PERFORM oai.datestamp(NEW.record);'
\qecho '  RETURN NEW;'
\qecho
\qecho 'END'
\qecho '$$ LANGUAGE plpgsql;'
\qecho
\qecho 'CREATE OR REPLACE FUNCTION oai.copy_datestamp()'
\qecho '  RETURNS TRIGGER AS $$'
\qecho 'BEGIN'
\qecho '  IF TG_OP = ''DELETE'''
\qecho '  THEN'
\qecho '    PERFORM oai.datestamp((SELECT acn.record FROM asset.call_number as acn WHERE acn.id = OLD.call_number));'
\qecho '    RETURN OLD;'
\qecho '  END IF;'
\qecho
\qecho '  PERFORM oai.datestamp((SELECT acn.record FROM asset.call_number as acn WHERE acn.id = NEW.call_number));'
\qecho '  RETURN NEW;'
\qecho
\qecho 'END'
\qecho '$$ LANGUAGE plpgsql;'
\qecho
\qecho 'CREATE TRIGGER call_number_datestamp AFTER INSERT OR UPDATE OR DELETE ON asset.call_number FOR EACH ROW EXECUTE PROCEDURE oai.call_number_datestamp();'
\qecho 'CREATE TRIGGER copy_datestamp AFTER INSERT OR UPDATE OR DELETE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE oai.copy_datestamp();'

COMMIT;

