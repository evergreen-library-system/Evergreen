-- LP#1091831 - reapply config.update_coded_value_map()
-- due to broken schema version
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0748', :eg_version);

CREATE OR REPLACE FUNCTION config.update_coded_value_map(in_ctype TEXT, in_code TEXT, in_value TEXT, in_description TEXT DEFAULT NULL, in_opac_visible BOOL DEFAULT NULL, in_search_label TEXT DEFAULT NULL, in_is_simple BOOL DEFAULT NULL, add_only BOOL DEFAULT FALSE) RETURNS VOID AS $f$
DECLARE
    current_row config.coded_value_map%ROWTYPE;
BEGIN
    -- Look for a current value
    SELECT INTO current_row * FROM config.coded_value_map WHERE ctype = in_ctype AND code = in_code;
    -- If we have one..
    IF FOUND AND NOT add_only THEN
        -- Update anything we were handed
        current_row.value := COALESCE(current_row.value, in_value);
        current_row.description := COALESCE(current_row.description, in_description);
        current_row.opac_visible := COALESCE(current_row.opac_visible, in_opac_visible);
        current_row.search_label := COALESCE(current_row.search_label, in_search_label);
        current_row.is_simple := COALESCE(current_row.is_simple, in_is_simple);
        UPDATE config.coded_value_map
            SET
                value = current_row.value,
                description = current_row.description,
                opac_visible = current_row.opac_visible,
                search_label = current_row.search_label,
                is_simple = current_row.is_simple
            WHERE id = current_row.id;
    ELSE
        INSERT INTO config.coded_value_map(ctype, code, value, description, opac_visible, search_label, is_simple) VALUES
            (in_ctype, in_code, in_value, in_description, COALESCE(in_opac_visible, TRUE), in_search_label, COALESCE(in_is_simple, FALSE));
    END IF;
END;
$f$ LANGUAGE PLPGSQL;

COMMIT;
