BEGIN;

SELECT evergreen.upgrade_deps_block_check('0778', :eg_version);

CREATE OR REPLACE FUNCTION extract_marc_field_set
        (TEXT, BIGINT, TEXT, TEXT) RETURNS SETOF TEXT AS $$
DECLARE
    query TEXT;
    output TEXT;
BEGIN
    FOR output IN
        SELECT x.t FROM (
            SELECT id,t
                FROM  oils_xpath_table(
                    'id', 'marc', $1, $3, 'id = ' || $2)
                AS t(id int, t text))x
        LOOP
        IF $4 IS NOT NULL THEN
            SELECT INTO output (SELECT regexp_replace(output, $4, '', 'g'));
        END IF;
        RETURN NEXT output;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;


CREATE OR REPLACE FUNCTION 
        public.extract_acq_marc_field_set ( BIGINT, TEXT, TEXT) 
        RETURNS SETOF TEXT AS $$
	SELECT extract_marc_field_set('acq.lineitem', $1, $2, $3);
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION public.ingest_acq_marc ( ) RETURNS TRIGGER AS $function$
DECLARE
	value		TEXT;
	atype		TEXT;
	prov		INT;
	pos 		INT;
	adef		RECORD;
	xpath_string	TEXT;
BEGIN
	FOR adef IN SELECT *,tableoid FROM acq.lineitem_attr_definition LOOP

		SELECT relname::TEXT INTO atype FROM pg_class WHERE oid = adef.tableoid;

		IF (atype NOT IN ('lineitem_usr_attr_definition','lineitem_local_attr_definition')) THEN
			IF (atype = 'lineitem_provider_attr_definition') THEN
				SELECT provider INTO prov FROM acq.lineitem_provider_attr_definition WHERE id = adef.id;
				CONTINUE WHEN NEW.provider IS NULL OR prov <> NEW.provider;
			END IF;
			
			IF (atype = 'lineitem_provider_attr_definition') THEN
				SELECT xpath INTO xpath_string FROM acq.lineitem_provider_attr_definition WHERE id = adef.id;
			ELSIF (atype = 'lineitem_marc_attr_definition') THEN
				SELECT xpath INTO xpath_string FROM acq.lineitem_marc_attr_definition WHERE id = adef.id;
			ELSIF (atype = 'lineitem_generated_attr_definition') THEN
				SELECT xpath INTO xpath_string FROM acq.lineitem_generated_attr_definition WHERE id = adef.id;
			END IF;

            xpath_string := REGEXP_REPLACE(xpath_string,$re$//?text\(\)$$re$,'');

            IF (adef.code = 'title' OR adef.code = 'author') THEN
                -- title and author should not be split
                -- FIXME: once oils_xpath can grok XPATH 2.0 functions, we can use
                -- string-join in the xpath and remove this special case
    			SELECT extract_acq_marc_field(id, xpath_string, adef.remove) INTO value FROM acq.lineitem WHERE id = NEW.id;
    			IF (value IS NOT NULL AND value <> '') THEN
				    INSERT INTO acq.lineitem_attr (lineitem, definition, attr_type, attr_name, attr_value)
	     			    VALUES (NEW.id, adef.id, atype, adef.code, value);
                END IF;
            ELSE
                pos := 1;
                LOOP
                    -- each application of the regex may produce multiple values
                    FOR value IN
                        SELECT * FROM extract_acq_marc_field_set(
                            NEW.id, xpath_string || '[' || pos || ']', adef.remove)
                        LOOP

                        IF (value IS NOT NULL AND value <> '') THEN
                            INSERT INTO acq.lineitem_attr
                                (lineitem, definition, attr_type, attr_name, attr_value)
                                VALUES (NEW.id, adef.id, atype, adef.code, value);
                        ELSE
                            EXIT;
                        END IF;
                    END LOOP;
                    IF NOT FOUND THEN
                        EXIT;
                    END IF;
                    pos := pos + 1;
               END LOOP;
            END IF;

		END IF;

	END LOOP;

	RETURN NULL;
END;
$function$ LANGUAGE PLPGSQL;

COMMIT;
