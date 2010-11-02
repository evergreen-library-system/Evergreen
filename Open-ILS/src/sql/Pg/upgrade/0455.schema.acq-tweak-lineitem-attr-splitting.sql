BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0455'); -- gmc

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
    			    SELECT extract_acq_marc_field(id, xpath_string || '[' || pos || ']', adef.remove) INTO value FROM acq.lineitem WHERE id = NEW.id;

    			    IF (value IS NOT NULL AND value <> '') THEN
	    			    INSERT INTO acq.lineitem_attr (lineitem, definition, attr_type, attr_name, attr_value)
		    			    VALUES (NEW.id, adef.id, atype, adef.code, value);
                    ELSE
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
