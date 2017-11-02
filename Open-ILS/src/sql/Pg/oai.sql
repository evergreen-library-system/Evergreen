-- VIEWS for the oai service
CREATE SCHEMA oai;

-- The view presents a lean table with unique bre.tc-numbers for oai paging;
CREATE VIEW oai.biblio AS
  SELECT
    bre.id                             AS tcn,
    bre.edit_date                      AS datestamp,
    bre.deleted                        AS deleted
  FROM
    biblio.record_entry bre
  ORDER BY
    bre.id;

-- The view presents a lean table with unique are.tc-numbers for oai paging;
CREATE VIEW oai.authority AS
  SELECT
    are.id               AS tcn,
    are.edit_date        AS datestamp,
    are.deleted          AS deleted
  FROM
    authority.record_entry AS are
  ORDER BY
    are.id;

-- If an edit date changes in the asset.call_number or asset.copy and you want this to persist to an OAI2 datestamp,
-- then add these stored procedures and triggers:
CREATE OR REPLACE FUNCTION oai.datestamp(rid BIGINT)
  RETURNS VOID AS $$
BEGIN
  UPDATE biblio.record_entry AS bre
  SET edit_date = now()
  WHERE bre.id = rid;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION oai.call_number_datestamp()
  RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE'
  THEN
    PERFORM oai.datestamp(OLD.record);
    RETURN OLD;
  END IF;

  PERFORM oai.datestamp(NEW.record);
  RETURN NEW;

END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION oai.copy_datestamp()
  RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE'
  THEN
    PERFORM oai.datestamp((SELECT acn.record FROM asset.call_number as acn WHERE acn.id = OLD.call_number));
    RETURN OLD;
  END IF;

  PERFORM oai.datestamp((SELECT acn.record FROM asset.call_number as acn WHERE acn.id = NEW.call_number));
  RETURN NEW;

END
$$ LANGUAGE plpgsql;

CREATE TRIGGER call_number_datestamp AFTER INSERT OR UPDATE OR DELETE ON asset.call_number FOR EACH ROW EXECUTE PROCEDURE oai.call_number_datestamp();
CREATE TRIGGER copy_datestamp AFTER INSERT OR UPDATE OR DELETE ON asset.copy FOR EACH ROW EXECUTE PROCEDURE oai.copy_datestamp();