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
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, ident ) VALUES ('rec_identifier','Accession Number','//*[@tag="001"]', TRUE);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, ident ) VALUES ('eg_tcn','TCN Value','//*[@tag="901"]/*[@code="a"]', TRUE);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, ident ) VALUES ('eg_tcn_source','TCN Source','//*[@tag="901"]/*[@code="b"]', TRUE);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, ident ) VALUES ('eg_identifier','Internal ID','//*[@tag="901"]/*[@code="c"]', TRUE);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath ) VALUES ('publisher','Publisher','//*[@tag="260"]/*[@code="b"][1]');
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath, remove ) VALUES ('pubdate','Publication Date','//*[@tag="260"]/*[@code="c"][1]',$r$\D$r$);
INSERT INTO vandelay.bib_attr_definition ( code, description, xpath ) VALUES ('edition','Edition','//*[@tag="250"]/*[@code="a"][1]');


-- Each TEXT field (other than 'name') should hold an XPath predicate for pulling the data needed
-- DROP TABLE vandelay.import_item_attr_definition CASCADE;
CREATE TABLE vandelay.import_item_attr_definition (
    id              BIGSERIAL   PRIMARY KEY,
    owner           INT         NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT        NOT NULL,
    tag             TEXT        NOT NULL,
    keep            BOOL        NOT NULL DEFAULT FALSE,
    owning_lib      TEXT,
    circ_lib        TEXT,
    call_number     TEXT,
    copy_number     TEXT,
    status          TEXT,
    location        TEXT,
    circulate       TEXT,
    deposit         TEXT,
    deposit_amount  TEXT,
    ref             TEXT,
    holdable        TEXT,
    price           TEXT,
    barcode         TEXT,
    circ_modifier   TEXT,
    circ_as_type    TEXT,
    alert_message   TEXT,
    opac_visible    TEXT,
    pub_note_title  TEXT,
    pub_note        TEXT,
    priv_note_title TEXT,
    priv_note       TEXT,
	CONSTRAINT vand_import_item_attr_def_idx UNIQUE (owner,name)
);

INSERT INTO vandelay.import_item_attr_definition (
    owner, name, tag, owning_lib, circ_lib, location,
    call_number, circ_modifier, barcode, price, copy_number,
    circulate, ref, holdable, opac_visible, status
) VALUES (
    1,
    'Evergreen 852 export format',
    '852',
    '[@code = "b"][1]',
    '[@code = "b"][2]',
    'c',
    'j',
    'g',
    'p',
    'y',
    't',
    '[@code = "x" and text() = "circulating"]',
    '[@code = "x" and text() = "reference"]',
    '[@code = "x" and text() = "holdable"]',
    '[@code = "x" and text() = "visible"]',
    'z'
);

INSERT INTO vandelay.import_item_attr_definition (
    owner,
    name,
    tag,
    owning_lib,
    location,
    call_number,
    circ_modifier,
    barcode,
    price,
    status
) VALUES (
    1,
    'Unicorn Import format -- 999',
    '999',
    'm',
    'l',
    'a',
    't',
    'i',
    'p',
    'k'
);

