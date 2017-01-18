BEGIN;

SELECT evergreen.upgrade_deps_block_check('1004', :eg_version); 

CREATE OR REPLACE FUNCTION reporter.hold_request_record_mapper () RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO reporter.hold_request_record (id, target, hold_type, bib_record)
        SELECT  NEW.id,
                NEW.target,
                NEW.hold_type,
                CASE
                    WHEN NEW.hold_type = 'T'
                        THEN NEW.target
                    WHEN NEW.hold_type = 'I'
                        THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = NEW.target)
                    WHEN NEW.hold_type = 'V'
                        THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = NEW.target)
                    WHEN NEW.hold_type IN ('C','R','F')
                        THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = NEW.target)
                    WHEN NEW.hold_type = 'M'
                        THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = NEW.target)
                    WHEN NEW.hold_type = 'P'
                        THEN (SELECT bmp.record FROM biblio.monograph_part bmp WHERE bmp.id = NEW.target)
                END AS bib_record;
    ELSIF TG_OP = 'UPDATE' AND (OLD.target <> NEW.target OR OLD.hold_type <> NEW.hold_type) THEN
        UPDATE  reporter.hold_request_record
          SET   target = NEW.target,
                hold_type = NEW.hold_type,
                bib_record = CASE
                    WHEN NEW.hold_type = 'T'
                        THEN NEW.target
                    WHEN NEW.hold_type = 'I'
                        THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = NEW.target)
                    WHEN NEW.hold_type = 'V'
                        THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = NEW.target)
                    WHEN NEW.hold_type IN ('C','R','F')
                        THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = NEW.target)
                    WHEN NEW.hold_type = 'M'
                        THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = NEW.target)
                    WHEN NEW.hold_type = 'P'
                        THEN (SELECT bmp.record FROM biblio.monograph_part bmp WHERE bmp.id = NEW.target)
                END
         WHERE  id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

TRUNCATE TABLE reporter.hold_request_record;
 
INSERT INTO reporter.hold_request_record 
SELECT  id,
        target,
        hold_type,
        CASE
                WHEN hold_type = 'T'
                        THEN target
                WHEN hold_type = 'I'
                        THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = ahr.target)
                WHEN hold_type = 'V'
                        THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = ahr.target)
                WHEN hold_type IN ('C','R','F')
                        THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = ahr.target)
                WHEN hold_type = 'M'
                        THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = ahr.target)
                WHEN hold_type = 'P'
                        THEN (SELECT bmp.record FROM biblio.monograph_part bmp WHERE bmp.id = ahr.target)
        END AS bib_record
  FROM  action.hold_request ahr;
 
REINDEX TABLE reporter.hold_request_record;

COMMIT;

ANALYZE reporter.hold_request_record;

