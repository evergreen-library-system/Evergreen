-- Evergreen DB patch 0540.schema.missing_serial_unit_triggers.sql
--
-- Bring serial.unit into line with asset.copy
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0540', :eg_version);

CREATE TRIGGER sunit_status_changed_trig
    BEFORE UPDATE ON serial.unit
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_status_changed();

SELECT auditor.create_auditor ( 'serial', 'unit' );
CREATE INDEX aud_serial_unit_hist_creator_idx      ON auditor.serial_unit_history ( creator );
CREATE INDEX aud_serial_unit_hist_editor_idx       ON auditor.serial_unit_history ( editor );

COMMIT;
