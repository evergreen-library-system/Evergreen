-- Evergreen DB patch 0685.data.bluray_vr_format.sql
--
-- FIXME: insert description of change, if needed
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0685', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
DO $FUNC$
DECLARE
    same_marc BOOL;
BEGIN
    -- Check if it is already there
    PERFORM * FROM config.marc21_physical_characteristic_value_map v
        JOIN config.marc21_physical_characteristic_subfield_map s ON v.ptype_subfield = s.id
        WHERE s.ptype_key = 'v' AND s.subfield = 'e' AND s.start_pos = '4' AND s.length = '1'
            AND v.value = 's';

    -- If it is, bail.
    IF FOUND THEN
        RETURN;
    END IF;

    -- Otherwise, insert it
    INSERT INTO config.marc21_physical_characteristic_value_map (value,ptype_subfield,label)
    SELECT 's',id,'Blu-ray'
        FROM config.marc21_physical_characteristic_subfield_map
        WHERE ptype_key = 'v' AND subfield = 'e' AND start_pos = '4' AND length = '1';

    -- And reingest the blue-ray items so that things see the new value
    SELECT INTO same_marc enabled FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc';
    UPDATE config.internal_flag SET enabled = true WHERE name = 'ingest.reingest.force_on_same_marc';
    UPDATE biblio.record_entry SET marc=marc WHERE id IN (SELECT record
        FROM
            metabib.full_rec a JOIN metabib.full_rec b USING (record)
        WHERE
            a.tag = 'LDR' AND a.value LIKE '______g%'
        AND b.tag = '007' AND b.value LIKE 'v___s%');
    UPDATE config.internal_flag SET enabled = same_marc WHERE name = 'ingest.reingest.force_on_same_marc';
END;
$FUNC$;


COMMIT;
