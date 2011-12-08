BEGIN;

SELECT evergreen.upgrade_deps_block_check('0643', :eg_version);

DO $$
DECLARE x TEXT;
BEGIN

    FOR x IN
        SELECT  marc
          FROM  authority.record_entry
          WHERE id > 0
                AND NOT deleted
                AND id NOT IN (SELECT DISTINCT record FROM authority.simple_heading)
    LOOP
        INSERT INTO authority.simple_heading (record,atag,value,sort_value)
            SELECT record, atag, value, sort_value FROM authority.simple_heading_set(x);
    END LOOP;
END;
$$;

COMMIT;

