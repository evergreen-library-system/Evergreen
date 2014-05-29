--Upgrade Script for 2.6.0 to 2.6.1
\set eg_version '''2.6.1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.6.1', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0880', :eg_version);

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
                    XPATH('//*[starts-with(@tag,"1")]/@tag',rec_marc_xml)::TEXT[]
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
        -- Loop over the trailing-number contents of all linking subfields
        FOR link IN
            SELECT  SUBSTRING( x::TEXT, '\d+$' )
              FROM  UNNEST(
                        XPATH(
                            '//*[@tag="'
                                || acsaf.tag
                                || '"]/*[@code="'
                                || acsaf.linking_subfield
                                || '"]/text()',
                            rec_marc_xml
                        )
                    ) x
        LOOP

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
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('0881', :eg_version);

UPDATE config.org_unit_setting_type
    SET description = replace(replace(description,'Original','Physical'),'"ol"','"physical_loc"')
    WHERE name = 'opac.org_unit_hiding.depth';

COMMIT;
