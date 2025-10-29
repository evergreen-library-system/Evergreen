DROP SCHEMA IF EXISTS vandelay CASCADE;

BEGIN;

CREATE SCHEMA vandelay;

CREATE TABLE vandelay.match_set (
    id      SERIAL  PRIMARY KEY,
    name    TEXT        NOT NULL,
    owner   INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE,
    mtype   TEXT        NOT NULL DEFAULT 'biblio', -- 'biblio','authority','mfhd'?, others?
    CONSTRAINT name_once_per_owner_mtype UNIQUE (name, owner, mtype)
);

-- Table to define match points, either FF via SVF or tag+subfield
CREATE TABLE vandelay.match_set_point (
    id          SERIAL  PRIMARY KEY,
    match_set   INT     REFERENCES vandelay.match_set (id) ON DELETE CASCADE,
    parent      INT     REFERENCES vandelay.match_set_point (id),
    bool_op     TEXT    CHECK (bool_op IS NULL OR (bool_op IN ('AND','OR','NOT'))),
    svf         TEXT    REFERENCES config.record_attr_definition (name),
    tag         TEXT,
    subfield    TEXT,
    negate      BOOL    DEFAULT FALSE,
    quality     INT     NOT NULL DEFAULT 1, -- higher is better
    heading     BOOLEAN NOT NULL DEFAULT FALSE, -- match on authority heading
    CONSTRAINT vmsp_need_a_subfield_with_a_tag CHECK ((tag IS NOT NULL AND subfield IS NOT NULL) OR tag IS NULL),
    CONSTRAINT vmsp_need_a_tag_or_a_ff_or_a_bo CHECK (
        (tag IS NOT NULL AND svf IS NULL AND heading IS FALSE AND bool_op IS NULL) OR 
        (tag IS NULL AND svf IS NOT NULL AND heading IS FALSE AND bool_op IS NULL) OR 
        (tag IS NULL AND svf IS NULL AND heading IS TRUE AND bool_op IS NULL) OR 
        (tag IS NULL AND svf IS NULL AND heading IS FALSE AND bool_op IS NOT NULL)
    )
);

CREATE TABLE vandelay.match_set_quality (
    id          SERIAL  PRIMARY KEY,
    match_set   INT     NOT NULL REFERENCES vandelay.match_set (id) ON DELETE CASCADE,
    svf         TEXT    REFERENCES config.record_attr_definition,
    tag         TEXT,
    subfield    TEXT,
    value       TEXT    NOT NULL,
    quality     INT     NOT NULL DEFAULT 1, -- higher is better
    CONSTRAINT vmsq_need_a_subfield_with_a_tag CHECK ((tag IS NOT NULL AND subfield IS NOT NULL) OR tag IS NULL),
    CONSTRAINT vmsq_need_a_tag_or_a_ff CHECK ((tag IS NOT NULL AND svf IS NULL) OR (tag IS NULL AND svf IS NOT NULL))
);
CREATE UNIQUE INDEX vmsq_def_once_per_set ON vandelay.match_set_quality (match_set, COALESCE(tag,''), COALESCE(subfield,''), COALESCE(svf,''), value);


