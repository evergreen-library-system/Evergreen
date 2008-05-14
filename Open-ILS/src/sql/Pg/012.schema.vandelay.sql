DROP SCHEMA vandelay CASCADE;

BEGIN;

CREATE SCHEMA vandelay;

CREATE TABLE vandelay.queue (
	id				BIGSERIAL	PRIMARY KEY,
	owner			INT			NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	name			TEXT		NOT NULL,
	complete		BOOL		NOT NULL DEFAULT FALSE,
	queue_type		TEXT		NOT NULL DEFAULT 'bib' CHECK (queue_type IN ('bib','authority')),
	CONSTRAINT vand_queue_name_once_per_owner_const UNIQUE (owner,name,queue_type)
);

CREATE TABLE vandelay.queued_record (
    id			BIGSERIAL                   PRIMARY KEY,
    create_time	TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    import_time	TIMESTAMP WITH TIME ZONE,
	purpose		TEXT						NOT NULL DEFAULT 'import' CHECK (purpose IN ('import','overlay')),
    marc		TEXT                        NOT NULL
);



/* Bib stuff at the top */
----------------------------------------------------

CREATE TABLE vandelay.bib_attr_definition (
	id			SERIAL	PRIMARY KEY,
	code		TEXT	UNIQUE NOT NULL,
	description	TEXT,
	xpath		TEXT	NOT NULL,
	remove		TEXT	NOT NULL DEFAULT '',
	ident		BOOL	NOT NULL DEFAULT FALSE
);

INSERT INTO vandelay.bib_attr_definition ( code, description, xpath ) VALUES ('title','Title of work','//*[@tag="245"]/*[contains("abcmnopr",@code)]');
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath ) VALUES ('author','Author of work','//*[@tag="100" or @tag="110" or @tag="113"]/*[contains("ad",@code)]');
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath ) VALUES ('language','Lanuage of work','//*[@tag="240"]/*[@code="l"][1]');
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath ) VALUES ('pagination','Pagination','//*[@tag="300"]/*[@code="a"][1]');
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, ident, remove ) VALUES ('isbn','ISBN','//*[@tag="020"]/*[@code="a"]', TRUE, $r$(?:-|\s.+$)$r$);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, ident, remove ) VALUES ('issn','ISSN','//*[@tag="022"]/*[@code="a"]', TRUE, $r$(?:-|\s.+$)$r$);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath ) VALUES ('price','Price','//*[@tag="020" or @tag="022"]/*[@code="c"][1]');
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, ident ) VALUES ('rec_identifier','Identifier','//*[@tag="001"]', TRUE);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, ident ) VALUES ('eg_identifier','Identifier','//*[@tag="901"]/*[@code="c"]', TRUE);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, ident ) VALUES ('eg_tcn','Identifier','//*[@tag="901"]/*[@code="a"]', TRUE);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath ) VALUES ('publisher','Publisher','//*[@tag="260"]/*[@code="b"][1]');
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, remove ) VALUES ('pubdate','Publication Date','//*[@tag="260"]/*[@code="c"][1]',$r$\D$r$);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath ) VALUES ('edition','Edition','//*[@tag="250"]/*[@code="a"][1]');


CREATE TABLE vandelay.bib_queue (
	queue_type	TEXT		NOT NULL DEFAULT 'bib' CHECK (queue_type = 'bib'),
	CONSTRAINT vand_bib_queue_name_once_per_owner_const UNIQUE (owner,name,queue_type)
) INHERITS (vandelay.queue);
ALTER TABLE vandelay.bib_queue ADD PRIMARY KEY (id);

