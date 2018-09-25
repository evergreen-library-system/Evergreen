--Upgrade Script for 3.0.2 to 3.0.3
\set eg_version '''3.0.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.0.3', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1085', :eg_version);

CREATE OR REPLACE FUNCTION asset.calculate_copy_visibility_attribute_set ( copy_id BIGINT ) RETURNS INT[] AS $f$
DECLARE
    copy_row    asset.copy%ROWTYPE;
    lgroup_map  asset.copy_location_group_map%ROWTYPE;
    attr_set    INT[] := '{}'::INT[];
BEGIN
    SELECT * INTO copy_row FROM asset.copy WHERE id = copy_id;

    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.opac_visible::INT, 'copy_flags');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.circ_lib, 'circ_lib');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.status, 'status');
    attr_set := attr_set || search.calculate_visibility_attribute(copy_row.location, 'location');

    SELECT  ARRAY_APPEND(
                attr_set,
                search.calculate_visibility_attribute(owning_lib, 'owning_lib')
            ) INTO attr_set
      FROM  asset.call_number
      WHERE id = copy_row.call_number;

    FOR lgroup_map IN SELECT * FROM asset.copy_location_group_map WHERE location = copy_row.location LOOP
        attr_set := attr_set || search.calculate_visibility_attribute(lgroup_map.lgroup, 'location_group');
    END LOOP;

    RETURN attr_set;
END;
$f$ LANGUAGE PLPGSQL;

DROP FUNCTION IF EXISTS biblio.calculate_bib_visibility_attribute_set ( BIGINT );
CREATE OR REPLACE FUNCTION biblio.calculate_bib_visibility_attribute_set ( bib_id BIGINT, new_source INT DEFAULT NULL, force_source BOOL DEFAULT FALSE ) RETURNS INT[] AS $f$
DECLARE
    bib_row     biblio.record_entry%ROWTYPE;
    cn_row      asset.call_number%ROWTYPE;
    attr_set    INT[] := '{}'::INT[];
BEGIN
    SELECT * INTO bib_row FROM biblio.record_entry WHERE id = bib_id;

    IF force_source THEN
        IF new_source IS NOT NULL THEN
            attr_set := attr_set || search.calculate_visibility_attribute(new_source, 'bib_source');
        END IF;
    ELSIF bib_row.source IS NOT NULL THEN
        attr_set := attr_set || search.calculate_visibility_attribute(bib_row.source, 'bib_source');
    END IF;

    FOR cn_row IN
        SELECT  *
          FROM  asset.call_number
          WHERE record = bib_id
                AND label = '##URI##'
                AND NOT deleted
    LOOP
        attr_set := attr_set || search.calculate_visibility_attribute(cn_row.owning_lib, 'luri_org');
    END LOOP;

    RETURN attr_set;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION asset.cache_copy_visibility () RETURNS TRIGGER as $func$
DECLARE
    ocn     asset.call_number%ROWTYPE;
    ncn     asset.call_number%ROWTYPE;
    cid     BIGINT;
    dobib   BOOL;
BEGIN

    SELECT enabled = FALSE INTO dobib FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc';

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
              WHERE record = OLD.peer_record AND target_copy = OLD.target_copy;

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
            NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id, NEW.source, TRUE);
        ELSIF TG_TABLE_NAME = 'call_number' AND NEW.label = '##URI##' AND dobib THEN -- New located URI
            UPDATE  biblio.record_entry
              SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(NEW.record)
              WHERE id = NEW.record;

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
        ELSIF OLD.location   <> NEW.location OR
            OLD.status       <> NEW.status OR
            OLD.opac_visible <> NEW.opac_visible OR
            OLD.circ_lib     <> NEW.circ_lib OR
            OLD.call_number  <> NEW.call_number
        THEN
            IF OLD.call_number  <> NEW.call_number THEN -- Special check since it's more expensive than the next branch
                SELECT * INTO ocn FROM asset.call_number cn WHERE id = OLD.call_number;

                IF ncn.record <> ocn.record THEN
                    -- We have to use a record-specific WHERE clause
                    -- to avoid modifying the entries for peer-bib copies.
                    UPDATE  asset.copy_vis_attr_cache
                      SET   target_copy = NEW.id,
                            record = ncn.record
                      WHERE target_copy = OLD.id
                            AND record = ocn.record;

                END IF;
            ELSE
                -- Any of these could change visibility, but
                -- we'll save some queries and not try to calculate
                -- the change directly.  We want to update peer-bib
                -- entries in this case, unlike above.
                UPDATE  asset.copy_vis_attr_cache
                  SET   target_copy = NEW.id,
                        vis_attr_vector = asset.calculate_copy_visibility_attribute_set(NEW.id)
                  WHERE target_copy = OLD.id;
            END IF;
        END IF;

    ELSIF TG_TABLE_NAME = 'call_number' THEN

        IF TG_OP = 'DELETE' AND OLD.label = '##URI##' AND dobib THEN -- really deleted located URI, if the delete protection rule is disabled...
            UPDATE  biblio.record_entry
              SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
              WHERE id = OLD.record;
            RETURN OLD;
        END IF;

        IF OLD.label = '##URI##' AND dobib THEN -- Located URI
            IF OLD.deleted <> NEW.deleted OR OLD.record <> NEW.record OR OLD.owning_lib <> NEW.owning_lib THEN
                UPDATE  biblio.record_entry
                  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(NEW.record)
                  WHERE id = NEW.record;

                IF OLD.record <> NEW.record THEN -- maybe on merge?
                    UPDATE  biblio.record_entry
                      SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(OLD.record)
                      WHERE id = OLD.record;
                END IF;
            END IF;

        ELSIF OLD.record <> NEW.record OR OLD.owning_lib <> NEW.owning_lib THEN
            UPDATE  asset.copy_vis_attr_cache
              SET   record = NEW.record,
                    vis_attr_vector = asset.calculate_copy_visibility_attribute_set(target_copy)
              WHERE target_copy IN (SELECT id FROM asset.copy WHERE call_number = NEW.id)
                    AND record = OLD.record;

        END IF;

    ELSIF TG_TABLE_NAME = 'record_entry' AND OLD.source IS DISTINCT FROM NEW.source THEN -- Only handles ON UPDATE, INSERT above
        NEW.vis_attr_vector := biblio.calculate_bib_visibility_attribute_set(NEW.id, NEW.source, TRUE);
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

DROP TRIGGER z_opac_vis_mat_view_tgr ON asset.call_number;
DROP TRIGGER z_opac_vis_mat_view_tgr ON biblio.record_entry;
CREATE TRIGGER z_opac_vis_mat_view_tgr AFTER INSERT OR UPDATE OR DELETE ON asset.call_number FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();
CREATE TRIGGER z_opac_vis_mat_view_tgr BEFORE INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE asset.cache_copy_visibility();


SELECT evergreen.upgrade_deps_block_check('1086', :eg_version);

CREATE OR REPLACE FUNCTION asset.location_group_default () RETURNS TEXT AS $f$
    SELECT '!()'::TEXT; -- For now, as there's no way to cause a location group to hide all copies.
/*
    SELECT  '!(' || ARRAY_TO_STRING(ARRAY_AGG(search.calculate_visibility_attribute(id, 'location_group')),'|') || ')'
      FROM  asset.copy_location_group
      WHERE NOT opac_visible;
*/
$f$ LANGUAGE SQL IMMUTABLE;



SELECT evergreen.upgrade_deps_block_check('1087', :eg_version);

CREATE OR REPLACE FUNCTION asset.patron_default_visibility_mask () RETURNS TABLE (b_attrs TEXT, c_attrs TEXT)  AS $f$
DECLARE
    copy_flags      TEXT; -- "c" attr

    owning_lib      TEXT; -- "c" attr
    circ_lib        TEXT; -- "c" attr
    status          TEXT; -- "c" attr
    location        TEXT; -- "c" attr
    location_group  TEXT; -- "c" attr

    luri_org        TEXT; -- "b" attr
    bib_sources     TEXT; -- "b" attr

    bib_tests       TEXT := '';
BEGIN
    copy_flags      := asset.all_visible_flags(); -- Will always have at least one

    owning_lib      := NULLIF(asset.owning_lib_default(),'!()');

    circ_lib        := NULLIF(asset.circ_lib_default(),'!()');
    status          := NULLIF(asset.status_default(),'!()');
    location        := NULLIF(asset.location_default(),'!()');
    location_group  := NULLIF(asset.location_group_default(),'!()');

    -- LURIs will be handled at the perl layer directly
    -- luri_org        := NULLIF(asset.luri_org_default(),'!()');
    bib_sources     := NULLIF(asset.bib_source_default(),'()');


    IF luri_org IS NOT NULL AND bib_sources IS NOT NULL THEN
        bib_tests := '('||ARRAY_TO_STRING( ARRAY[luri_org,bib_sources], '|')||')&('||luri_org||')&';
    ELSIF luri_org IS NOT NULL THEN
        bib_tests := luri_org || '&';
    ELSIF bib_sources IS NOT NULL THEN
        bib_tests := bib_sources || '|';
    END IF;

    RETURN QUERY SELECT bib_tests,
        '('||ARRAY_TO_STRING(
            ARRAY[copy_flags,owning_lib,circ_lib,status,location,location_group]::TEXT[],
            '&'
        )||')';
END;
$f$ LANGUAGE PLPGSQL STABLE ROWS 1;


COMMIT;

\echo ---------------------------------------------------------------------
\echo Updating visibility attribute vector for biblio.record_entry
BEGIN;

ALTER TABLE biblio.record_entry DISABLE TRIGGER  a_marcxml_is_well_formed;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  aaa_indexing_ingest_or_delete;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  audit_biblio_record_entry_update_trigger;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  b_maintain_901;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  bbb_simple_rec_trigger;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  c_maintain_control_numbers;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  fingerprint_tgr;
ALTER TABLE biblio.record_entry DISABLE TRIGGER  z_opac_vis_mat_view_tgr;

UPDATE  biblio.record_entry
  SET   vis_attr_vector = biblio.calculate_bib_visibility_attribute_set(id)
  WHERE id IN (
            SELECT  DISTINCT cn.record
              FROM  asset.call_number cn
              WHERE NOT cn.deleted
                    AND cn.label = '##URI##'
                    AND EXISTS (
                        SELECT  1
                          FROM  asset.uri_call_number_map m
                          WHERE m.call_number = cn.id
                    )
                UNION
            SELECT id FROM biblio.record_entry WHERE source IS NOT NULL
        );

ALTER TABLE biblio.record_entry ENABLE TRIGGER  a_marcxml_is_well_formed;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  aaa_indexing_ingest_or_delete;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  audit_biblio_record_entry_update_trigger;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  b_maintain_901;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  bbb_simple_rec_trigger;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  c_maintain_control_numbers;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  fingerprint_tgr;
ALTER TABLE biblio.record_entry ENABLE TRIGGER  z_opac_vis_mat_view_tgr;

COMMIT;
