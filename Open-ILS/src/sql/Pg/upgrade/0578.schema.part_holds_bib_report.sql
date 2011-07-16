-- Evergreen DB patch 0578.schema.part_holds_bib_report.sql
--
-- Fix part holds in reporter.hold_request_record
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0578', :eg_version);

CREATE OR REPLACE VIEW reporter.hold_request_record AS
SELECT	id,
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
  FROM	action.hold_request ahr;

COMMIT;

