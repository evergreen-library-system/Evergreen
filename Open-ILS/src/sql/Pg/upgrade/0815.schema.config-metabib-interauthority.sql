BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0815', :eg_version);

ALTER TABLE authority.control_set_authority_field
    ADD COLUMN linking_subfield CHAR(1);

UPDATE authority.control_set_authority_field
    SET linking_subfield = '0' WHERE main_entry IS NOT NULL;

CREATE TABLE authority.authority_linking (
    id      BIGSERIAL PRIMARY KEY,
    source  BIGINT REFERENCES authority.record_entry (id) NOT NULL,
    target  BIGINT REFERENCES authority.record_entry (id) NOT NULL,
    field   INT REFERENCES authority.control_set_authority_field (id) NOT NULL
);

-- Given an authority record's ID, control set ID (if known), and marc::XML,
-- return all links to other authority records in the form of rows that
-- can be inserted into authority.authority_linking.
CREATE OR REPLACE FUNCTION authority.calculate_authority_linking(
    rec_id BIGINT, rec_control_set INT, rec_marc_xml XML
) RETURNS SETOF authority.authority_linking AS $func$
DECLARE
    acsaf       authority.control_set_authority_field%ROWTYPE;
    link        TEXT;
    aal         authority.authority_linking%ROWTYPE;
BEGIN
    IF rec_control_set IS NULL THEN
        -- No control_set on record?  Guess at one
        SELECT control_set INTO rec_control_set
            FROM authority.control_set_authority_field
            WHERE tag IN (
                SELECT UNNEST(
                    XPATH('//*[starts-with(@tag,"1")]/@tag',rec_marc_xml::XML)::TEXT[]
                )
            ) LIMIT 1;

        IF NOT FOUND THEN
            RAISE WARNING 'Could not even guess at control set for authority record %', rec_id;
            RETURN;
        END IF;
    END IF;

    aal.source := rec_id;

    FOR acsaf IN
        SELECT * FROM authority.control_set_authority_field
        WHERE control_set = rec_control_set
            AND linking_subfield IS NOT NULL
            AND main_entry IS NOT NULL
    LOOP
        link := SUBSTRING(
            (XPATH('//*[@tag="' || acsaf.tag || '"]/*[@code="' ||
                acsaf.linking_subfield || '"]/text()', rec_marc_xml))[1]::TEXT,
            '\d+$'
        );

        -- Ignore links that are null, malformed, circular, or point to
        -- non-existent authority records.
        IF link IS NOT NULL AND link::BIGINT <> rec_id THEN
            PERFORM * FROM authority.record_entry WHERE id = link::BIGINT;
            IF FOUND THEN
                aal.target := link::BIGINT;
                aal.field := acsaf.id;
                RETURN NEXT aal;
            END IF;
        END IF;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;


-- AFTER UPDATE OR INSERT trigger for authority.record_entry
CREATE OR REPLACE FUNCTION authority.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this authority is deleted
        DELETE FROM authority.bib_linking WHERE authority = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM authority.full_rec WHERE record = NEW.id; -- Avoid validating fields against deleted authority records
        DELETE FROM authority.simple_heading WHERE record = NEW.id;
          -- Should remove matching $0 from controlled fields at the same time?

        -- XXX What do we about the actual linking subfields present in
        -- authority records that target this one when this happens?
        DELETE FROM authority.authority_linking
            WHERE source = NEW.id OR target = NEW.id;

        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;

        -- Propagate these updates to any linked bib records
        PERFORM authority.propagate_changes(NEW.id) FROM authority.record_entry WHERE id = NEW.id;

        DELETE FROM authority.simple_heading WHERE record = NEW.id;
        DELETE FROM authority.authority_linking WHERE source = NEW.id;
    END IF;

    INSERT INTO authority.authority_linking (source, target, field)
        SELECT source, target, field FROM authority.calculate_authority_linking(
            NEW.id, NEW.control_set, NEW.marc::XML
        );

    INSERT INTO authority.simple_heading (record,atag,value,sort_value)
        SELECT record, atag, value, sort_value FROM authority.simple_heading_set(NEW.marc);

    -- Flatten and insert the afr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.reingest_authority_full_rec(NEW.id);
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM authority.reingest_authority_rec_descriptor(NEW.id);
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
