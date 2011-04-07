BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0508'); -- gmc

CREATE OR REPLACE FUNCTION maintain_901 () RETURNS TRIGGER AS $func$
DECLARE
    use_id_for_tcn BOOLEAN;
    norm_tcn_value TEXT;
    norm_tcn_source TEXT;
BEGIN
    -- Remove any existing 901 fields before we insert the authoritative one
    NEW.marc := REGEXP_REPLACE(NEW.marc, E'<datafield[^>]*?tag="901".+?</datafield>', '', 'g');

    IF TG_TABLE_SCHEMA = 'biblio' THEN
        -- Set TCN value to record ID?
        SELECT enabled FROM config.global_flag INTO use_id_for_tcn
            WHERE name = 'cat.bib.use_id_for_tcn';

        IF use_id_for_tcn = 't' THEN
            NEW.tcn_value := NEW.id;
            norm_tcn_value := NEW.tcn_value;
        ELSE
            -- yes, ampersands can show up in tcn_values ...
            norm_tcn_value := REGEXP_REPLACE(NEW.tcn_value, E'&(?!\\S+;)', '&amp;', 'g');
        END IF;
        -- ... and TCN sources
        -- FIXME we have here yet another (stub) version of entityize
        norm_tcn_source := REGEXP_REPLACE(NEW.tcn_source, E'&(?!\\S+;)', '&amp;', 'g');

        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="a">' || norm_tcn_value || E'</subfield>' ||
                '<subfield code="b">' || norm_tcn_source || E'</subfield>' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                CASE WHEN NEW.owner IS NOT NULL THEN '<subfield code="o">' || NEW.owner || E'</subfield>' ELSE '' END ||
                CASE WHEN NEW.share_depth IS NOT NULL THEN '<subfield code="d">' || NEW.share_depth || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'authority' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    ELSIF TG_TABLE_SCHEMA = 'serial' THEN
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
                '<subfield code="o">' || NEW.owning_lib || E'</subfield>' ||
                CASE WHEN NEW.record IS NOT NULL THEN '<subfield code="r">' || NEW.record || E'</subfield>' ELSE '' END ||
             E'</datafield>\\1'
        );
    ELSE
        NEW.marc := REGEXP_REPLACE(
            NEW.marc,
            E'(</(?:[^:]*?:)?record>)',
            E'<datafield tag="901" ind1=" " ind2=" ">' ||
                '<subfield code="c">' || NEW.id || E'</subfield>' ||
                '<subfield code="t">' || TG_TABLE_SCHEMA || E'</subfield>' ||
             E'</datafield>\\1'
        );
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
