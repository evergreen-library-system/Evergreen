--Upgrade Script for 2.7.1 to 2.7.2
\set eg_version '''2.7.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.7.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0896', :eg_version);

CREATE OR REPLACE FUNCTION asset.acp_location_fixer()
RETURNS TRIGGER AS $$
DECLARE
    new_copy_location INT;
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF NEW.location = OLD.location AND NEW.call_number = OLD.call_number AND NEW.circ_lib = OLD.circ_lib THEN
            RETURN NEW;
        END IF;
    END IF;
    SELECT INTO new_copy_location acpl.id FROM asset.copy_location acpl JOIN actor.org_unit_ancestors_distance((SELECT owning_lib FROM asset.call_number WHERE id = NEW.call_number)) aouad ON acpl.owning_lib = aouad.id WHERE name = (SELECT name FROM asset.copy_location WHERE id = NEW.location) ORDER BY distance LIMIT 1;
    IF new_copy_location IS NULL THEN
        SELECT INTO new_copy_location acpl.id FROM asset.copy_location acpl JOIN actor.org_unit_ancestors_distance(NEW.circ_lib) aouad ON acpl.owning_lib = aouad.id WHERE name = (SELECT name FROM asset.copy_location WHERE id = NEW.location) ORDER BY distance LIMIT 1;
    END IF;
    IF new_copy_location IS NOT NULL THEN
        NEW.location = new_copy_location;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS acp_location_fixer_trig ON asset.copy;

CREATE TRIGGER acp_location_fixer_trig
    BEFORE INSERT OR UPDATE OF location, call_number, circ_lib ON asset.copy
    FOR EACH ROW EXECUTE PROCEDURE asset.acp_location_fixer();


SELECT evergreen.upgrade_deps_block_check('0897', :eg_version);

CREATE OR REPLACE FUNCTION authority.indexing_ingest_or_delete() RETURNS TRIGGER AS $BODY$
DECLARE
    ashs    authority.simple_heading%ROWTYPE;
    mbe_row metabib.browse_entry%ROWTYPE;
    mbe_id  BIGINT;
    ash_id  BIGINT;
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

        -- Unless there's a setting stopping us, propagate these updates to any linked bib records
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_auto_update' AND enabled;

        IF NOT FOUND THEN
            PERFORM authority.propagate_changes(NEW.id);
        END IF;

        DELETE FROM authority.simple_heading WHERE record = NEW.id;
        DELETE FROM authority.authority_linking WHERE source = NEW.id;
    END IF;

    INSERT INTO authority.authority_linking (source, target, field)
        SELECT source, target, field FROM authority.calculate_authority_linking(
            NEW.id, NEW.control_set, NEW.marc::XML
        );

    FOR ashs IN SELECT * FROM authority.simple_heading_set(NEW.marc) LOOP

        INSERT INTO authority.simple_heading (record,atag,value,sort_value)
            VALUES (ashs.record, ashs.atag, ashs.value, ashs.sort_value);
        ash_id := CURRVAL('authority.simple_heading_id_seq'::REGCLASS);

        SELECT INTO mbe_row * FROM metabib.browse_entry
            WHERE value = ashs.value AND sort_value = ashs.sort_value;

        IF FOUND THEN
            mbe_id := mbe_row.id;
        ELSE
            INSERT INTO metabib.browse_entry
                ( value, sort_value ) VALUES
                ( ashs.value, ashs.sort_value );

            mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
        END IF;

        INSERT INTO metabib.browse_entry_simple_heading_map (entry,simple_heading) VALUES (mbe_id,ash_id);

    END LOOP;

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
$BODY$ LANGUAGE plpgsql;



SELECT evergreen.upgrade_deps_block_check('0898', :eg_version);

CREATE OR REPLACE FUNCTION unapi.mmr_mra (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE,
    pref_lib INT DEFAULT NULL
) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
        name attributes,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@mmr/' || $1 AS metarecord
        ),
        (SELECT XMLAGG(foo.y)
          FROM (
            WITH sourcelist AS (
                WITH aou AS (SELECT COALESCE(id, (evergreen.org_top()).id) AS id
                    FROM actor.org_unit WHERE shortname = $5 LIMIT 1)
                SELECT source
                FROM metabib.metarecord_source_map, aou
                WHERE metarecord = $1 AND (
                    EXISTS (
                        SELECT 1 FROM asset.opac_visible_copies
                        WHERE record = source AND circ_lib IN (
                            SELECT id FROM actor.org_unit_descendants(aou.id, $6))
                        LIMIT 1
                    )
                    OR EXISTS (SELECT 1 FROM located_uris(source, aou.id, $10) LIMIT 1)
                )
            )
            SELECT  cmra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            cmra.attr AS name,
                            cmra.value AS "coded-value",
                            cmra.aid AS "cvmid",
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        cmra.value
                    )
              FROM  (
                SELECT DISTINCT aid, attr, value
                  FROM (
                    SELECT  v.source AS id,
                            c.id AS aid,
                            c.ctype AS attr,
                            c.code AS value
                      FROM  metabib.record_attr_vector_list v
                            JOIN config.coded_value_map c ON ( c.id = ANY( v.vlist ) )
                    ) AS x
                    JOIN sourcelist ON (x.id = sourcelist.source)
                ) AS cmra
                JOIN config.record_attr_definition rad ON (cmra.attr = rad.name)
                UNION ALL
            SELECT  umra.aid,
                    XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            umra.attr AS name,
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        umra.value
                    )
              FROM  (
                SELECT DISTINCT aid, attr, value
                  FROM (
                    SELECT  v.source AS id,
                            m.id AS aid,
                            m.attr AS attr,
                            m.value AS value
                      FROM  metabib.record_attr_vector_list v
                            JOIN metabib.uncontrolled_record_attr_value m ON ( m.id = ANY( v.vlist ) )
                    ) AS x
                    JOIN sourcelist ON (x.id = sourcelist.source)
                ) AS umra
                JOIN config.record_attr_definition rad ON (umra.attr = rad.name)
                ORDER BY 1

            )foo(id,y)
        )
    )
$F$ LANGUAGE SQL STABLE;



SELECT evergreen.upgrade_deps_block_check('0899', :eg_version);

ALTER FUNCTION asset.label_normalizer_generic(TEXT) IMMUTABLE;
ALTER FUNCTION asset.label_normalizer_dewey(TEXT) IMMUTABLE;
ALTER FUNCTION asset.label_normalizer_lc(TEXT) IMMUTABLE;


SELECT evergreen.upgrade_deps_block_check('0900', :eg_version);

CREATE OR REPLACE VIEW metabib.record_attr AS
    SELECT  id, HSTORE( ARRAY_AGG( attr ), ARRAY_AGG( value ) ) AS attrs
      FROM  metabib.record_attr_flat
      WHERE attr IS NOT NULL
      GROUP BY 1;


COMMIT;

-- Include helpful note to run 2.6.2-2.6.3 if missed during 2.6-2.7 upgrade
\qecho **** NOTICE ****
\qecho 'There was a missed upgrade script on the path from 2.6 series'
\qecho 'to 2.7 series. If you are upgrading from 2.7.1 and have not'
\qecho 'already run 2.6.2-2.6.3-upgrade-db.sql script, please go back'
\qecho 'and run now to receive those missed fixes.'
