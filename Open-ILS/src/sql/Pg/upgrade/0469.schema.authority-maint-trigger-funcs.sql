BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0469'); -- miker

CREATE OR REPLACE FUNCTION vandelay.replace_field ( target_xml TEXT, source_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
DECLARE
    xml_output TEXT;
    parsed_target TEXT;
BEGIN
    parsed_target := vandelay.strip_field( target_xml, ''); -- this dance normalized the format of the xml for the IF below
    xml_output := vandelay.strip_field( parsed_target, field);

    IF xml_output <> parsed_target  AND field ~ E'~' THEN
        -- we removed something, and there was a regexp restriction in the field definition, so proceed
        xml_output := vandelay.add_field( xml_output, source_xml, field, 1 );
    ELSIF field !~ E'~' THEN
        -- No regexp restriction, add the field
        xml_output := vandelay.add_field( xml_output, source_xml, field, 0 );
    END IF;

    RETURN xml_output;
END;
$_$ LANGUAGE PLPGSQL;

COMMIT;

