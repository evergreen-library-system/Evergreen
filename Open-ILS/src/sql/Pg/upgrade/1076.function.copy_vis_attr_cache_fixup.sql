BEGIN;

SELECT evergreen.upgrade_deps_block_check('1076', :eg_version); -- miker/gmcharlt

CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    ocn     asset.call_number%ROWTYPE;
    ncn     asset.call_number%ROWTYPE;
    cid     BIGINT;
BEGIN

    IF TG_TABLE_NAME = 'peer_bib_copy_map' THEN -- Only needs ON INSERT OR DELETE, so handle separately
        IF TG_OP = 'INSERT' THEN
            INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                NEW.peer_record,
                NEW.target_copy,
                asset.calculate_copy_visibility_attribute_set(NEW.target_copy)
            );

            RETURN NEW;
        ELSIF TG_OP = 'DELETE' THEN
            DELETE FROM asset.copy_vis_attr_cache
              WHERE record = NEW.peer_record AND target_copy = NEW.target_copy;

            RETURN OLD;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN -- Handles ON INSERT. ON UPDATE is below.
        IF TG_TABLE_NAME IN ('copy', 'unit') THEN
            SELECT * INTO ncn FROM asset.call_number cn WHERE id = NEW.call_number;
            INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                ncn.record,
                NEW.id,
                asset.calculate_copy_visibility_attribute_set(NEW.id)
            );
        ELSIF TG_TABLE_NAME = 'record_entry' THEN
            NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id);
        END IF;

        RETURN NEW;
    END IF;

    -- handle items first, since with circulation activity
    -- their statuses change frequently
    IF TG_TABLE_NAME IN ('copy', 'unit') THEN -- This handles ON UPDATE OR DELETE. ON INSERT above

        IF TG_OP = 'DELETE' THEN -- Shouldn't get here, normally
            DELETE FROM asset.copy_vis_attr_cache WHERE target_copy = OLD.id;
            RETURN OLD;
        END IF;

        SELECT * INTO ncn FROM asset.call_number cn WHERE id = NEW.call_number;

        IF OLD.deleted <> NEW.deleted THEN
            IF NEW.deleted THEN
                DELETE FROM asset.copy_vis_attr_cache WHERE target_copy = OLD.id;
            ELSE
                INSERT INTO asset.copy_vis_attr_cache (record, target_copy, vis_attr_vector) VALUES (
                    ncn.record,
                    NEW.id,
                    asset.calculate_copy_visibility_attribute_set(NEW.id)
                );
            END IF;

            RETURN NEW;
        ELSIF OLD.call_number  <> NEW.call_number THEN
            SELECT * INTO ocn FROM asset.call_number cn WHERE id = OLD.call_number;

            IF ncn.record <> ocn.record THEN
                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(ncn.record)
                  WHERE id = ocn.record;

                -- We have to use a record-specific WHERE clause
                -- to avoid modifying the entries for peer-bib copies.
                UPDATE  asset.copy_vis_attr_cache
                  SET   target_copy = NEW.id,
                        record = ncn.record
                  WHERE target_copy = OLD.id
                        AND record = ocn.record;
            END IF;
        END IF;

        IF OLD.location     <> NEW.location OR
           OLD.status       <> NEW.status OR
           OLD.opac_visible <> NEW.opac_visible OR
           OLD.circ_lib     <> NEW.circ_lib
        THEN
            -- Any of these could change visibility, but
            -- we'll save some queries and not try to calculate
            -- the change directly.  We want to update peer-bib
            -- entries in this case, unlike above.
            UPDATE  asset.copy_vis_attr_cache
              SET   target_copy = NEW.id,
                    vis_attr_vector = asset.calculate_copy_visibility_attribute_set(NEW.id)
              WHERE target_copy = OLD.id;

        END IF;

    ELSIF TG_TABLE_NAME = 'call_number' THEN -- Only ON UPDATE. Copy handler will deal with ON INSERT OR DELETE.

        IF OLD.record <> NEW.record THEN
            IF NEW.label = '##URI##' THEN
                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
                  WHERE id = OLD.record;

                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(NEW.record)
                  WHERE id = NEW.record;
            END IF;

            UPDATE  asset.copy_vis_attr_cache
              SET   record = NEW.record,
                    vis_attr_vector = asset.calculate_copy_visibility_attribute_set(target_copy)
              WHERE target_copy IN (SELECT id FROM asset.copy WHERE call_number = NEW.id)
                    AND record = OLD.record;

        ELSIF OLD.owning_lib <> NEW.owning_lib THEN
            UPDATE  asset.copy_vis_attr_cache
              SET   vis_attr_vector = asset.calculate_copy_visibility_attribute_set(target_copy)
              WHERE target_copy IN (SELECT id FROM asset.copy WHERE call_number = NEW.id)
                    AND record = NEW.record;

            IF NEW.label = '##URI##' THEN
                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
                  WHERE id = OLD.record;
            END IF;
        END IF;

    ELSIF TG_TABLE_NAME = 'record_entry' THEN -- Only handles ON UPDATE OR DELETE

        IF TG_OP = 'DELETE' THEN -- Shouldn't get here, normally
            DELETE FROM asset.copy_vis_attr_cache WHERE record = OLD.id;
            RETURN OLD;
        ELSIF OLD.source <> NEW.source THEN
            NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id);
        END IF;

    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