CREATE TABLE vandelay.queued_bib_record (
	queue		INT		NOT NULL REFERENCES vandelay.bib_queue (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	bib_source	INT		REFERENCES config.bib_source (id) DEFERRABLE INITIALLY DEFERRED,
	imported_as	INT		REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED
) INHERITS (vandelay.queued_record);
ALTER TABLE vandelay.queued_bib_record ADD PRIMARY KEY (id);

CREATE TABLE vandelay.queued_bib_record_attr (
	id			BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL REFERENCES vandelay.queued_bib_record (id) DEFERRABLE INITIALLY DEFERRED,
	field		INT			NOT NULL REFERENCES vandelay.bib_attr_definition (id) DEFERRABLE INITIALLY DEFERRED,
	attr_value	TEXT		NOT NULL
);

CREATE TABLE vandelay.bib_match (
	id				BIGSERIAL	PRIMARY KEY,
	field_type		TEXT		NOT NULL CHECK (field_type in ('isbn','tcn_value','id')),
	matched_attr	INT			REFERENCES vandelay.queued_bib_record_attr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	queued_record	BIGINT		REFERENCES vandelay.queued_bib_record (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	eg_record		BIGINT		REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE OR REPLACE FUNCTION vandelay.ingest_bib_marc ( ) RETURNS TRIGGER AS $$
DECLARE
    value   TEXT;
    atype   TEXT;
    adef    RECORD;
BEGIN
    FOR adef IN SELECT * FROM vandelay.bib_attr_definition LOOP

        SELECT extract_marc_field('vandelay.queued_bib_record', id, adef.xpath, adef.remove) INTO value FROM vandelay.queued_bib_record WHERE id = NEW.id;
        IF (value IS NOT NULL AND value <> '') THEN
            INSERT INTO vandelay.queued_bib_record_attr (record, field, attr_value) VALUES (NEW.id, adef.id, value);
        END IF;

    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.match_bib_record ( ) RETURNS TRIGGER AS $func$
DECLARE
    attr    RECORD;
    eg_rec  RECORD;
BEGIN
    FOR attr IN SELECT a.* FROM vandelay.queued_bib_record_attr a JOIN vandelay.bib_attr_definition d ON (d.id = a.field) WHERE record = NEW.id AND d.ident IS TRUE LOOP

		-- All numbers? check for an id match
		IF (attr.attr_value ~ $r$^\d+$$r$) THEN
	        FOR eg_rec IN SELECT * FROM biblio.record_entry WHERE id = attr.attr_value::BIGINT AND deleted IS FALSE LOOP
		        INSERT INTO vandelay.bib_match (field_type, matched_attr, queued_record, eg_record) VALUES ('id', attr.id, NEW.id, eg_rec.id);
			END LOOP;
		END IF;

		-- Looks like an ISBN? check for an isbn match
		IF (attr.attr_value ~* $r$^[0-9x]+$$r$ AND character_length(attr.attr_value) IN (10,13)) THEN
	        FOR eg_rec IN EXECUTE $$SELECT * FROM metabib.full_rec fr WHERE fr.value LIKE LOWER('$$ || attr.attr_value || $$%') AND fr.tag = '020' AND fr.subfield = 'a'$$ LOOP
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

    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.cleanup_bib_marc ( ) RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM vandelay.queued_bib_record_attr WHERE lineitem = OLD.id;
    IF TG_OP = 'UPDATE' THEN
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER cleanup_bib_trigger
    BEFORE UPDATE OR DELETE ON vandelay.queued_bib_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.cleanup_bib_marc();

CREATE TRIGGER ingest_bib_trigger
    AFTER INSERT OR UPDATE ON vandelay.queued_bib_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.ingest_bib_marc();

CREATE TRIGGER zz_match_bibs_trigger
    AFTER INSERT OR UPDATE ON vandelay.queued_bib_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.match_bib_record();


/* Authority stuff down here */
---------------------------------------
CREATE TABLE vandelay.authority_attr_definition (
	id			SERIAL	PRIMARY KEY,
	code		TEXT	UNIQUE NOT NULL,
	description	TEXT,
	xpath		TEXT	NOT NULL,
	remove		TEXT	NOT NULL DEFAULT '',
	ident		BOOL	NOT NULL DEFAULT FALSE
);
INSERT INTO vandelay.authority_attr_definition ( code, description, xpath, ident ) VALUES ('rec_identifier','Identifier','//*[@tag="001"]', TRUE);

CREATE TABLE vandelay.authority_queue (
	queue_type	TEXT		NOT NULL DEFAULT 'authority' CHECK (queue_type = 'authority'),
	CONSTRAINT vand_authority_queue_name_once_per_owner_const UNIQUE (owner,name,queue_type)
) INHERITS (vandelay.queue);
ALTER TABLE vandelay.authority_queue ADD PRIMARY KEY (id);

CREATE TABLE vandelay.queued_authority_record (
	queue		INT	NOT NULL REFERENCES vandelay.authority_queue (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	imported_as	INT	REFERENCES authority.record_entry (id) DEFERRABLE INITIALLY DEFERRED
) INHERITS (vandelay.queued_record);
ALTER TABLE vandelay.queued_authority_record ADD PRIMARY KEY (id);

CREATE TABLE vandelay.queued_authority_record_attr (
	id			BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL REFERENCES vandelay.queued_authority_record (id) DEFERRABLE INITIALLY DEFERRED,
	field		INT			NOT NULL REFERENCES vandelay.authority_attr_definition (id) DEFERRABLE INITIALLY DEFERRED,
	attr_value	TEXT		NOT NULL
);

CREATE TABLE vandelay.authority_match (
	id				BIGSERIAL	PRIMARY KEY,
	matched_attr	INT			REFERENCES vandelay.queued_authority_record_attr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	queued_record	BIGINT		REFERENCES vandelay.queued_authority_record (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	eg_record		BIGINT		REFERENCES authority.record_entry (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE OR REPLACE FUNCTION vandelay.ingest_authority_marc ( ) RETURNS TRIGGER AS $$
DECLARE
    value   TEXT;
    atype   TEXT;
    adef    RECORD;
BEGIN
    FOR adef IN SELECT * FROM vandelay.authority_attr_definition LOOP

        SELECT extract_marc_field('vandelay.queued_authority_record', id, adef.xpath, adef.remove) INTO value FROM vandelay.queued_authority_record WHERE id = NEW.id;
        IF (value IS NOT NULL AND value <> '') THEN
            INSERT INTO vandelay.queued_authority_record_attr (record, field, attr_value) VALUES (NEW.id, adef.id, value);
        END IF;

    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.cleanup_authority_marc ( ) RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM vandelay.queued_authority_record_attr WHERE lineitem = OLD.id;
    IF TG_OP = 'UPDATE' THEN
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER cleanup_authority_trigger
    BEFORE UPDATE OR DELETE ON vandelay.queued_authority_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.cleanup_authority_marc();

CREATE TRIGGER ingest_authority_trigger
    AFTER INSERT OR UPDATE ON vandelay.queued_authority_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.ingest_authority_marc();

COMMIT;