CREATE TABLE vandelay.bib_queue (
	queue_type	    TEXT	NOT NULL DEFAULT 'bib' CHECK (queue_type = 'bib'),
	item_attr_def	TEXT	REFERENCES vandelay.import_item_attr_definition (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
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
	eg_record		BIGINT		REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

-- DROP TABLE vandelay.import_item CASCADE;
CREATE TABLE vandelay.import_item (
    id              BIGSERIAL   PRIMARY KEY,
    record          BIGINT      NOT NULL REFERENCES vandelay.queued_bib_record (id) ON DELETE CASCADE,
    definition      BIGINT      NOT NULL REFERENCES vandelay.import_item_attr_definition (id) ON DELETE CASCADE,
    owning_lib      INT,
    circ_lib        INT,
    call_number     TEXT,
    copy_number     INT,
    status          INT,
    location        INT,
    circulate       BOOL,
    deposit         BOOL,
    deposit_amount  NUMERIC(8,2),
    ref             BOOL,
    holdable        BOOL,
    price           NUMERIC(8,2),
    barcode         TEXT,
    circ_modifier   TEXT,
    circ_as_type    TEXT,
    alert_message   TEXT,
    pub_note        TEXT,
    priv_note       TEXT,
    opac_visible    BOOL
);
 
CREATE TABLE vandelay.import_bib_trash_fields (
    id              BIGSERIAL   PRIMARY KEY,
    owner           INT         NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    field           TEXT        NOT NULL,
	CONSTRAINT vand_import_bib_trash_fields_idx UNIQUE (owner,field)
);

CREATE OR REPLACE FUNCTION vandelay.strip_field ( xml TEXT, field TEXT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML;

    my $xml = shift;
    my $field_spec = shift;

    my $r = MARC::Record->new_from_xml( $xml );
    $r->delete_field( $_ ) for ( $r->field( $field_spec ) );

    $xml = $r->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$_$ LANGUAGE PLPERLU;


CREATE OR REPLACE FUNCTION vandelay.ingest_items ( import_id BIGINT, attr_def_id BIGINT ) RETURNS SETOF vandelay.import_item AS $$
DECLARE

    owning_lib      TEXT;
    circ_lib        TEXT;
    call_number     TEXT;
    copy_number     TEXT;
    status          TEXT;
    location        TEXT;
    circulate       TEXT;
    deposit         TEXT;
    deposit_amount  TEXT;
    ref             TEXT;
    holdable        TEXT;
    price           TEXT;
    barcode         TEXT;
    circ_modifier   TEXT;
    circ_as_type    TEXT;
    alert_message   TEXT;
    opac_visible    TEXT;
    pub_note        TEXT;
    priv_note       TEXT;

    attr_def        RECORD;
    tmp_attr_set    RECORD;
    attr_set        vandelay.import_item%ROWTYPE;

    xpath           TEXT;

BEGIN

    SELECT * INTO attr_def FROM vandelay.import_item_attr_definition WHERE id = attr_def_id;

    IF FOUND THEN

        attr_set.definition := attr_def.id; 
    
        -- Build the combined XPath
    
        owning_lib :=
            CASE
                WHEN attr_def.owning_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.owning_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.owning_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.owning_lib
            END;
    
        circ_lib :=
            CASE
                WHEN attr_def.circ_lib IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_lib ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_lib || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_lib
            END;
    
        call_number :=
            CASE
                WHEN attr_def.call_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.call_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.call_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.call_number
            END;
    
        copy_number :=
            CASE
                WHEN attr_def.copy_number IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.copy_number ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.copy_number || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.copy_number
            END;
    
        status :=
            CASE
                WHEN attr_def.status IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.status ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.status || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.status
            END;
    
        location :=
            CASE
                WHEN attr_def.location IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.location ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.location || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.location
            END;
    
        circulate :=
            CASE
                WHEN attr_def.circulate IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circulate ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circulate || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circulate
            END;
    
        deposit :=
            CASE
                WHEN attr_def.deposit IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit
            END;
    
        deposit_amount :=
            CASE
                WHEN attr_def.deposit_amount IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.deposit_amount ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.deposit_amount || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.deposit_amount
            END;
    
        ref :=
            CASE
                WHEN attr_def.ref IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.ref ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.ref || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.ref
            END;
    
        holdable :=
            CASE
                WHEN attr_def.holdable IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.holdable ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.holdable || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.holdable
            END;
    
        price :=
            CASE
                WHEN attr_def.price IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.price ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.price || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.price
            END;
    
        barcode :=
            CASE
                WHEN attr_def.barcode IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.barcode ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.barcode || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.barcode
            END;
    
        circ_modifier :=
            CASE
                WHEN attr_def.circ_modifier IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_modifier ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_modifier || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_modifier
            END;
    
        circ_as_type :=
            CASE
                WHEN attr_def.circ_as_type IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.circ_as_type ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.circ_as_type || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.circ_as_type
            END;
    
        alert_message :=
            CASE
                WHEN attr_def.alert_message IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.alert_message ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.alert_message || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.alert_message
            END;
    
        opac_visible :=
            CASE
                WHEN attr_def.opac_visible IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.opac_visible ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.opac_visible || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.opac_visible
            END;

        pub_note :=
            CASE
                WHEN attr_def.pub_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.pub_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.pub_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.pub_note
            END;
        priv_note :=
            CASE
                WHEN attr_def.priv_note IS NULL THEN 'null()'
                WHEN LENGTH( attr_def.priv_note ) = 1 THEN '//*[@tag="' || attr_def.tag || '"]/*[@code="' || attr_def.priv_note || '"]'
                ELSE '//*[@tag="' || attr_def.tag || '"]/*' || attr_def.priv_note
            END;
    
    
        xpath := 
            owning_lib      || '|' || 
            circ_lib        || '|' || 
            call_number     || '|' || 
            copy_number     || '|' || 
            status          || '|' || 
            location        || '|' || 
            circulate       || '|' || 
            deposit         || '|' || 
            deposit_amount  || '|' || 
            ref             || '|' || 
            holdable        || '|' || 
            price           || '|' || 
            barcode         || '|' || 
            circ_modifier   || '|' || 
            circ_as_type    || '|' || 
            alert_message   || '|' || 
            pub_note        || '|' || 
            priv_note       || '|' || 
            opac_visible;

        -- RAISE NOTICE 'XPath: %', xpath;
        
        FOR tmp_attr_set IN
                SELECT  *
                  FROM  xpath_table( 'id', 'marc', 'vandelay.queued_bib_record', xpath, 'id = ' || import_id )
                            AS t( id BIGINT, ol TEXT, clib TEXT, cn TEXT, cnum TEXT, cs TEXT, cl TEXT, circ TEXT,
                                  dep TEXT, dep_amount TEXT, r TEXT, hold TEXT, pr TEXT, bc TEXT, circ_mod TEXT,
                                  circ_as TEXT, amessage TEXT, note TEXT, pnote TEXT, opac_vis TEXT )
        LOOP
    
            tmp_attr_set.pr = REGEXP_REPLACE(tmp_attr_set.pr, E'[^0-9\\.]', '', 'g');
            tmp_attr_set.dep_amount = REGEXP_REPLACE(tmp_attr_set.dep_amount, E'[^0-9\\.]', '', 'g');

            tmp_attr_set.pr := NULLIF( tmp_attr_set.pr, '' );
            tmp_attr_set.dep_amount := NULLIF( tmp_attr_set.dep_amount, '' );
    
            SELECT id INTO attr_set.owning_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.ol); -- INT
            SELECT id INTO attr_set.circ_lib FROM actor.org_unit WHERE shortname = UPPER(tmp_attr_set.clib); -- INT
            SELECT id INTO attr_set.status FROM config.copy_status WHERE LOWER(name) = LOWER(tmp_attr_set.cs); -- INT
    
            SELECT  id INTO attr_set.location
              FROM  asset.copy_location
              WHERE LOWER(name) = LOWER(tmp_attr_set.cl)
                    AND owning_lib = COALESCE(attr_set.owning_lib, attr_set.circ_lib); -- INT
    
            attr_set.circulate      :=
                LOWER( SUBSTRING( tmp_attr_set.circ, 1, 1)) IN ('t','y','1')
                OR LOWER(tmp_attr_set.circ) = 'circulating'; -- BOOL

            attr_set.deposit        :=
                LOWER( SUBSTRING( tmp_attr_set.dep, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.dep) = 'deposit'; -- BOOL

            attr_set.holdable       :=
                LOWER( SUBSTRING( tmp_attr_set.hold, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.hold) = 'holdable'; -- BOOL

            attr_set.opac_visible   :=
                LOWER( SUBSTRING( tmp_attr_set.opac_vis, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.opac_vis) = 'visible'; -- BOOL

            attr_set.ref            :=
                LOWER( SUBSTRING( tmp_attr_set.r, 1, 1 ) ) IN ('t','y','1')
                OR LOWER(tmp_attr_set.r) = 'reference'; -- BOOL
    
            attr_set.copy_number    := tmp_attr_set.cnum::INT; -- INT,
            attr_set.deposit_amount := tmp_attr_set.dep_amount::NUMERIC(6,2); -- NUMERIC(6,2),
            attr_set.price          := tmp_attr_set.pr::NUMERIC(8,2); -- NUMERIC(8,2),
    
            attr_set.call_number    := tmp_attr_set.cn; -- TEXT
            attr_set.barcode        := tmp_attr_set.bc; -- TEXT,
            attr_set.circ_modifier  := tmp_attr_set.circ_mod; -- TEXT,
            attr_set.circ_as_type   := tmp_attr_set.circ_as; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
            attr_set.pub_note       := tmp_attr_set.note; -- TEXT,
            attr_set.priv_note      := tmp_attr_set.pnote; -- TEXT,
            attr_set.alert_message  := tmp_attr_set.amessage; -- TEXT,
    
            RETURN NEXT attr_set;
    
        END LOOP;
    
    END IF;

END;
$$ LANGUAGE PLPGSQL;


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

CREATE OR REPLACE FUNCTION vandelay.ingest_bib_items ( ) RETURNS TRIGGER AS $func$
DECLARE
    queue_rec   RECORD;
    item_rule   RECORD;
    item_data   vandelay.import_item%ROWTYPE;
BEGIN

    SELECT * INTO queue_rec FROM vandelay.bib_queue WHERE id = NEW.queue;

    FOR item_rule IN SELECT r.* FROM actor.org_unit_ancestors( queue_rec.owner ) o JOIN vandelay.import_item_attr_definition r ON ( r.owner = o.id ) LOOP
        FOR item_data IN SELECT * FROM vandelay.ingest_items( NEW.id::BIGINT, item_rule.id::BIGINT ) LOOP
            INSERT INTO vandelay.import_item (
		record,
                definition,
                owning_lib,
                circ_lib,
                call_number,
                copy_number,
                status,
                location,
                circulate,
                deposit,
                deposit_amount,
                ref,
                holdable,
                price,
                barcode,
                circ_modifier,
                circ_as_type,
                alert_message,
                pub_note,
                priv_note,
                opac_visible
            ) VALUES (
		NEW.id,
                item_data.definition,
                item_data.owning_lib,
                item_data.circ_lib,
                item_data.call_number,
                item_data.copy_number,
                item_data.status,
                item_data.location,
                item_data.circulate,
                item_data.deposit,
                item_data.deposit_amount,
                item_data.ref,
                item_data.holdable,
                item_data.price,
                item_data.barcode,
                item_data.circ_modifier,
                item_data.circ_as_type,
                item_data.alert_message,
                item_data.pub_note,
                item_data.priv_note,
                item_data.opac_visible
            );
        END LOOP;
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

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
    DELETE FROM vandelay.queued_bib_record_attr WHERE record = OLD.id;
    DELETE FROM vandelay.import_item WHERE record = OLD.id;

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

CREATE TRIGGER ingest_item_trigger
    AFTER INSERT OR UPDATE ON vandelay.queued_bib_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.ingest_bib_items();

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
    DELETE FROM vandelay.queued_authority_record_attr WHERE record = OLD.id;
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

