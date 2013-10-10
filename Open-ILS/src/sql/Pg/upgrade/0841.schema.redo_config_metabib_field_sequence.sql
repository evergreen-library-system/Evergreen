BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0841', :eg_version);

ALTER TABLE config.metabib_field_ts_map DROP CONSTRAINT metabib_field_ts_map_metabib_field_fkey;
ALTER TABLE config.metabib_search_alias DROP CONSTRAINT metabib_search_alias_field_fkey;
ALTER TABLE config.z3950_index_field_map DROP CONSTRAINT z3950_index_field_map_metabib_field_fkey;
ALTER TABLE metabib.browse_entry_def_map DROP CONSTRAINT browse_entry_def_map_def_fkey;

ALTER TABLE config.metabib_field_ts_map ADD CONSTRAINT metabib_field_ts_map_metabib_field_fkey FOREIGN KEY (metabib_field) REFERENCES config.metabib_field(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.metabib_search_alias ADD CONSTRAINT metabib_search_alias_field_fkey FOREIGN KEY (field) REFERENCES config.metabib_field(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE config.z3950_index_field_map ADD CONSTRAINT z3950_index_field_map_metabib_field_fkey FOREIGN KEY (metabib_field) REFERENCES config.metabib_field(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE metabib.browse_entry_def_map ADD CONSTRAINT browse_entry_def_map_def_fkey FOREIGN KEY (def) REFERENCES config.metabib_field(id) DEFERRABLE INITIALLY DEFERRED;


DROP FUNCTION IF EXISTS config.modify_metabib_field(source INT, target INT);
CREATE FUNCTION config.modify_metabib_field(v_source INT, target INT) RETURNS INT AS $func$
DECLARE
    f_class TEXT;
    check_id INT;
    target_id INT;
BEGIN
    SELECT field_class INTO f_class FROM config.metabib_field WHERE id = v_source;
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    IF target IS NULL THEN
        target_id = v_source + 1000;
    ELSE
        target_id = target;
    END IF;
    SELECT id FROM config.metabib_field INTO check_id WHERE id = target_id;
    IF FOUND THEN
        RAISE NOTICE 'Cannot bump config.metabib_field.id from % to %; the target ID already exists.', v_source, target_id;
        RETURN 0;
    END IF;
    UPDATE config.metabib_field SET id = target_id WHERE id = v_source;
    EXECUTE ' UPDATE metabib.' || f_class || '_field_entry SET field = ' || target_id || ' WHERE field = ' || v_source;
    UPDATE config.metabib_field_ts_map SET metabib_field = target_id WHERE metabib_field = v_source;
    UPDATE config.metabib_field_index_norm_map SET field = target_id WHERE field = v_source;
    UPDATE search.relevance_adjustment SET field = target_id WHERE field = v_source;
    UPDATE config.metabib_search_alias SET field = target_id WHERE field = v_source;
    UPDATE config.z3950_index_field_map SET metabib_field = target_id WHERE metabib_field = v_source;
    UPDATE metabib.browse_entry_def_map SET def = target_id WHERE def = v_source;
    RETURN 1;
END;
$func$ LANGUAGE PLPGSQL;

SELECT config.modify_metabib_field(id, NULL)
    FROM config.metabib_field
    WHERE id > 30;

SELECT SETVAL('config.metabib_field_id_seq', GREATEST(1000, (SELECT MAX(id) FROM config.metabib_field)));

COMMIT;
