BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0519'); -- miker

CREATE OR REPLACE FUNCTION vandelay.marc21_extract_all_fixed_fields( marc TEXT ) RETURNS SETOF biblio.record_ff_map AS $func$
DECLARE
    tag_data    TEXT;
    rtype       TEXT;
    ff_pos      RECORD;
    output      biblio.record_ff_map%ROWTYPE;
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;

    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE rec_type = rtype ORDER BY tag DESC LOOP
        output.ff_name  := ff_pos.fixed_field;
        output.ff_value := NULL;

        IF ff_pos.tag = 'ldr' THEN
            output.ff_value := oils_xpath_string('//*[local-name()="leader"]', marc);
            IF output.ff_value IS NOT NULL THEN
                output.ff_value := SUBSTRING( output.ff_value, ff_pos.start_pos + 1, ff_pos.length );
                RETURN NEXT output;
                output.ff_value := NULL;
            END IF;
        ELSE
            FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(ff_pos.tag) || '"]/text()', marc ) ) x(value) LOOP
                output.ff_value := SUBSTRING( tag_data, ff_pos.start_pos + 1, ff_pos.length );
                IF output.ff_value IS NULL THEN output.ff_value := REPEAT( ff_pos.default_val, ff_pos.length ); END IF;
                RETURN NEXT output;
                output.ff_value := NULL;
            END LOOP;
        END IF;
    
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;

