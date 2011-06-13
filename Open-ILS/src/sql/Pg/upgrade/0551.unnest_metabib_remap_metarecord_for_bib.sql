-- Evergreen DB patch 0551.unnest_metabib_remap_metarecord_for_bib.sql
--
-- Replace usage of custom explode_array() function with native unnest()
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0551', :eg_version);

CREATE OR REPLACE FUNCTION metabib.remap_metarecord_for_bib( bib_id BIGINT, fp TEXT ) RETURNS BIGINT AS $func$
DECLARE
    source_count    INT;
    old_mr          BIGINT;
    tmp_mr          metabib.metarecord%ROWTYPE;
    deleted_mrs     BIGINT[];
BEGIN

    DELETE FROM metabib.metarecord_source_map WHERE source = bib_id; -- Rid ourselves of the search-estimate-killing linkage

    FOR tmp_mr IN SELECT  m.* FROM  metabib.metarecord m JOIN metabib.metarecord_source_map s ON (s.metarecord = m.id) WHERE s.source = bib_id LOOP

        IF old_mr IS NULL AND fp = tmp_mr.fingerprint THEN -- Find the first fingerprint-matching
            old_mr := tmp_mr.id;
        ELSE
            SELECT COUNT(*) INTO source_count FROM metabib.metarecord_source_map WHERE metarecord = tmp_mr.id;
            IF source_count = 0 THEN -- No other records
                deleted_mrs := ARRAY_APPEND(deleted_mrs, tmp_mr.id);
                DELETE FROM metabib.metarecord WHERE id = tmp_mr.id;
            END IF;
        END IF;

    END LOOP;

    IF old_mr IS NULL THEN -- we found no suitable, preexisting MR based on old source maps
        SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp; -- is there one for our current fingerprint?
        IF old_mr IS NULL THEN -- nope, create one and grab its id
            INSERT INTO metabib.metarecord ( fingerprint, master_record ) VALUES ( fp, bib_id );
            SELECT id INTO old_mr FROM metabib.metarecord WHERE fingerprint = fp;
        ELSE -- indeed there is. update it with a null cache and recalcualated master record
            UPDATE  metabib.metarecord
              SET   mods = NULL,
                    master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp ORDER BY quality DESC LIMIT 1)
              WHERE id = old_mr;
        END IF;
    ELSE -- there was one we already attached to, update its mods cache and master_record
        UPDATE  metabib.metarecord
          SET   mods = NULL,
                master_record = ( SELECT id FROM biblio.record_entry WHERE fingerprint = fp ORDER BY quality DESC LIMIT 1)
          WHERE id = old_mr;
    END IF;

    INSERT INTO metabib.metarecord_source_map (metarecord, source) VALUES (old_mr, bib_id); -- new source mapping

    IF ARRAY_UPPER(deleted_mrs,1) > 0 THEN
        UPDATE action.hold_request SET target = old_mr WHERE target IN ( SELECT unnest(deleted_mrs) ) AND hold_type = 'M'; -- if we had to delete any MRs above, make sure their holds are moved
    END IF;

    RETURN old_mr;

END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
