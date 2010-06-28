BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0319'); --miker

-- Making this a global_flag (UI accessible) instead of an internal_flag
INSERT INTO config.global_flag (name, label) -- defaults to enabled=FALSE
    VALUES (
        'ingest.disable_authority_linking',
        oils_i18n_gettext(
            'ingest.disable_authority_linking',
            'Authority Automation: Disable bib-authority link tracking',
            'cgf', 
            'label'
        )
    );
UPDATE config.global_flag SET enabled = (SELECT enabled FROM ONLY config.internal_flag WHERE name = 'ingest.disable_authority_linking');
DELETE FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking';

INSERT INTO config.global_flag (name, label) -- defaults to enabled=FALSE
    VALUES (
        'ingest.disable_authority_auto_update',
        oils_i18n_gettext(
            'ingest.disable_authority_auto_update',
            'Authority Automation: Disable automatic authority updating (requires link tracking)',
            'cgf', 
            'label'
        )
    );


CREATE OR REPLACE FUNCTION authority.propagate_changes (aid BIGINT, bid BIGINT) RETURNS BIGINT AS $func$
    UPDATE  biblio.record_entry
      SET   marc = vandelay.merge_record_xml( marc, authority.generate_overlay_template( $1 ) )
      WHERE id = $2;
    SELECT $2;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.propagate_changes (aid BIGINT) RETURNS SETOF BIGINT AS $func$
    SELECT authority.propagate_changes( authority, bib ) FROM authority.bib_linking WHERE authority = $1;
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION authority.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this authority is deleted
        RETURN NEW; -- and ... we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;


    -- authority change propogation
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_auto_update' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.propagate_changes( NEW.id );
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER aaa_auth_ingest_or_delete AFTER INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE authority.indexing_ingest_or_delete ();


COMMIT;

