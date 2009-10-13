BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0034'); -- miker

CREATE OR REPLACE FUNCTION oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
        normalizer      RECORD;
        value           TEXT := '';
BEGIN
        value := NEW.value;

        IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
                FOR normalizer IN
			SELECT	n.func AS func,
				m.params AS params
			  FROM	config.index_normalizer n
				JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
			  WHERE	field = NEW.field
			  ORDER BY m.pos
		LOOP
			EXECUTE 'SELECT ' || normalizer.func || '(' || quote_literal( value ) || ',' || BTRIM(normalizer.params,'[]') || ')' INTO value;
		END LOOP;
        END IF;

	IF REGEXP_REPLACE(VERSION(),E'^.+?(\\d+\\.\\d+).*?$',E'\\1')::FLOAT > 8.2 THEN
	        NEW.index_vector = to_tsvector((TG_ARGV[0])::regconfig, value);
	ELSE
	        NEW.index_vector = to_tsvector(TG_ARGV[0], value);
	END IF;

        RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

COMMIT;