CREATE TABLE vandelay.queue (
	id				BIGSERIAL	PRIMARY KEY,
	owner			INT			NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	name			TEXT		NOT NULL,
	complete		BOOL		NOT NULL DEFAULT FALSE,
    match_set       INT         REFERENCES vandelay.match_set (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE vandelay.queued_record (
    id			BIGSERIAL                   PRIMARY KEY,
    create_time	TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    import_time	TIMESTAMP WITH TIME ZONE,
	purpose		TEXT						NOT NULL DEFAULT 'import' CHECK (purpose IN ('import','overlay')),
    marc		TEXT                        NOT NULL,
    quality     INT                         NOT NULL DEFAULT 0
);



/* Bib stuff at the top */
----------------------------------------------------

CREATE TABLE vandelay.bib_attr_definition (
	id			SERIAL	PRIMARY KEY,
	code		TEXT	UNIQUE NOT NULL,
	description	TEXT,
	xpath		TEXT	NOT NULL,
	remove		TEXT	NOT NULL DEFAULT ''
);

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
    internal_id     TEXT,
    stat_cat_data   TEXT,
    parts_data      TEXT,
    floating        TEXT,
    loan_duration   TEXT,
    fine_level      TEXT,
    age_protect     TEXT,
    mint_condition  TEXT,
	CONSTRAINT vand_import_item_attr_def_idx UNIQUE (owner,name)
);

CREATE TABLE vandelay.import_error (
    code        TEXT    PRIMARY KEY,
    description TEXT    NOT NULL -- i18n
);

CREATE TYPE vandelay.bib_queue_queue_type AS ENUM ('bib', 'acq');

CREATE TABLE vandelay.bib_queue (
	queue_type	    vandelay.bib_queue_queue_type	NOT NULL DEFAULT 'bib',
	item_attr_def	BIGINT REFERENCES vandelay.import_item_attr_definition (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    match_bucket    INTEGER, -- REFERENCES container.biblio_record_entry_bucket(id);
	CONSTRAINT vand_bib_queue_name_once_per_owner_const UNIQUE (owner,name,queue_type)
) INHERITS (vandelay.queue);
ALTER TABLE vandelay.bib_queue ADD PRIMARY KEY (id);

CREATE TABLE vandelay.queued_bib_record (
	queue		    INT		NOT NULL REFERENCES vandelay.bib_queue (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	bib_source	    INT		REFERENCES config.bib_source (id) DEFERRABLE INITIALLY DEFERRED,
	imported_as 	BIGINT	REFERENCES biblio.record_entry (id) DEFERRABLE INITIALLY DEFERRED,
	import_error	TEXT    REFERENCES vandelay.import_error (code) ON DELETE SET NULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
	error_detail	TEXT
) INHERITS (vandelay.queued_record);
ALTER TABLE vandelay.queued_bib_record ADD PRIMARY KEY (id);
CREATE INDEX queued_bib_record_queue_idx ON vandelay.queued_bib_record (queue);

CREATE TABLE vandelay.queued_bib_record_attr (
	id			BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL REFERENCES vandelay.queued_bib_record (id) DEFERRABLE INITIALLY DEFERRED,
	field		INT			NOT NULL REFERENCES vandelay.bib_attr_definition (id) DEFERRABLE INITIALLY DEFERRED,
	attr_value	TEXT		NOT NULL
);
CREATE INDEX queued_bib_record_attr_record_idx ON vandelay.queued_bib_record_attr (record);

CREATE TABLE vandelay.bib_match (
	id				BIGSERIAL	PRIMARY KEY,
	queued_record	BIGINT		REFERENCES vandelay.queued_bib_record (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	eg_record		BIGINT		REFERENCES biblio.record_entry (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    quality         INT         NOT NULL DEFAULT 1,
    match_score     INT         NOT NULL DEFAULT 0
);
CREATE INDEX bib_match_queued_record_idx ON vandelay.bib_match (queued_record);

CREATE TABLE vandelay.import_item (
    id              BIGSERIAL   PRIMARY KEY,
    record          BIGINT      NOT NULL REFERENCES vandelay.queued_bib_record (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    definition      BIGINT      NOT NULL REFERENCES vandelay.import_item_attr_definition (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	import_error	TEXT        REFERENCES vandelay.import_error (code) ON DELETE SET NULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
	error_detail	TEXT,
    imported_as     BIGINT,
    import_time	    TIMESTAMP WITH TIME ZONE,
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
    stat_cat_data   TEXT,
    parts_data      TEXT,
    opac_visible    BOOL,
    floating        INT,
    loan_duration   INT,
    fine_level      INT,
    age_protect     INT,
    mint_condition  BOOL,
    internal_id     BIGINT -- queue_type == 'acq' ? acq.lineitem_detail.id : asset.copy.id
);
CREATE INDEX import_item_record_idx ON vandelay.import_item (record);

CREATE TABLE vandelay.import_bib_trash_group(
    id           SERIAL  PRIMARY KEY,
    owner        INTEGER NOT NULL REFERENCES actor.org_unit(id),
    label        TEXT    NOT NULL, --i18n
    always_apply BOOLEAN NOT NULL DEFAULT FALSE,
	CONSTRAINT vand_import_bib_trash_grp_owner_label UNIQUE (owner, label)
);
 
CREATE TABLE vandelay.import_bib_trash_fields (
    id         BIGSERIAL PRIMARY KEY,
    grp        INTEGER   NOT NULL REFERENCES vandelay.import_bib_trash_group,
    field      TEXT      NOT NULL,
    CONSTRAINT vand_import_bib_trash_fields_once_per UNIQUE (grp, field)
);

CREATE TABLE vandelay.merge_profile (
    id              BIGSERIAL   PRIMARY KEY,
    owner           INT         NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT        NOT NULL,
    add_spec        TEXT,
    replace_spec    TEXT,
    strip_spec      TEXT,
    preserve_spec   TEXT,
    update_bib_source BOOLEAN	NOT NULL DEFAULT FALSE,
    update_bib_editor BOOLEAN	NOT NULL DEFAULT FALSE,
    lwm_ratio       NUMERIC,
	CONSTRAINT vand_merge_prof_owner_name_idx UNIQUE (owner,name),
	CONSTRAINT add_replace_strip_or_preserve CHECK ((preserve_spec IS NOT NULL OR replace_spec IS NOT NULL) OR (preserve_spec IS NULL AND replace_spec IS NULL))
);

CREATE OR REPLACE FUNCTION vandelay.marc21_record_type( marc TEXT ) RETURNS config.marc21_rec_type_map AS $func$
DECLARE
        ldr         TEXT;
        tval        TEXT;
        tval_rec    RECORD;
        bval        TEXT;
        bval_rec    RECORD;
    retval      config.marc21_rec_type_map%ROWTYPE;
BEGIN
    ldr := oils_xpath_string( '//*[local-name()="leader"]', marc );

    IF ldr IS NULL OR ldr = '' THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
        RETURN retval;
    END IF;

    SELECT * INTO tval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'Type' LIMIT 1; -- They're all the same
    SELECT * INTO bval_rec FROM config.marc21_ff_pos_map WHERE fixed_field = 'BLvl' LIMIT 1; -- They're all the same


    tval := SUBSTRING( ldr, tval_rec.start_pos + 1, tval_rec.length );
    bval := SUBSTRING( ldr, bval_rec.start_pos + 1, bval_rec.length );

    -- RAISE NOTICE 'type %, blvl %, ldr %', tval, bval, ldr;

    SELECT * INTO retval FROM config.marc21_rec_type_map WHERE type_val LIKE '%' || tval || '%' AND blvl_val LIKE '%' || bval || '%';


    IF retval.code IS NULL THEN
        SELECT * INTO retval FROM config.marc21_rec_type_map WHERE code = 'BKS';
    END IF;

    RETURN retval;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TYPE biblio.record_ff_map AS (record BIGINT, ff_name TEXT, ff_value TEXT);
CREATE OR REPLACE FUNCTION vandelay.marc21_extract_all_fixed_fields( marc TEXT, use_default BOOL DEFAULT FALSE ) RETURNS SETOF biblio.record_ff_map AS $func$
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
                CONTINUE WHEN output.ff_value IS NULL AND NOT use_default;
                IF output.ff_value IS NULL THEN output.ff_value := REPEAT( ff_pos.default_val, ff_pos.length ); END IF;
                RETURN NEXT output;
                output.ff_value := NULL;
            END LOOP;
        END IF;

    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.marc21_extract_fixed_field_list( marc TEXT, ff TEXT, use_default BOOL DEFAULT FALSE ) RETURNS TEXT[] AS $func$
DECLARE
    rtype       TEXT;
    ff_pos      RECORD;
    tag_data    RECORD;
    val         TEXT;
    collection  TEXT[] := '{}'::TEXT[];
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;
    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = ff AND rec_type = rtype ORDER BY tag DESC LOOP
        IF ff_pos.tag = 'ldr' THEN
            val := oils_xpath_string('//*[local-name()="leader"]', marc);
            IF val IS NOT NULL THEN
                val := SUBSTRING( val, ff_pos.start_pos + 1, ff_pos.length );
                collection := collection || val;
            END IF;
        ELSE
            FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(ff_pos.tag) || '"]/text()', marc ) ) x(value) LOOP
                val := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
                collection := collection || val;
            END LOOP;
        END IF;
        CONTINUE WHEN NOT use_default;
        CONTINUE WHEN ARRAY_UPPER(collection, 1) > 0;
        val := REPEAT( ff_pos.default_val, ff_pos.length );
        collection := collection || val;
    END LOOP;

    RETURN collection;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.marc21_extract_fixed_field( marc TEXT, ff TEXT, use_default BOOL DEFAULT FALSE ) RETURNS TEXT AS $func$
DECLARE
    rtype       TEXT;
    ff_pos      RECORD;
    tag_data    RECORD;
    val         TEXT;
BEGIN
    rtype := (vandelay.marc21_record_type( marc )).code;
    FOR ff_pos IN SELECT * FROM config.marc21_ff_pos_map WHERE fixed_field = ff AND rec_type = rtype ORDER BY tag DESC LOOP
        IF ff_pos.tag = 'ldr' THEN
            val := oils_xpath_string('//*[local-name()="leader"]', marc);
            IF val IS NOT NULL THEN
                val := SUBSTRING( val, ff_pos.start_pos + 1, ff_pos.length );
                RETURN val;
            END IF;
        ELSE
            FOR tag_data IN SELECT value FROM UNNEST( oils_xpath( '//*[@tag="' || UPPER(ff_pos.tag) || '"]/text()', marc ) ) x(value) LOOP
                val := SUBSTRING( tag_data.value, ff_pos.start_pos + 1, ff_pos.length );
                RETURN val;
            END LOOP;
        END IF;
        CONTINUE WHEN NOT use_default;
        val := REPEAT( ff_pos.default_val, ff_pos.length );
        RETURN val;
    END LOOP;

    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TYPE biblio.marc21_physical_characteristics AS ( id INT, record BIGINT, ptype TEXT, subfield INT, value INT );
CREATE OR REPLACE FUNCTION vandelay.marc21_physical_characteristics( marc TEXT) RETURNS SETOF biblio.marc21_physical_characteristics AS $func$
DECLARE
    rowid   INT := 0;
    _007    TEXT;
    ptype   config.marc21_physical_characteristic_type_map%ROWTYPE;
    psf     config.marc21_physical_characteristic_subfield_map%ROWTYPE;
    pval    config.marc21_physical_characteristic_value_map%ROWTYPE;
    retval  biblio.marc21_physical_characteristics%ROWTYPE;
BEGIN

    FOR _007 IN SELECT oils_xpath_string('//*', value) FROM UNNEST(oils_xpath('//*[@tag="007"]', marc)) x(value) LOOP
        IF _007 IS NOT NULL AND _007 <> '' THEN
            SELECT * INTO ptype FROM config.marc21_physical_characteristic_type_map WHERE ptype_key = SUBSTRING( _007, 1, 1 );

            IF ptype.ptype_key IS NOT NULL THEN
                FOR psf IN SELECT * FROM config.marc21_physical_characteristic_subfield_map WHERE ptype_key = ptype.ptype_key LOOP
                    SELECT * INTO pval FROM config.marc21_physical_characteristic_value_map WHERE ptype_subfield = psf.id AND value = SUBSTRING( _007, psf.start_pos + 1, psf.length );

                    IF pval.id IS NOT NULL THEN
                        rowid := rowid + 1;
                        retval.id := rowid;
                        retval.ptype := ptype.ptype_key;
                        retval.subfield := psf.id;
                        retval.value := pval.id;
                        RETURN NEXT retval;
                    END IF;

                END LOOP;
            END IF;
        END IF;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TYPE vandelay.flat_marc AS ( tag CHAR(3), ind1 TEXT, ind2 TEXT, subfield TEXT, value TEXT );
CREATE OR REPLACE FUNCTION vandelay.flay_marc ( TEXT ) RETURNS SETOF vandelay.flat_marc AS $func$

use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use strict;

MARC::Charset->assume_unicode(1);

my $xml = shift;
my $r = MARC::Record->new_from_xml( $xml );

return_next( { tag => 'LDR', value => $r->leader } );

for my $f ( $r->fields ) {
    if ($f->is_control_field) {
        return_next({ tag => $f->tag, value => $f->data });
    } else {
        for my $s ($f->subfields) {
            return_next({
                tag      => $f->tag,
                ind1     => $f->indicator(1),
                ind2     => $f->indicator(2),
                subfield => $s->[0],
                value    => $s->[1]
            });

            if ( $f->tag eq '245' and $s->[0] eq 'a' ) {
                my $trim = $f->indicator(2) || 0;
                return_next({
                    tag      => 'tnf',
                    ind1     => $f->indicator(1),
                    ind2     => $f->indicator(2),
                    subfield => 'a',
                    value    => substr( $s->[1], $trim )
                });
            }
        }
    }
}

return undef;

$func$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.flatten_marc ( marc TEXT ) RETURNS SETOF vandelay.flat_marc AS $func$
DECLARE
    output  vandelay.flat_marc%ROWTYPE;
    field   RECORD;
BEGIN
    FOR field IN SELECT * FROM vandelay.flay_marc( marc ) LOOP
        output.ind1 := field.ind1;
        output.ind2 := field.ind2;
        output.tag := field.tag;
        output.subfield := field.subfield;
        IF field.subfield IS NOT NULL AND field.tag NOT IN ('020','022','024') THEN -- exclude standard numbers and control fields
            output.value := naco_normalize(field.value, field.subfield);
        ELSE
            output.value := field.value;
        END IF;

        CONTINUE WHEN output.value IS NULL;

        RETURN NEXT output;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.extract_rec_attrs ( xml TEXT, attr_defs TEXT[]) RETURNS hstore AS $_$
DECLARE
    transformed_xml TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_value      TEXT;
    new_attrs       HSTORE := ''::HSTORE;
    attr_def        config.record_attr_definition%ROWTYPE;
BEGIN

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE name IN (SELECT * FROM UNNEST(attr_defs)) ORDER BY format LOOP

        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  STRING_AGG(x.value, COALESCE(attr_def.joiner,' ')) INTO attr_value
              FROM  vandelay.flatten_marc(xml) AS x
              WHERE x.tag LIKE attr_def.tag
                    AND CASE
                        WHEN attr_def.sf_list IS NOT NULL
                            THEN POSITION(x.subfield IN attr_def.sf_list) > 0
                        ELSE TRUE
                        END
              GROUP BY x.tag
              ORDER BY x.tag
              LIMIT 1;

        ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
            attr_value := vandelay.marc21_extract_fixed_field(xml, attr_def.fixed_field);

        ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;

            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(xml,xfrm.xslt);
                ELSE
                    transformed_xml := xml;
                END IF;

                prev_xfrm := xfrm.name;
            END IF;

            IF xfrm.name IS NULL THEN
                -- just grab the marcxml (empty) transform
                SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                prev_xfrm := xfrm.name;
            END IF;

            attr_value := oils_xpath_string(attr_def.xpath, transformed_xml, COALESCE(attr_def.joiner,' '), ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]);

        ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
            SELECT  m.value::TEXT INTO attr_value
              FROM  vandelay.marc21_physical_characteristics(xml) v
                    JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
              WHERE v.subfield = attr_def.phys_char_sf
              LIMIT 1; -- Just in case ...

        END IF;

        -- apply index normalizers to attr_value
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
              WHERE attr = attr_def.name
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_nullable( attr_value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO attr_value;

        END LOOP;

        -- Add the new value to the hstore
        new_attrs := new_attrs || hstore( attr_def.name, attr_value );

    END LOOP;

    RETURN new_attrs;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.extract_rec_attrs ( xml TEXT ) RETURNS hstore AS $_$
    SELECT vandelay.extract_rec_attrs( $1, (SELECT ARRAY_AGG(name) FROM config.record_attr_definition));
$_$ LANGUAGE SQL;

-- Everything between this comment and the beginning of the definition of
-- vandelay.match_bib_record() is strictly in service of that function.
CREATE TYPE vandelay.match_set_test_result AS (record BIGINT, quality INTEGER);

CREATE OR REPLACE FUNCTION vandelay.match_set_test_marcxml(
    match_set_id INTEGER, record_xml TEXT, bucket_id INTEGER 
) RETURNS SETOF vandelay.match_set_test_result AS $$
DECLARE
    tags_rstore HSTORE;
    svf_rstore  HSTORE;
    coal        TEXT;
    joins       TEXT;
    query_      TEXT;
    wq          TEXT;
    qvalue      INTEGER;
    rec         RECORD;
BEGIN
    tags_rstore := vandelay.flatten_marc_hstore(record_xml);
    svf_rstore := vandelay.extract_rec_attrs(record_xml);

    CREATE TEMPORARY TABLE _vandelay_tmp_qrows (q INTEGER);
    CREATE TEMPORARY TABLE _vandelay_tmp_jrows (j TEXT);

    -- generate the where clause and return that directly (into wq), and as
    -- a side-effect, populate the _vandelay_tmp_[qj]rows tables.
    wq := vandelay.get_expr_from_match_set(match_set_id, tags_rstore);

    query_ := 'SELECT DISTINCT(record), ';

    -- qrows table is for the quality bits we add to the SELECT clause
    SELECT STRING_AGG(
        'COALESCE(n' || q::TEXT || '.quality, 0)', ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT STRING_AGG(j, E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n';

    -- join the record bucket
    IF bucket_id IS NOT NULL THEN
        query_ := query_ || 'JOIN container.biblio_record_entry_bucket_item ' ||
            'brebi ON (brebi.target_biblio_record_entry = record ' ||
            'AND brebi.bucket = ' || bucket_id || E')\n';
    END IF;

    query_ := query_ || 'JOIN biblio.record_entry bre ON (bre.id = record) ' || 'WHERE ' || wq || ' AND not bre.deleted';

    -- this will return rows of record,quality
    FOR rec IN EXECUTE query_ USING tags_rstore, svf_rstore LOOP
        RETURN NEXT rec;
    END LOOP;

    DROP TABLE _vandelay_tmp_qrows;
    DROP TABLE _vandelay_tmp_jrows;
    RETURN;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION vandelay.flatten_marc_hstore(
    record_xml TEXT
) RETURNS HSTORE AS $func$
BEGIN
    RETURN (SELECT
        HSTORE(
            ARRAY_AGG(tag || (COALESCE(subfield, ''))),
            ARRAY_AGG(value)
        )
        FROM (
            SELECT  tag, subfield, ARRAY_AGG(value)::TEXT AS value
              FROM  (SELECT tag,
                            subfield,
                            CASE WHEN tag = '020' THEN -- caseless -- isbn
                                LOWER((SELECT REGEXP_MATCHES(value,$$^(\S{10,17})$$))[1] || '%')
                            WHEN tag = '022' THEN -- caseless -- issn
                                LOWER((SELECT REGEXP_MATCHES(value,$$^(\S{4}[- ]?\S{4})$$))[1] || '%')
                            WHEN tag = '024' THEN -- caseless -- upc (other)
                                LOWER(value || '%')
                            ELSE
                                value
                            END AS value
                      FROM  vandelay.flatten_marc(record_xml)) x
                GROUP BY tag, subfield ORDER BY tag, subfield
        ) subquery
    );
END;
$func$ LANGUAGE PLPGSQL;

-- backwards compat version so we don't have 
-- to modify vandelay.match_set_test_marcxml()
CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set(
    match_set_id INTEGER,
    tags_rstore HSTORE
) RETURNS TEXT AS $$
BEGIN
    RETURN vandelay.get_expr_from_match_set(
        match_set_id, tags_rstore, NULL);
END;
$$  LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set(
    match_set_id INTEGER,
    tags_rstore HSTORE,
    auth_heading TEXT
) RETURNS TEXT AS $$
DECLARE
    root vandelay.match_set_point;
BEGIN
    SELECT * INTO root FROM vandelay.match_set_point
        WHERE parent IS NULL AND match_set = match_set_id;

    RETURN vandelay.get_expr_from_match_set_point(
        root, tags_rstore, auth_heading);
END;
$$  LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set_point(
    node vandelay.match_set_point,
    tags_rstore HSTORE,
    auth_heading TEXT
) RETURNS TEXT AS $$
DECLARE
    q           TEXT;
    i           INTEGER;
    this_op     TEXT;
    children    INTEGER[];
    child       vandelay.match_set_point;
BEGIN
    SELECT ARRAY_AGG(id) INTO children FROM vandelay.match_set_point
        WHERE parent = node.id;

    IF ARRAY_LENGTH(children, 1) > 0 THEN
        this_op := vandelay._get_expr_render_one(node);
        q := '(';
        i := 1;
        WHILE children[i] IS NOT NULL LOOP
            SELECT * INTO child FROM vandelay.match_set_point
                WHERE id = children[i];
            IF i > 1 THEN
                q := q || ' ' || this_op || ' ';
            END IF;
            i := i + 1;
            q := q || vandelay.get_expr_from_match_set_point(
                child, tags_rstore, auth_heading);
        END LOOP;
        q := q || ')';
        RETURN q;
    ELSIF node.bool_op IS NULL THEN
        PERFORM vandelay._get_expr_push_qrow(node);
        PERFORM vandelay._get_expr_push_jrow(node, tags_rstore, auth_heading);
        RETURN vandelay._get_expr_render_one(node);
    ELSE
        RETURN '';
    END IF;
END;
$$  LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_qrow(
    node vandelay.match_set_point
) RETURNS VOID AS $$
DECLARE
BEGIN
    INSERT INTO _vandelay_tmp_qrows (q) VALUES (node.id);
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point,
    tags_rstore HSTORE,
    auth_heading TEXT
) RETURNS VOID AS $$
DECLARE
    jrow        TEXT;
    my_alias    TEXT;
    op          TEXT;
    tagkey      TEXT;
    caseless    BOOL;
    jrow_count  INT;
    my_using    TEXT;
    my_join     TEXT;
    rec_table   TEXT;
BEGIN
    -- remember $1 is tags_rstore, and $2 is svf_rstore
    -- a non-NULL auth_heading means we're matching authority records

    IF auth_heading IS NOT NULL THEN
        rec_table := 'authority.full_rec';
    ELSE
        rec_table := 'metabib.full_rec';
    END IF;

    caseless := FALSE;
    SELECT COUNT(*) INTO jrow_count FROM _vandelay_tmp_jrows;
    IF jrow_count > 0 THEN
        my_using := ' USING (record)';
        my_join := 'FULL OUTER JOIN';
    ELSE
        my_using := '';
        my_join := 'FROM';
    END IF;

    IF node.tag IS NOT NULL THEN
        caseless := (node.tag IN ('020', '022', '024'));
        tagkey := node.tag;
        IF node.subfield IS NOT NULL THEN
            tagkey := tagkey || node.subfield;
        END IF;
    END IF;

    IF node.negate THEN
        IF caseless THEN
            op := 'NOT LIKE';
        ELSE
            op := '<>';
        END IF;
    ELSE
        IF caseless THEN
            op := 'LIKE';
        ELSE
            op := '=';
        END IF;
    END IF;

    my_alias := 'n' || node.id::TEXT;

    jrow := my_join || ' (SELECT *, ';
    IF node.tag IS NOT NULL THEN
        jrow := jrow  || node.quality ||
            ' AS quality FROM ' || rec_table || ' mfr WHERE mfr.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND mfr.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (';
        jrow := jrow || vandelay._node_tag_comparisons(caseless, op, tags_rstore, tagkey);
        jrow := jrow || ')) ' || my_alias || my_using || E'\n';
    ELSE    -- svf
        IF auth_heading IS NOT NULL THEN -- authority record
            IF node.heading AND auth_heading <> '' THEN
                jrow := jrow || 'id AS record, ' || node.quality ||
                ' AS quality FROM authority.record_entry are ' ||
                ' WHERE are.heading = ''' || auth_heading || '''';
                jrow := jrow || ') ' || my_alias || my_using || E'\n';
            END IF;
        ELSE -- bib record
            jrow := jrow || 'id AS record, ' || node.quality ||
                ' AS quality FROM metabib.record_attr_flat mraf WHERE mraf.attr = ''' ||
                node.svf || ''' AND mraf.value ' || op || ' $2->''' || node.svf || ''') ' ||
                my_alias || my_using || E'\n';
        END IF;
    END IF;
    INSERT INTO _vandelay_tmp_jrows (j) VALUES (jrow);
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._node_tag_comparisons(
    caseless BOOLEAN,
    op TEXT,
    tags_rstore HSTORE,
    tagkey TEXT
) RETURNS TEXT AS $$
DECLARE
    result  TEXT;
    i       INT;
    vals    TEXT[];
BEGIN
    i := 1;
    vals := tags_rstore->tagkey;
    result := '';

    WHILE TRUE LOOP
        IF i > 1 THEN
            IF vals[i] IS NULL THEN
                EXIT;
            ELSE
                result := result || ' OR ';
            END IF;
        END IF;

        IF caseless THEN
            result := result || 'LOWER(mfr.value) ' || op;
        ELSE
            result := result || 'mfr.value ' || op;
        END IF;

        result := result || ' ' || COALESCE('''' || vals[i] || '''', 'NULL');

        IF vals[i] IS NULL THEN
            EXIT;
        END IF;
        i := i + 1;
    END LOOP;

    RETURN result;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_render_one(
    node vandelay.match_set_point
) RETURNS TEXT AS $$
DECLARE
    s           TEXT;
BEGIN
    IF node.bool_op IS NOT NULL THEN
        RETURN node.bool_op;
    ELSE
        RETURN '(n' || node.id::TEXT || '.id IS NOT NULL)';
    END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.match_bib_record() RETURNS TRIGGER AS $func$
DECLARE
    incoming_existing_id    TEXT;
    test_result             vandelay.match_set_test_result%ROWTYPE;
    tmp_rec                 BIGINT;
    match_set               INT;
    match_bucket            INT;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    DELETE FROM vandelay.bib_match WHERE queued_record = NEW.id;

    SELECT q.match_set INTO match_set FROM vandelay.bib_queue q WHERE q.id = NEW.queue;

    IF match_set IS NOT NULL THEN
        NEW.quality := vandelay.measure_record_quality( NEW.marc, match_set );
    END IF;

    -- Perfect matches on 901$c exit early with a match with high quality.
    incoming_existing_id :=
        oils_xpath_string('//*[@tag="901"]/*[@code="c"][1]', NEW.marc);

    IF incoming_existing_id IS NOT NULL AND incoming_existing_id != '' THEN
        SELECT id INTO tmp_rec FROM biblio.record_entry WHERE id = incoming_existing_id::bigint;
        IF tmp_rec IS NOT NULL THEN
            INSERT INTO vandelay.bib_match (queued_record, eg_record, match_score, quality) 
                SELECT
                    NEW.id, 
                    b.id,
                    9999,
                    -- note: no match_set means quality==0
                    vandelay.measure_record_quality( b.marc, match_set )
                FROM biblio.record_entry b
                WHERE id = incoming_existing_id::bigint;
        END IF;
    END IF;

    IF match_set IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT q.match_bucket INTO match_bucket FROM vandelay.bib_queue q WHERE q.id = NEW.queue;

    FOR test_result IN SELECT * FROM
        vandelay.match_set_test_marcxml(match_set, NEW.marc, match_bucket) LOOP

        INSERT INTO vandelay.bib_match ( queued_record, eg_record, match_score, quality )
            SELECT  
                NEW.id,
                test_result.record,
                test_result.quality,
                vandelay.measure_record_quality( b.marc, match_set )
	        FROM  biblio.record_entry b
	        WHERE id = test_result.record;

    END LOOP;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.measure_record_quality ( xml TEXT, match_set_id INT ) RETURNS INT AS $_$
DECLARE
    out_q   INT := 0;
    rvalue  TEXT;
    test    vandelay.match_set_quality%ROWTYPE;
BEGIN

    FOR test IN SELECT * FROM vandelay.match_set_quality WHERE match_set = match_set_id LOOP
        IF test.tag IS NOT NULL THEN
            FOR rvalue IN SELECT value FROM vandelay.flatten_marc( xml ) WHERE tag = test.tag AND subfield = test.subfield LOOP
                IF test.value = rvalue THEN
                    out_q := out_q + test.quality;
                END IF;
            END LOOP;
        ELSE
            IF test.value = vandelay.extract_rec_attrs(xml, ARRAY[test.svf]) -> test.svf THEN
                out_q := out_q + test.quality;
            END IF;
        END IF;
    END LOOP;

    RETURN out_q;
END;
$_$ LANGUAGE PLPGSQL;

CREATE TYPE vandelay.tcn_data AS (tcn TEXT, tcn_source TEXT, used BOOL);
CREATE OR REPLACE FUNCTION vandelay.find_bib_tcn_data ( xml TEXT ) RETURNS SETOF vandelay.tcn_data AS $_$
DECLARE
    eg_tcn          TEXT;
    eg_tcn_source   TEXT;
    output          vandelay.tcn_data%ROWTYPE;
BEGIN

    -- 001/003
    eg_tcn := BTRIM((oils_xpath('//*[@tag="001"]/text()',xml))[1]);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := BTRIM((oils_xpath('//*[@tag="003"]/text()',xml))[1]);
        IF eg_tcn_source IS NULL OR eg_tcn_source = '' THEN
            eg_tcn_source := 'System Local';
        END IF;

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 901 ab
    eg_tcn := BTRIM((oils_xpath('//*[@tag="901"]/*[@code="a"]/text()',xml))[1]);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := BTRIM((oils_xpath('//*[@tag="901"]/*[@code="b"]/text()',xml))[1]);
        IF eg_tcn_source IS NULL OR eg_tcn_source = '' THEN
            eg_tcn_source := 'System Local';
        END IF;

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 039 ab
    eg_tcn := BTRIM((oils_xpath('//*[@tag="039"]/*[@code="a"]/text()',xml))[1]);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := BTRIM((oils_xpath('//*[@tag="039"]/*[@code="b"]/text()',xml))[1]);
        IF eg_tcn_source IS NULL OR eg_tcn_source = '' THEN
            eg_tcn_source := 'System Local';
        END IF;

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 020 a
    eg_tcn := REGEXP_REPLACE((oils_xpath('//*[@tag="020"]/*[@code="a"]/text()',xml))[1], $re$^(\w+).*?$$re$, $re$\1$re$);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := 'ISBN';

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 022 a
    eg_tcn := REGEXP_REPLACE((oils_xpath('//*[@tag="022"]/*[@code="a"]/text()',xml))[1], $re$^(\w+).*?$$re$, $re$\1$re$);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := 'ISSN';

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 010 a
    eg_tcn := REGEXP_REPLACE((oils_xpath('//*[@tag="010"]/*[@code="a"]/text()',xml))[1], $re$^(\w+).*?$$re$, $re$\1$re$);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := 'LCCN';

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    -- 035 a
    eg_tcn := REGEXP_REPLACE((oils_xpath('//*[@tag="035"]/*[@code="a"]/text()',xml))[1], $re$^.*?(\w+)$$re$, $re$\1$re$);
    IF eg_tcn IS NOT NULL AND eg_tcn <> '' THEN

        eg_tcn_source := 'System Legacy';

        PERFORM id FROM biblio.record_entry WHERE tcn_value = eg_tcn  AND NOT deleted;

        IF NOT FOUND THEN
            output.used := FALSE;
        ELSE
            output.used := TRUE;
        END IF;

        output.tcn := eg_tcn;
        output.tcn_source := eg_tcn_source;
        RETURN NEXT output;

    END IF;

    RETURN;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT, force_add INT ) RETURNS TEXT AS $_$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;
    use strict;

    MARC::Charset->assume_unicode(1);

    my $target_xml = shift;
    my $source_xml = shift;
    my $field_spec = shift;
    my $force_add = shift || 0;

    my $target_r = MARC::Record->new_from_xml( $target_xml );
    my $source_r = MARC::Record->new_from_xml( $source_xml );

    return $target_xml unless ($target_r && $source_r);

    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $matches = $3;
            $matches =~ s/^\s*//; $matches =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($matches) {
                for my $match (split('&&', $matches)) {
                    $match =~ s/^\s*//; $match =~ s/\s*$//;
                    my ($msf,$mre) = split('~', $match);
                    if (length($msf) > 0 and length($mre) > 0) {
                        $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                        $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                        $fields{$field}{match}{$msf} = qr/$mre/;
                    }
                }
            }
        }
    }

    for my $f ( keys %fields) {
        if ( @{$fields{$f}{sf}} ) {
            for my $from_field ($source_r->field( $f )) {
                my @tos = $target_r->field( $f );
                if (!@tos) {
                    next if (exists($fields{$f}{match}) and !$force_add);
                    my @new_fields = map { $_->clone } $source_r->field( $f );
                    $target_r->insert_fields_ordered( @new_fields );
                } else {
                    for my $to_field (@tos) {
                        if (exists($fields{$f}{match})) {
                            my @match_list;
                            for my $match_key_sf_code ( keys %{$fields{$f}{match}} ) {
                                # We loop here because there might be multiple SFs, such as multiple
                                # $0s in an authority controlled datafield, where one has the EG-special
                                # format, and others are links to external heading data.
                                for my $sf_content ($to_field->subfield($match_key_sf_code)) {
                                    if ($sf_content =~ $fields{$f}{match}{$match_key_sf_code}) {
                                        push @match_list, $sf_content;
                                    }
                                }
                            }
                            next unless (scalar(@match_list) >= scalar(keys %{$fields{$f}{match}}));
                        }
                        for my $old_sf ($from_field->subfields) {
                            $to_field->add_subfields( @$old_sf ) if grep(/$$old_sf[0]/,@{$fields{$f}{sf}});
                        }
                    }
                }
            }
        } else {
            my @new_fields = map { $_->clone } $source_r->field( $f );
            $target_r->insert_fields_ordered( @new_fields );
        }
    }

    $target_xml = $target_r->as_xml_record;
    $target_xml =~ s/^<\?.+?\?>$//mo;
    $target_xml =~ s/\n//sgo;
    $target_xml =~ s/>\s+</></sgo;

    return $target_xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.add_field ( target_xml TEXT, source_xml TEXT, field TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.add_field( $1, $2, $3, 0 );
$_$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION vandelay.strip_field(xml text, field text) RETURNS text AS $f$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;
    use strict;

    MARC::Charset->assume_unicode(1);

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return $xml unless ($r);

    my $field_spec = shift;
    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $matches = $3;
            $matches =~ s/^\s*//; $matches =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($matches) {
                for my $match (split('&&', $matches)) {
                    $match =~ s/^\s*//; $match =~ s/\s*$//;
                    my ($msf,$mre) = split('~', $match);
                    if (length($msf) > 0 and length($mre) > 0) {
                        $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                        $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                        $fields{$field}{match}{$msf} = qr/$mre/;
                    }
                }
            }
        }
    }

    for my $f ( keys %fields) {
        for my $to_field ($r->field( $f )) {
            if (exists($fields{$f}{match})) {
                my @match_list;
                for my $match_key_sf_code ( keys %{$fields{$f}{match}} ) {
                    # We loop here because there might be multiple SFs, such as multiple
                    # $0s in an authority controlled datafield, where one has the EG-special
                    # format, and others are links to external heading data.
                    for my $sf_content ($to_field->subfield($match_key_sf_code)) {
                        if ($sf_content =~ $fields{$f}{match}{$match_key_sf_code}) {
                            push @match_list, $sf_content;
                        }
                    }
                }
                next unless (scalar(@match_list) >= scalar(keys %{$fields{$f}{match}}));
            }

            if ( @{$fields{$f}{sf}} ) {
                $to_field->delete_subfield(code => $fields{$f}{sf});
            } else {
                $r->delete_field( $to_field );
            }
        }
    }

    $xml = $r->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$f$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION vandelay.replace_field 
    (target_xml TEXT, source_xml TEXT, field TEXT) RETURNS TEXT AS $_$

    use strict;
    use MARC::Record;
    use MARC::Field;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;

    MARC::Charset->assume_unicode(1);

    my $target_xml = shift;
    my $source_xml = shift;
    my $field_spec = shift;

    my $target_r = MARC::Record->new_from_xml($target_xml);
    my $source_r = MARC::Record->new_from_xml($source_xml);

    return $target_xml unless $target_r && $source_r;

    # Extract the field_spec components into MARC tags, subfields, 
    # and regex matches.  Copied wholesale from vandelay.strip_field()

    my @field_list = split(',', $field_spec);
    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $matches = $3;
            $matches =~ s/^\s*//; $matches =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($matches) {
                for my $match (split('&&', $matches)) {
                    $match =~ s/^\s*//; $match =~ s/\s*$//;
                    my ($msf,$mre) = split('~', $match);
                    if (length($msf) > 0 and length($mre) > 0) {
                        $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                        $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                        $fields{$field}{match}{$msf} = qr/$mre/;
                    }
                 }
            }
        }
    }

    # Returns a flat list of subfield (code, value, code, value, ...)
    # suitable for adding to a MARC::Field.
    sub generate_replacement_subfields {
        my ($source_field, $target_field, @controlled_subfields) = @_;

        # Performing a wholesale field replacment.  
        # Use the entire source field as-is.
        return map {$_->[0], $_->[1]} $source_field->subfields
            unless @controlled_subfields;

        my @new_subfields;

        # Iterate over all target field subfields:
        # 1. Keep uncontrolled subfields as is.
        # 2. Replace values for controlled subfields when a
        #    replacement value exists on the source record.
        # 3. Delete values for controlled subfields when no 
        #    replacement value exists on the source record.

        for my $target_sf ($target_field->subfields) {
            my $subfield = $target_sf->[0];
            my $target_val = $target_sf->[1];

            if (grep {$_ eq $subfield} @controlled_subfields) {
                if (my $source_val = $source_field->subfield($subfield)) {
                    # We have a replacement value
                    push(@new_subfields, $subfield, $source_val);
                } else {
                    # no replacement value for controlled subfield, drop it.
                }
            } else {
                # Field is not controlled.  Copy it over as-is.
                push(@new_subfields, $subfield, $target_val);
            }
        }

        # Iterate over all subfields in the source field and back-fill
        # any values that exist only in the source field.  Insert these
        # subfields in the same relative position they exist in the
        # source field.
                
        my @seen_subfields;
        for my $source_sf ($source_field->subfields) {
            my $subfield = $source_sf->[0];
            my $source_val = $source_sf->[1];
            push(@seen_subfields, $subfield);

            # target field already contains this subfield, 
            # so it would have been addressed above.
            next if $target_field->subfield($subfield);

            # Ignore uncontrolled subfields.
            next unless grep {$_ eq $subfield} @controlled_subfields;

            # Adding a new subfield.  Find its relative position and add
            # it to the list under construction.  Work backwards from
            # the list of already seen subfields to find the best slot.

            my $done = 0;
            for my $seen_sf (reverse(@seen_subfields)) {
                my $idx = @new_subfields;
                for my $new_sf (reverse(@new_subfields)) {
                    $idx--;
                    next if $idx % 2 == 1; # sf codes are in the even slots

                    if ($new_subfields[$idx] eq $seen_sf) {
                        splice(@new_subfields, $idx + 2, 0, $subfield, $source_val);
                        $done = 1;
                        last;
                    }
                }
                last if $done;
            }

            # if no slot was found, add to the end of the list.
            push(@new_subfields, $subfield, $source_val) unless $done;
        }

        return @new_subfields;
    }

    # MARC tag loop
    for my $f (keys %fields) {
        my $tag_idx = -1;
        my @target_fields = $target_r->field($f);

        if (!@target_fields and !defined($fields{$f}{match})) {
            # we will just add the source fields
            # unless they require a target match.
            my @add_these = map { $_->clone } $source_r->field($f);
            $target_r->insert_fields_ordered( @add_these );
        }

        for my $target_field (@target_fields) { # This will not run when the above "if" does.

            # field spec contains a regex for this field.  Confirm field on 
            # target record matches the specified regex before replacing.
            if (exists($fields{$f}{match})) {
                my @match_list;
                for my $match_key_sf_code ( keys %{$fields{$f}{match}} ) {
                    # We loop here because there might be multiple SFs, such as multiple
                    # $0s in an authority controlled datafield, where one has the EG-special
                    # format, and others are links to external heading data.
                    for my $sf_content ($target_field->subfield($match_key_sf_code)) {
                        if ($sf_content =~ $fields{$f}{match}{$match_key_sf_code}) {
                            push @match_list, $sf_content;
                        }
                    }
                }
                next unless (scalar(@match_list) >= scalar(keys %{$fields{$f}{match}}));
            }

            my @new_subfields;
            my @controlled_subfields = @{$fields{$f}{sf}};

            # If the target record has multiple matching bib fields,
            # replace them from matching fields on the source record
            # in a predictable order to avoid replacing with them with
            # same source field repeatedly.
            my @source_fields = $source_r->field($f);
            my $source_field = $source_fields[++$tag_idx];

            if (!$source_field && @controlled_subfields) {
                # When there are more target fields than source fields
                # and we are replacing values for subfields and not
                # performing wholesale field replacment, use the last
                # available source field as the input for all remaining
                # target fields.
                $source_field = $source_fields[$#source_fields];
            }

            if (!$source_field) {
                # No source field exists.  Delete all affected target
                # data.  This is a little bit counterintuitive, but is
                # backwards compatible with the previous version of this
                # function which first deleted all affected data, then
                # replaced values where possible.
                if (@controlled_subfields) {
                    $target_field->delete_subfield($_) for @controlled_subfields;
                } else {
                    $target_r->delete_field($target_field);
                }
                next;
            }

            my @new_subfields = generate_replacement_subfields(
                $source_field, $target_field, @controlled_subfields);

            # Build the replacement field from scratch.  
            my $replacement_field = MARC::Field->new(
                $target_field->tag,
                $target_field->indicator(1),
                $target_field->indicator(2),
                @new_subfields
            );

            $target_field->replace_with($replacement_field);
        }
    }

    $target_xml = $target_r->as_xml_record;
    $target_xml =~ s/^<\?.+?\?>$//mo;
    $target_xml =~ s/\n//sgo;
    $target_xml =~ s/>\s+</></sgo;

    return $target_xml;

$_$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION vandelay.merge_record_xml ( target_xml TEXT, source_xml TEXT, add_rule TEXT, replace_preserve_rule TEXT, strip_rule TEXT ) RETURNS TEXT AS $_$
    SELECT vandelay.replace_field( vandelay.add_field( vandelay.strip_field( $1, $5) , $2, $3 ), $2, $4);
$_$ LANGUAGE SQL;

CREATE TYPE vandelay.compile_profile AS (add_rule TEXT, replace_rule TEXT, preserve_rule TEXT, strip_rule TEXT);
CREATE OR REPLACE FUNCTION vandelay.compile_profile ( incoming_xml TEXT ) RETURNS vandelay.compile_profile AS $_$
DECLARE
    output              vandelay.compile_profile%ROWTYPE;
    profile             vandelay.merge_profile%ROWTYPE;
    profile_tmpl        TEXT;
    profile_tmpl_owner  TEXT;
    add_rule            TEXT := '';
    strip_rule          TEXT := '';
    replace_rule        TEXT := '';
    preserve_rule       TEXT := '';

BEGIN

    profile_tmpl := (oils_xpath('//*[@tag="905"]/*[@code="t"]/text()',incoming_xml))[1];
    profile_tmpl_owner := (oils_xpath('//*[@tag="905"]/*[@code="o"]/text()',incoming_xml))[1];

    IF profile_tmpl IS NOT NULL AND profile_tmpl <> '' AND profile_tmpl_owner IS NOT NULL AND profile_tmpl_owner <> '' THEN
        SELECT  p.* INTO profile
          FROM  vandelay.merge_profile p
                JOIN actor.org_unit u ON (u.id = p.owner)
          WHERE p.name = profile_tmpl
                AND u.shortname = profile_tmpl_owner;

        IF profile.id IS NOT NULL THEN
            add_rule := COALESCE(profile.add_spec,'');
            strip_rule := COALESCE(profile.strip_spec,'');
            replace_rule := COALESCE(profile.replace_spec,'');
            preserve_rule := COALESCE(profile.preserve_spec,'');
        END IF;
    END IF;

    add_rule := add_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="a"]/text()',incoming_xml),','),'');
    strip_rule := strip_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="d"]/text()',incoming_xml),','),'');
    replace_rule := replace_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="r"]/text()',incoming_xml),','),'');
    preserve_rule := preserve_rule || ',' || COALESCE(ARRAY_TO_STRING(oils_xpath('//*[@tag="905"]/*[@code="p"]/text()',incoming_xml),','),'');

    output.add_rule := BTRIM(add_rule,',');
    output.replace_rule := BTRIM(replace_rule,',');
    output.strip_rule := BTRIM(strip_rule,',');
    output.preserve_rule := BTRIM(preserve_rule,',');

    RETURN output;
END;
$_$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.template_overlay_bib_record ( v_marc TEXT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    editor_string   TEXT;
    editor_id       INT;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc         TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    SELECT  b.marc INTO eg_marc
      FROM  biblio.record_entry b
      WHERE b.id = eg_id
      LIMIT 1;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for template or bib record';
        RETURN FALSE;
    END IF;

    dyn_profile := vandelay.compile_profile( v_marc );

    IF merge_profile_id IS NOT NULL THEN
        SELECT * INTO merge_profile FROM vandelay.merge_profile WHERE id = merge_profile_id;
        IF FOUND THEN
            dyn_profile.add_rule := BTRIM( dyn_profile.add_rule || ',' || COALESCE(merge_profile.add_spec,''), ',');
            dyn_profile.strip_rule := BTRIM( dyn_profile.strip_rule || ',' || COALESCE(merge_profile.strip_spec,''), ',');
            dyn_profile.replace_rule := BTRIM( dyn_profile.replace_rule || ',' || COALESCE(merge_profile.replace_spec,''), ',');
            dyn_profile.preserve_rule := BTRIM( dyn_profile.preserve_rule || ',' || COALESCE(merge_profile.preserve_spec,''), ',');
        END IF;
    END IF;

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN FALSE;
    END IF;

    IF dyn_profile.replace_rule = '' AND dyn_profile.preserve_rule = '' AND dyn_profile.add_rule = '' AND dyn_profile.strip_rule = '' THEN
        --Since we have nothing to do, just return a NOOP "we did it"
        RETURN TRUE;
    ELSIF dyn_profile.replace_rule <> '' THEN
        source_marc = v_marc;
        target_marc = eg_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        source_marc = eg_marc;
        target_marc = v_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    UPDATE  biblio.record_entry
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule )
      WHERE id = eg_id;

    IF NOT FOUND THEN
        -- RAISE NOTICE 'update of biblio.record_entry failed';
        RETURN FALSE;
    END IF;

    RETURN TRUE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.merge_record_xml ( target_marc TEXT, template_marc TEXT ) RETURNS TEXT AS $$
DECLARE
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    replace_rule    TEXT;
    tmp_marc        TEXT;
    trgt_marc        TEXT;
    tmpl_marc        TEXT;
    match_count     INT;
BEGIN

    IF target_marc IS NULL OR template_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for target or template record';
        RETURN NULL;
    END IF;

    dyn_profile := vandelay.compile_profile( template_marc );

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN NULL;
    END IF;

    IF dyn_profile.replace_rule = '' AND dyn_profile.preserve_rule = '' AND dyn_profile.add_rule = '' AND dyn_profile.strip_rule = '' THEN
        --Since we have nothing to do, just return what we were given.
        RETURN target_marc;
    ELSIF dyn_profile.replace_rule <> '' THEN
        trgt_marc = target_marc;
        tmpl_marc = template_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        tmp_marc = target_marc;
        trgt_marc = template_marc;
        tmpl_marc = tmp_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    RETURN vandelay.merge_record_xml( trgt_marc, tmpl_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule );

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.merge_record_xml_using_profile ( incoming_marc TEXT, existing_marc TEXT, merge_profile_id BIGINT ) RETURNS TEXT AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    target_marc     TEXT;
    source_marc     TEXT;
    replace_rule    TEXT;
    match_count     INT;
BEGIN

    IF existing_marc IS NULL OR incoming_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for source or target records';
        RETURN NULL;
    END IF;

    IF merge_profile_id IS NOT NULL THEN
        SELECT * INTO merge_profile FROM vandelay.merge_profile WHERE id = merge_profile_id;
        IF FOUND THEN
            dyn_profile.add_rule := COALESCE(merge_profile.add_spec,'');
            dyn_profile.strip_rule := COALESCE(merge_profile.strip_spec,'');
            dyn_profile.replace_rule := COALESCE(merge_profile.replace_spec,'');
            dyn_profile.preserve_rule := COALESCE(merge_profile.preserve_spec,'');
        ELSE
            -- RAISE NOTICE 'merge profile not found';
            RETURN NULL;
        END IF;
    ELSE
        -- RAISE NOTICE 'no merge profile specified';
        RETURN NULL;
    END IF;

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN NULL;
    END IF;

    IF dyn_profile.replace_rule = '' AND dyn_profile.preserve_rule = '' AND dyn_profile.add_rule = '' AND dyn_profile.strip_rule = '' THEN
        -- Since we have nothing to do, just return a target record as is
        RETURN existing_marc;
    ELSIF dyn_profile.preserve_rule <> '' THEN
        source_marc = existing_marc;
        target_marc = incoming_marc;
        replace_rule = dyn_profile.preserve_rule;
    ELSE
        source_marc = incoming_marc;
        target_marc = existing_marc;
        replace_rule = dyn_profile.replace_rule;
    END IF;

    RETURN vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule );

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.template_overlay_bib_record ( v_marc TEXT, eg_id BIGINT) RETURNS BOOL AS $$
    SELECT vandelay.template_overlay_bib_record( $1, $2, NULL);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.overlay_bib_record 
    ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    editor_string   TEXT;
    editor_id       INT;
    v_marc          TEXT;
    v_bib_source    INT;
    update_fields   TEXT[];
    update_query    TEXT;
    update_bib_source BOOL;
    update_bib_editor BOOL;
BEGIN

    SELECT  q.marc, q.bib_source INTO v_marc, v_bib_source
      FROM  vandelay.queued_bib_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or bib record';
        RETURN FALSE;
    END IF;

    IF NOT vandelay.template_overlay_bib_record( v_marc, eg_id, merge_profile_id) THEN
        -- no update happened, get outta here.
        RETURN FALSE;
    END IF;

    UPDATE  vandelay.queued_bib_record
      SET   imported_as = eg_id,
            import_time = NOW()
      WHERE id = import_id;

    SELECT q.update_bib_source INTO update_bib_source 
        FROM vandelay.merge_profile q where q.id = merge_profile_Id;

    IF update_bib_source AND v_bib_source IS NOT NULL THEN
        update_fields := ARRAY_APPEND(update_fields, 'source = ' || v_bib_source);
    END IF;

    SELECT q.update_bib_editor INTO update_bib_editor 
        FROM vandelay.merge_profile q where q.id = merge_profile_Id;

    IF update_bib_editor THEN

        editor_string := (oils_xpath('//*[@tag="905"]/*[@code="u"]/text()',v_marc))[1];

        IF editor_string IS NOT NULL AND editor_string <> '' THEN
            SELECT usr INTO editor_id FROM actor.card WHERE barcode = editor_string;

            IF editor_id IS NULL THEN
                SELECT id INTO editor_id FROM actor.usr WHERE usrname = editor_string;
            END IF;

            IF editor_id IS NOT NULL THEN
                --only update the edit date if we have a valid editor
                update_fields := ARRAY_APPEND(
                    update_fields, 'editor = ' || editor_id || ', edit_date = NOW()');
            END IF;
        END IF;
    END IF;

    IF ARRAY_LENGTH(update_fields, 1) > 0 THEN
        update_query := 'UPDATE biblio.record_entry SET ' || 
            ARRAY_TO_STRING(update_fields, ',') || ' WHERE id = ' || eg_id || ';';
        EXECUTE update_query;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record_with_best ( import_id BIGINT, merge_profile_id INT, lwm_ratio_value_p NUMERIC ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    lwm_ratio_value NUMERIC;
BEGIN

    lwm_ratio_value := COALESCE(lwm_ratio_value_p, 0.0);

    PERFORM * FROM vandelay.queued_bib_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.bib_match m
            JOIN vandelay.queued_bib_record qr ON (m.queued_record = qr.id)
            JOIN vandelay.bib_queue q ON (qr.queue = q.id)
            JOIN biblio.record_entry r ON (r.id = m.eg_record)
      WHERE m.queued_record = import_id
            AND qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC >= lwm_ratio_value
      ORDER BY  m.match_score DESC, -- required match score
                qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC DESC, -- quality tie breaker
                m.id -- when in doubt, use the first match
      LIMIT 1;

    IF eg_id IS NULL THEN
        -- RAISE NOTICE 'incoming record is not of high enough quality';
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record_with_best ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
    SELECT vandelay.auto_overlay_bib_record_with_best( $1, $2, p.lwm_ratio ) FROM vandelay.merge_profile p WHERE id = $2;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
BEGIN

    PERFORM * FROM vandelay.queued_bib_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    SELECT COUNT(*) INTO match_count FROM vandelay.bib_match WHERE queued_record = import_id;

    IF match_count <> 1 THEN
        -- RAISE NOTICE 'not an exact match';
        RETURN FALSE;
    END IF;

    -- Check that the one match is on the first 901c
    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.queued_bib_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id)
      WHERE q.id = import_id
            AND m.eg_record = oils_xpath_string('//*[@tag="901"]/*[@code="c"][1]',marc)::BIGINT;

    IF NOT FOUND THEN
        -- RAISE NOTICE 'not a 901c match';
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue ( queue_id BIGINT, merge_profile_id INT ) RETURNS SETOF BIGINT AS $$
DECLARE
    queued_record   vandelay.queued_bib_record%ROWTYPE;
BEGIN

    FOR queued_record IN SELECT * FROM vandelay.queued_bib_record WHERE queue = queue_id AND import_time IS NULL LOOP

        IF vandelay.auto_overlay_bib_record( queued_record.id, merge_profile_id ) THEN
            RETURN NEXT queued_record.id;
        END IF;

    END LOOP;

    RETURN;
    
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue_with_best ( queue_id BIGINT, merge_profile_id INT, lwm_ratio_value NUMERIC ) RETURNS SETOF BIGINT AS $$
DECLARE
    queued_record   vandelay.queued_bib_record%ROWTYPE;
BEGIN

    FOR queued_record IN SELECT * FROM vandelay.queued_bib_record WHERE queue = queue_id AND import_time IS NULL LOOP

        IF vandelay.auto_overlay_bib_record_with_best( queued_record.id, merge_profile_id, lwm_ratio_value ) THEN
            RETURN NEXT queued_record.id;
        END IF;

    END LOOP;

    RETURN;
    
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue_with_best ( import_id BIGINT, merge_profile_id INT ) RETURNS SETOF BIGINT AS $$
    SELECT vandelay.auto_overlay_bib_queue_with_best( $1, $2, p.lwm_ratio ) FROM vandelay.merge_profile p WHERE id = $2;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_bib_queue ( queue_id BIGINT ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM vandelay.auto_overlay_bib_queue( $1, NULL );
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_org_unit_copies ( import_id BIGINT, merge_profile_id INT, lwm_ratio_value_p NUMERIC ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
    rec             vandelay.bib_match%ROWTYPE;
    v_owning_lib    INT;
    scope_org       INT;
    scope_orgs      INT[];
    copy_count      INT := 0;
    max_copy_count  INT := 0;
BEGIN

    PERFORM * FROM vandelay.queued_bib_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    -- Gather all the owning libs for our import items.
    -- These are our initial scope_orgs.
    SELECT ARRAY_AGG(DISTINCT owning_lib) INTO scope_orgs
        FROM vandelay.import_item
        WHERE record = import_id;

    WHILE CARDINALITY(scope_orgs) IS NOT NULL LOOP
        EXIT WHEN CARDINALITY(scope_orgs) = 0;
        FOR scope_org IN SELECT * FROM UNNEST(scope_orgs) LOOP
            -- For each match, get a count of all copies at descendants of our scope org.
            FOR rec IN SELECT * FROM vandelay.bib_match AS vbm
                WHERE queued_record = import_id
                ORDER BY vbm.eg_record DESC
            LOOP
                SELECT COUNT(acp.id) INTO copy_count
                    FROM asset.copy AS acp
                    INNER JOIN asset.call_number AS acn
                        ON acp.call_number = acn.id
                    WHERE acn.owning_lib IN (SELECT id FROM
                        actor.org_unit_descendants(scope_org))
                    AND acn.record = rec.eg_record
                    AND acp.deleted = FALSE;
                IF copy_count > max_copy_count THEN
                    max_copy_count := copy_count;
                    eg_id := rec.eg_record;
                END IF;
            END LOOP;
        END LOOP;

        EXIT WHEN eg_id IS NOT NULL;

        -- If no matching bibs had holdings, gather our next set of orgs to check, and iterate.
        IF max_copy_count = 0 THEN 
            SELECT ARRAY_AGG(DISTINCT parent_ou) INTO scope_orgs
                FROM actor.org_unit
                WHERE id IN (SELECT * FROM UNNEST(scope_orgs))
                AND parent_ou IS NOT NULL;
            EXIT WHEN CARDINALITY(scope_orgs) IS NULL;
        END IF;
    END LOOP;

    IF eg_id IS NULL THEN
        -- Could not determine best match via copy count
        -- fall back to default best match
        IF (SELECT * FROM vandelay.auto_overlay_bib_record_with_best( import_id, merge_profile_id, lwm_ratio_value_p )) THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    END IF;

    RETURN vandelay.overlay_bib_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.ingest_bib_marc ( ) RETURNS TRIGGER AS $$
DECLARE
    value   TEXT;
    atype   TEXT;
    adef    RECORD;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    FOR adef IN SELECT * FROM vandelay.bib_attr_definition LOOP

        SELECT extract_marc_field('vandelay.queued_bib_record', id, adef.xpath, adef.remove) INTO value FROM vandelay.queued_bib_record WHERE id = NEW.id;
        IF (value IS NOT NULL AND value <> '') THEN
            INSERT INTO vandelay.queued_bib_record_attr (record, field, attr_value) VALUES (NEW.id, adef.id, value);
        END IF;

    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.cleanup_bib_marc ( ) RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

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

CREATE TRIGGER zz_match_bibs_trigger
    BEFORE INSERT OR UPDATE ON vandelay.queued_bib_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.match_bib_record();


/* Authority stuff down here */
---------------------------------------
CREATE TABLE vandelay.authority_attr_definition (
	id			SERIAL	PRIMARY KEY,
	code		TEXT	UNIQUE NOT NULL,
	description	TEXT,
	xpath		TEXT	NOT NULL,
	remove		TEXT	NOT NULL DEFAULT ''
);

CREATE TYPE vandelay.authority_queue_queue_type AS ENUM ('authority');
CREATE TABLE vandelay.authority_queue (
	queue_type	vandelay.authority_queue_queue_type NOT NULL DEFAULT 'authority',
	CONSTRAINT vand_authority_queue_name_once_per_owner_const UNIQUE (owner,name,queue_type)
) INHERITS (vandelay.queue);
ALTER TABLE vandelay.authority_queue ADD PRIMARY KEY (id);

CREATE TABLE vandelay.queued_authority_record (
	queue		INT	NOT NULL REFERENCES vandelay.authority_queue (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	imported_as	INT	REFERENCES authority.record_entry (id) DEFERRABLE INITIALLY DEFERRED,
	import_error	TEXT    REFERENCES vandelay.import_error (code) ON DELETE SET NULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED,
	error_detail	TEXT
) INHERITS (vandelay.queued_record);
ALTER TABLE vandelay.queued_authority_record ADD PRIMARY KEY (id);
CREATE INDEX queued_authority_record_queue_idx ON vandelay.queued_authority_record (queue);

CREATE TABLE vandelay.queued_authority_record_attr (
	id			BIGSERIAL	PRIMARY KEY,
	record		BIGINT		NOT NULL REFERENCES vandelay.queued_authority_record (id) DEFERRABLE INITIALLY DEFERRED,
	field		INT			NOT NULL REFERENCES vandelay.authority_attr_definition (id) DEFERRABLE INITIALLY DEFERRED,
	attr_value	TEXT		NOT NULL
);
CREATE INDEX queued_authority_record_attr_record_idx ON vandelay.queued_authority_record_attr (record);

CREATE TABLE vandelay.authority_match (
	id				BIGSERIAL	PRIMARY KEY,
	queued_record	BIGINT		REFERENCES vandelay.queued_authority_record (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	eg_record		BIGINT		REFERENCES authority.record_entry (id) DEFERRABLE INITIALLY DEFERRED,
    quality         INT         NOT NULL DEFAULT 0,
    match_score     INT         NOT NULL DEFAULT 0
);

CREATE OR REPLACE FUNCTION vandelay.ingest_authority_marc ( ) RETURNS TRIGGER AS $$
DECLARE
    value   TEXT;
    atype   TEXT;
    adef    RECORD;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

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
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

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

CREATE OR REPLACE FUNCTION vandelay.overlay_authority_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    merge_profile   vandelay.merge_profile%ROWTYPE;
    dyn_profile     vandelay.compile_profile%ROWTYPE;
    editor_string   TEXT;
    new_editor      INT;
    new_edit_date   TIMESTAMPTZ;
    source_marc     TEXT;
    target_marc     TEXT;
    eg_marc_row     authority.record_entry%ROWTYPE;
    eg_marc         TEXT;
    v_marc          TEXT;
    replace_rule    TEXT;
    match_count     INT;
    update_query    TEXT;
BEGIN

    SELECT  * INTO eg_marc_row
      FROM  authority.record_entry b
            JOIN vandelay.authority_match m ON (m.eg_record = b.id AND m.queued_record = import_id)
      LIMIT 1;

    SELECT  q.marc INTO v_marc
      FROM  vandelay.queued_record q
            JOIN vandelay.authority_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    eg_marc := eg_marc_row.marc;

    IF eg_marc IS NULL OR v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or authority record';
        RETURN FALSE;
    END IF;

    -- Extract the editor string before any modification to the vandelay
    -- MARC occur.
    editor_string := 
        (oils_xpath('//*[@tag="905"]/*[@code="u"]/text()',v_marc))[1];

    -- If an editor value can be found, update the authority record
    -- editor and edit_date values.
    IF editor_string IS NOT NULL AND editor_string <> '' THEN

        -- Vandelay.pm sets the value to 'usrname' when needed.  
        SELECT id INTO new_editor
            FROM actor.usr WHERE usrname = editor_string;

        IF new_editor IS NULL THEN
            SELECT usr INTO new_editor
                FROM actor.card WHERE barcode = editor_string;
        END IF;

        IF new_editor IS NOT NULL THEN
            new_edit_date := NOW();
        ELSE -- No valid editor, use current values
            new_editor = eg_marc_row.editor;
            new_edit_date = eg_marc_row.edit_date;
        END IF;
    ELSE
        new_editor = eg_marc_row.editor;
        new_edit_date = eg_marc_row.edit_date;
    END IF;

    dyn_profile := vandelay.compile_profile( v_marc );

    IF merge_profile_id IS NOT NULL THEN
        SELECT * INTO merge_profile FROM vandelay.merge_profile WHERE id = merge_profile_id;
        IF FOUND THEN
            dyn_profile.add_rule := BTRIM( dyn_profile.add_rule || ',' || COALESCE(merge_profile.add_spec,''), ',');
            dyn_profile.strip_rule := BTRIM( dyn_profile.strip_rule || ',' || COALESCE(merge_profile.strip_spec,''), ',');
            dyn_profile.replace_rule := BTRIM( dyn_profile.replace_rule || ',' || COALESCE(merge_profile.replace_spec,''), ',');
            dyn_profile.preserve_rule := BTRIM( dyn_profile.preserve_rule || ',' || COALESCE(merge_profile.preserve_spec,''), ',');
        END IF;
    END IF;

    IF dyn_profile.replace_rule <> '' AND dyn_profile.preserve_rule <> '' THEN
        -- RAISE NOTICE 'both replace [%] and preserve [%] specified', dyn_profile.replace_rule, dyn_profile.preserve_rule;
        RETURN FALSE;
    END IF;

    IF dyn_profile.replace_rule = '' AND dyn_profile.preserve_rule = '' AND dyn_profile.add_rule = '' AND dyn_profile.strip_rule = '' THEN
        --Since we have nothing to do, just return a NOOP "we did it"
        RETURN TRUE;
    ELSIF dyn_profile.replace_rule <> '' THEN
        source_marc = v_marc;
        target_marc = eg_marc;
        replace_rule = dyn_profile.replace_rule;
    ELSE
        source_marc = eg_marc;
        target_marc = v_marc;
        replace_rule = dyn_profile.preserve_rule;
    END IF;

    UPDATE  authority.record_entry
      SET   marc = vandelay.merge_record_xml( target_marc, source_marc, dyn_profile.add_rule, replace_rule, dyn_profile.strip_rule ),
            editor = new_editor,
            edit_date = new_edit_date
      WHERE id = eg_id;

    IF NOT FOUND THEN 
        -- Import/merge failed.  Nothing left to do.
        RETURN FALSE;
    END IF;

    -- Authority record successfully merged / imported.

    -- Update the vandelay record to show the successful import.
    UPDATE  vandelay.queued_authority_record
      SET   imported_as = eg_id,
            import_time = NOW()
      WHERE id = import_id;

    RETURN TRUE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_record ( import_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    match_count     INT;
BEGIN
    SELECT COUNT(*) INTO match_count FROM vandelay.authority_match WHERE queued_record = import_id;

    IF match_count <> 1 THEN
        -- RAISE NOTICE 'not an exact match';
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.authority_match m
      WHERE m.queued_record = import_id
      LIMIT 1;

    IF eg_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_authority_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_queue ( queue_id BIGINT, merge_profile_id INT ) RETURNS SETOF BIGINT AS $$
DECLARE
    queued_record   vandelay.queued_authority_record%ROWTYPE;
BEGIN

    FOR queued_record IN SELECT * FROM vandelay.queued_authority_record WHERE queue = queue_id AND import_time IS NULL LOOP

        IF vandelay.auto_overlay_authority_record( queued_record.id, merge_profile_id ) THEN
            RETURN NEXT queued_record.id;
        END IF;

    END LOOP;

    RETURN;
    
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_queue ( queue_id BIGINT ) RETURNS SETOF BIGINT AS $$
    SELECT * FROM vandelay.auto_overlay_authority_queue( $1, NULL );
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION vandelay.match_set_test_authxml(
    match_set_id INTEGER, record_xml TEXT
) RETURNS SETOF vandelay.match_set_test_result AS $$
DECLARE
    tags_rstore HSTORE;
    heading     TEXT;
    coal        TEXT;
    joins       TEXT;
    query_      TEXT;
    wq          TEXT;
    qvalue      INTEGER;
    rec         RECORD;
BEGIN
    tags_rstore := vandelay.flatten_marc_hstore(record_xml);

    SELECT normalize_heading INTO heading 
        FROM authority.normalize_heading(record_xml);

    CREATE TEMPORARY TABLE _vandelay_tmp_qrows (q INTEGER);
    CREATE TEMPORARY TABLE _vandelay_tmp_jrows (j TEXT);

    -- generate the where clause and return that directly (into wq), and as
    -- a side-effect, populate the _vandelay_tmp_[qj]rows tables.
    wq := vandelay.get_expr_from_match_set(
        match_set_id, tags_rstore, heading);

    query_ := 'SELECT DISTINCT(record), ';

    -- qrows table is for the quality bits we add to the SELECT clause
    SELECT STRING_AGG(
        'COALESCE(n' || q::TEXT || '.quality, 0)', ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT STRING_AGG(j, E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n';

    query_ := query_ || 'JOIN authority.record_entry are ON (are.id = record) ' 
        || 'WHERE ' || wq || ' AND not are.deleted';

    -- this will return rows of record,quality
    FOR rec IN EXECUTE query_ USING tags_rstore LOOP
        RETURN NEXT rec;
    END LOOP;

    DROP TABLE _vandelay_tmp_qrows;
    DROP TABLE _vandelay_tmp_jrows;
    RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.measure_auth_record_quality 
    ( xml TEXT, match_set_id INT ) RETURNS INT AS $_$
DECLARE
    out_q   INT := 0;
    rvalue  TEXT;
    test    vandelay.match_set_quality%ROWTYPE;
BEGIN

    FOR test IN SELECT * FROM vandelay.match_set_quality 
            WHERE match_set = match_set_id LOOP
        IF test.tag IS NOT NULL THEN
            FOR rvalue IN SELECT value FROM vandelay.flatten_marc( xml ) 
                WHERE tag = test.tag AND subfield = test.subfield LOOP
                IF test.value = rvalue THEN
                    out_q := out_q + test.quality;
                END IF;
            END LOOP;
        END IF;
    END LOOP;

    RETURN out_q;
END;
$_$ LANGUAGE PLPGSQL;



CREATE OR REPLACE FUNCTION vandelay.match_authority_record() RETURNS TRIGGER AS $func$
DECLARE
    incoming_existing_id    TEXT;
    test_result             vandelay.match_set_test_result%ROWTYPE;
    tmp_rec                 BIGINT;
    match_set               INT;
BEGIN
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.imported_as IS NOT NULL THEN
        RETURN NEW;
    END IF;

    DELETE FROM vandelay.authority_match WHERE queued_record = NEW.id;

    SELECT q.match_set INTO match_set FROM vandelay.authority_queue q WHERE q.id = NEW.queue;

    IF match_set IS NOT NULL THEN
        NEW.quality := vandelay.measure_auth_record_quality( NEW.marc, match_set );
    END IF;

    -- Perfect matches on 901$c exit early with a match with high quality.
    incoming_existing_id :=
        oils_xpath_string('//*[@tag="901"]/*[@code="c"][1]', NEW.marc);

    IF incoming_existing_id IS NOT NULL AND incoming_existing_id != '' THEN
        SELECT id INTO tmp_rec FROM authority.record_entry WHERE id = incoming_existing_id::bigint;
        IF tmp_rec IS NOT NULL THEN
            INSERT INTO vandelay.authority_match (queued_record, eg_record, match_score, quality) 
                SELECT
                    NEW.id, 
                    b.id,
                    9999,
                    -- note: no match_set means quality==0
                    vandelay.measure_auth_record_quality( b.marc, match_set )
                FROM authority.record_entry b
                WHERE id = incoming_existing_id::bigint;
        END IF;
    END IF;

    IF match_set IS NULL THEN
        RETURN NEW;
    END IF;

    FOR test_result IN SELECT * FROM
        vandelay.match_set_test_authxml(match_set, NEW.marc) LOOP

        INSERT INTO vandelay.authority_match ( queued_record, eg_record, match_score, quality )
            SELECT  
                NEW.id,
                test_result.record,
                test_result.quality,
                vandelay.measure_auth_record_quality( b.marc, match_set )
	        FROM  authority.record_entry b
	        WHERE id = test_result.record;

    END LOOP;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER zz_match_auths_trigger
    BEFORE INSERT OR UPDATE ON vandelay.queued_authority_record
    FOR EACH ROW EXECUTE PROCEDURE vandelay.match_authority_record();

CREATE OR REPLACE FUNCTION vandelay.auto_overlay_authority_record_with_best ( import_id BIGINT, merge_profile_id INT, lwm_ratio_value_p NUMERIC ) RETURNS BOOL AS $$
DECLARE
    eg_id           BIGINT;
    lwm_ratio_value NUMERIC;
BEGIN

    lwm_ratio_value := COALESCE(lwm_ratio_value_p, 0.0);

    PERFORM * FROM vandelay.queued_authority_record WHERE import_time IS NOT NULL AND id = import_id;

    IF FOUND THEN
        -- RAISE NOTICE 'already imported, cannot auto-overlay'
        RETURN FALSE;
    END IF;

    SELECT  m.eg_record INTO eg_id
      FROM  vandelay.authority_match m
            JOIN vandelay.queued_authority_record qr ON (m.queued_record = qr.id)
            JOIN vandelay.authority_queue q ON (qr.queue = q.id)
            JOIN authority.record_entry r ON (r.id = m.eg_record)
      WHERE m.queued_record = import_id
            AND qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC >= lwm_ratio_value
      ORDER BY  m.match_score DESC, -- required match score
                qr.quality::NUMERIC / COALESCE(NULLIF(m.quality,0),1)::NUMERIC DESC, -- quality tie breaker
                m.id -- when in doubt, use the first match
      LIMIT 1;

    IF eg_id IS NULL THEN
        -- RAISE NOTICE 'incoming record is not of high enough quality';
        RETURN FALSE;
    END IF;

    RETURN vandelay.overlay_authority_record( import_id, eg_id, merge_profile_id );
END;
$$ LANGUAGE PLPGSQL;




-- Vandelay (for importing and exporting records) 012.schema.vandelay.sql 
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (1, 'title', oils_i18n_gettext(1, 'vqbrad', 'Title of work', 'description'),'//*[@tag="245"]/*[contains("abcmnopr",@code)]');
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (2, 'author', oils_i18n_gettext(1, 'vqbrad', 'Author of work', 'description'),'//*[@tag="100" or @tag="110" or @tag="113"]/*[contains("ad",@code)]');
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (3, 'language', oils_i18n_gettext(3, 'vqbrad', 'Language of work', 'description'),'//*[@tag="240"]/*[@code="l"][1]');
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (4, 'pagination', oils_i18n_gettext(4, 'vqbrad', 'Pagination', 'description'),'//*[@tag="300"]/*[@code="a"][1]');
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath, ident, remove ) VALUES (5, 'isbn',oils_i18n_gettext(5, 'vqbrad', 'ISBN', 'description'),'//*[@tag="020"]/*[@code="a"]', TRUE, $r$(?:-|\s.+$)$r$);
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath, ident, remove ) VALUES (6, 'issn',oils_i18n_gettext(6, 'vqbrad', 'ISSN', 'description'),'//*[@tag="022"]/*[@code="a"]', TRUE, $r$(?:-|\s.+$)$r$);
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (7, 'price',oils_i18n_gettext(7, 'vqbrad', 'Price', 'description'),'//*[@tag="020" or @tag="022"]/*[@code="c"][1]');
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath, ident ) VALUES (8, 'rec_identifier',oils_i18n_gettext(8, 'vqbrad', 'Accession Number', 'description'),'//*[@tag="001"]', TRUE);
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath, ident ) VALUES (9, 'eg_tcn',oils_i18n_gettext(9, 'vqbrad', 'TCN Value', 'description'),'//*[@tag="901"]/*[@code="a"]', TRUE);
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath, ident ) VALUES (10, 'eg_tcn_source',oils_i18n_gettext(10, 'vqbrad', 'TCN Source', 'description'),'//*[@tag="901"]/*[@code="b"]', TRUE);
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath, ident ) VALUES (11, 'eg_identifier',oils_i18n_gettext(11, 'vqbrad', 'Internal ID', 'description'),'//*[@tag="901"]/*[@code="c"]', TRUE);
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (12, 'publisher',oils_i18n_gettext(12, 'vqbrad', 'Publisher', 'description'),'//*[@tag="260"]/*[@code="b"][1]');
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath, remove ) VALUES (13, 'pubdate',oils_i18n_gettext(13, 'vqbrad', 'Publication Date', 'description'),'//*[@tag="260"]/*[@code="c"][1]',$r$\D$r$);
--INSERT INTO vandelay.bib_attr_definition ( id, code, description, xpath ) VALUES (14, 'edition',oils_i18n_gettext(14, 'vqbrad', 'Edition', 'description'),'//*[@tag="250"]/*[@code="a"][1]');
--
--INSERT INTO vandelay.import_item_attr_definition (
--    owner, name, tag, owning_lib, circ_lib, location,
--    call_number, circ_modifier, barcode, price, copy_number,
--    circulate, ref, holdable, opac_visible, status
--) VALUES (
--    1,
--    'Evergreen 852 export format',
--    '852',
--    '[@code = "b"][1]',
--    '[@code = "b"][2]',
--    'c',
--    'j',
--    'g',
--    'p',
--    'y',
--    't',
--    '[@code = "x" and text() = "circulating"]',
--    '[@code = "x" and text() = "reference"]',
--    '[@code = "x" and text() = "holdable"]',
--    '[@code = "x" and text() = "visible"]',
--    'z'
--);
--
--INSERT INTO vandelay.import_item_attr_definition (
--    owner,
--    name,
--    tag,
--    owning_lib,
--    location,
--    call_number,
--    circ_modifier,
--    barcode,
--    price,
--    status
--) VALUES (
--    1,
--    'Unicorn Import format -- 999',
--    '999',
--    'm',
--    'l',
--    'a',
--    't',
--    'i',
--    'p',
--    'k'
--);
--
--INSERT INTO vandelay.authority_attr_definition ( code, description, xpath, ident ) VALUES ('rec_identifier','Identifier','//*[@tag="001"]', TRUE);


CREATE TABLE vandelay.session_tracker (
    id          BIGSERIAL PRIMARY KEY,

    -- string of characters (e.g. md5) used for linking trackers
    -- of different actions into a series.  There can be multiple
    -- session_keys of each action type, creating the opportunity
    -- to link multiple action trackers into a single session.
    session_key TEXT NOT NULL,

    -- optional user-supplied name
    name        TEXT NOT NULL, 

    usr         INTEGER NOT NULL REFERENCES actor.usr(id)
                DEFERRABLE INITIALLY DEFERRED,

    -- org unit can be derived from WS
    workstation INTEGER NOT NULL REFERENCES actor.workstation(id)
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,

    -- bib/auth
    record_type TEXT NOT NULL DEFAULT 'bib',

    -- Queue defines the source of the data, it does not necessarily
    -- mean that an action is being performed against an entire queue.
    -- E.g. some imports are misc. lists of record IDs, but they always 
    -- come from one queue.
    -- No foreign key -- could be auth or bib queue.
    queue       BIGINT NOT NULL,

    create_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    update_time TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    state       TEXT NOT NULL DEFAULT 'active',

    action_type TEXT NOT NULL DEFAULT 'enqueue', -- import

    -- total number of tasks to perform / loosely defined
    -- could be # of recs to import or # of recs + # of copies 
    -- depending on the import context
    total_actions INTEGER NOT NULL DEFAULT 0,

    -- total number of tasked performed so far
    actions_performed INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT vand_tracker_valid_state 
        CHECK (state IN ('active','error','complete')),

    CONSTRAINT vand_tracker_valid_action_type
        CHECK (action_type IN ('upload', 'enqueue', 'import')),

    CONSTRAINT vand_tracker_valid_record_type
        CHECK (record_type IN ('bib', 'authority'))
);

CREATE TABLE vandelay.background_import (
    id              SERIAL      PRIMARY KEY,
    owner           INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    workstation     INT         REFERENCES actor.workstation (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    import_type     TEXT        NOT NULL DEFAULT 'bib' CHECK (import_type IN ('bib','acq','authority')),
    params          TEXT,
    email           TEXT,
    state           TEXT        NOT NULL DEFAULT 'new' CHECK (state IN ('new','running','complete')),
    request_time    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    complete_time   TIMESTAMPTZ,
    queue           BIGINT      -- no fkey, could be either bib_queue or authority_queue, based on import_type
);

COMMIT;

