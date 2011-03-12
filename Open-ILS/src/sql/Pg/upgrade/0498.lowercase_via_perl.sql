BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0498'); -- dbs

-- Rather than polluting the public schema with general Evergreen
-- functions, carve out a dedicated schema
CREATE SCHEMA evergreen;

-- Replace all uses of PostgreSQL's built-in LOWER() function with
-- a more locale-savvy PLPERLU evergreen.lowercase() function
CREATE OR REPLACE FUNCTION evergreen.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

-- update actor.usr_address indexes
DROP INDEX IF EXISTS actor.actor_usr_addr_street1_idx;
DROP INDEX IF EXISTS actor.actor_usr_addr_street2_idx;
DROP INDEX IF EXISTS actor.actor_usr_addr_city_idx;
DROP INDEX IF EXISTS actor.actor_usr_addr_state_idx; 
DROP INDEX IF EXISTS actor.actor_usr_addr_post_code_idx;

CREATE INDEX actor_usr_addr_street1_idx ON actor.usr_address (evergreen.lowercase(street1));
CREATE INDEX actor_usr_addr_street2_idx ON actor.usr_address (evergreen.lowercase(street2));
CREATE INDEX actor_usr_addr_city_idx ON actor.usr_address (evergreen.lowercase(city));
CREATE INDEX actor_usr_addr_state_idx ON actor.usr_address (evergreen.lowercase(state));
CREATE INDEX actor_usr_addr_post_code_idx ON actor.usr_address (evergreen.lowercase(post_code));

-- update actor.usr indexes
DROP INDEX IF EXISTS actor.actor_usr_first_given_name_idx;
DROP INDEX IF EXISTS actor.actor_usr_second_given_name_idx;
DROP INDEX IF EXISTS actor.actor_usr_family_name_idx;
DROP INDEX IF EXISTS actor.actor_usr_email_idx;
DROP INDEX IF EXISTS actor.actor_usr_day_phone_idx;
DROP INDEX IF EXISTS actor.actor_usr_evening_phone_idx;
DROP INDEX IF EXISTS actor.actor_usr_other_phone_idx;
DROP INDEX IF EXISTS actor.actor_usr_ident_value_idx;
DROP INDEX IF EXISTS actor.actor_usr_ident_value2_idx;

CREATE INDEX actor_usr_first_given_name_idx ON actor.usr (evergreen.lowercase(first_given_name));
CREATE INDEX actor_usr_second_given_name_idx ON actor.usr (evergreen.lowercase(second_given_name));
CREATE INDEX actor_usr_family_name_idx ON actor.usr (evergreen.lowercase(family_name));
CREATE INDEX actor_usr_email_idx ON actor.usr (evergreen.lowercase(email));
CREATE INDEX actor_usr_day_phone_idx ON actor.usr (evergreen.lowercase(day_phone));
CREATE INDEX actor_usr_evening_phone_idx ON actor.usr (evergreen.lowercase(evening_phone));
CREATE INDEX actor_usr_other_phone_idx ON actor.usr (evergreen.lowercase(other_phone));
CREATE INDEX actor_usr_ident_value_idx ON actor.usr (evergreen.lowercase(ident_value));
CREATE INDEX actor_usr_ident_value2_idx ON actor.usr (evergreen.lowercase(ident_value2));

CREATE OR REPLACE FUNCTION vandelay.match_bib_record ( ) RETURNS TRIGGER AS $func$
DECLARE
    attr        RECORD;
    attr_def    RECORD;
    eg_rec      RECORD;
    id_value    TEXT;
    exact_id    BIGINT;
BEGIN

    DELETE FROM vandelay.bib_match WHERE queued_record = NEW.id;

    SELECT * INTO attr_def FROM vandelay.bib_attr_definition WHERE xpath = '//*[@tag="901"]/*[@code="c"]' ORDER BY id LIMIT 1;

    IF attr_def IS NOT NULL AND attr_def.id IS NOT NULL THEN
        id_value := extract_marc_field('vandelay.queued_bib_record', NEW.id, attr_def.xpath, attr_def.remove);
    
        IF id_value IS NOT NULL AND id_value <> '' AND id_value ~ $r$^\d+$$r$ THEN
            SELECT id INTO exact_id FROM biblio.record_entry WHERE id = id_value::BIGINT AND NOT deleted;
            SELECT * INTO attr FROM vandelay.queued_bib_record_attr WHERE record = NEW.id and field = attr_def.id LIMIT 1;
            IF exact_id IS NOT NULL THEN
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, exact_id);
            END IF;
        END IF;
    END IF;

    IF exact_id IS NULL THEN
        FOR attr IN SELECT a.* FROM vandelay.queued_bib_record_attr a JOIN vandelay.bib_attr_definition d ON (d.id = a.field) WHERE record = NEW.id AND d.ident IS TRUE LOOP
    
    		-- All numbers? check for an id match
    		IF (attr.attr_value ~ $r$^\d+$$r$) THEN
    	        FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE id = attr.attr_value::BIGINT AND deleted IS FALSE LOOP
    		        INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
    			END LOOP;
    		END IF;
    
    		-- Looks like an ISBN? check for an isbn match
    		IF (attr.attr_value ~* $r$^[0-9x]+$$r$ AND character_length(attr.attr_value) IN (10,13)) THEN
    	        FOR eg_rec IN EXECUTE $$SELECT * FROM metabib.full_rec fr WHERE fr.value LIKE evergreen.lowercase('$$ || attr.attr_value || $$%') AND fr.tag = '020' AND fr.subfield = 'a'$$ LOOP
    				PERFORM id FROM biblio.record_entry WHERE id = eg_rec.record AND deleted IS FALSE;
    				IF FOUND THEN
    			        INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('isbn', attr.id, NEW.id, eg_rec.record);
    				END IF;
    			END LOOP;
    
    			-- subcheck for isbn-as-tcn
    		    FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = 'i' || attr.attr_value AND deleted IS FALSE LOOP
    			    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
    	        END LOOP;
    		END IF;
    
    		-- check for an OCLC tcn_value match
    		IF (attr.attr_value ~ $r$^o\d+$$r$) THEN
    		    FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = regexp_replace(attr.attr_value,'^o','ocm') AND deleted IS FALSE LOOP
    			    INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
    	        END LOOP;
    		END IF;
    
    		-- check for a direct tcn_value match
            FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE tcn_value = attr.attr_value AND deleted IS FALSE LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('tcn_value', attr.id, NEW.id, eg_rec.id);
            END LOOP;
    
    		-- check for a direct item barcode match
            FOR eg_rec IN
                    SELECT  DISTINCT b.*
                      FROM  biblio.record_entry b
                            JOIN asset.call_number cn ON (cn.record = b.id)
                            JOIN asset.copy cp ON (cp.call_number = cn.id)
                      WHERE cp.barcode = attr.attr_value AND cp.deleted IS FALSE
            LOOP
                INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
            END LOOP;
    
        END LOOP;
    END IF;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;


COMMIT;
