BEGIN;

SELECT evergreen.upgrade_deps_block_check('0864', :eg_version);

CREATE EXTENSION IF NOT EXISTS intarray;

-- while we have this opportunity, and before we start collecting 
-- CCVM IDs (below) carve out a nice space for stock ccvm values
UPDATE config.coded_value_map SET id = id + 10000 WHERE id > 556;
SELECT SETVAL('config.coded_value_map_id_seq'::TEXT, 
    (SELECT GREATEST(max(id), 10000) FROM config.coded_value_map));

ALTER TABLE config.record_attr_definition ADD COLUMN multi BOOL NOT NULL DEFAULT TRUE, ADD COLUMN composite BOOL NOT NULL DEFAULT FALSE;

UPDATE  config.record_attr_definition
  SET   multi = FALSE
  WHERE name IN ('bib_level','control_type','pubdate','cat_form','enc_level','item_type','titlesort','authorsort');

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

CREATE OR REPLACE FUNCTION vandelay.marc21_extract_fixed_field_list( marc TEXT, ff TEXT ) RETURNS TEXT[] AS $func$
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
        val := REPEAT( ff_pos.default_val, ff_pos.length );
        collection := collection || val;
    END LOOP;

    RETURN collection;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION biblio.marc21_extract_fixed_field_list( rid BIGINT, ff TEXT ) RETURNS TEXT[] AS $func$
    SELECT * FROM vandelay.marc21_extract_fixed_field_list( (SELECT marc FROM biblio.record_entry WHERE id = $1), $2 );
$func$ LANGUAGE SQL;

-- DECREMENTING serial starts at -1
CREATE SEQUENCE metabib.uncontrolled_record_attr_value_id_seq INCREMENT BY -1;

CREATE TABLE metabib.uncontrolled_record_attr_value (
    id      BIGINT  PRIMARY KEY DEFAULT nextval('metabib.uncontrolled_record_attr_value_id_seq'),
    attr    TEXT    NOT NULL REFERENCES config.record_attr_definition (name),
    value   TEXT    NOT NULL
);
CREATE UNIQUE INDEX muv_once_idx ON metabib.uncontrolled_record_attr_value (attr,value);

CREATE TABLE metabib.record_attr_vector_list (
    source  BIGINT  PRIMARY KEY REFERENCES  biblio.record_entry (id),
    vlist   INT[]   NOT NULL -- stores id from ccvm AND murav
);
CREATE INDEX mrca_vlist_idx ON metabib.record_attr_vector_list USING gin ( vlist gin__int_ops );

CREATE TABLE metabib.record_sorter (
    id      BIGSERIAL   PRIMARY KEY,
    source  BIGINT      NOT NULL REFERENCES biblio.record_entry (id) ON DELETE CASCADE,
    attr    TEXT        NOT NULL REFERENCES config.record_attr_definition (name) ON DELETE CASCADE,
    value   TEXT        NOT NULL
);
CREATE INDEX metabib_sorter_source_idx ON metabib.record_sorter (source); -- we may not need one of this or the next ... stats will tell
CREATE INDEX metabib_sorter_s_a_idx ON metabib.record_sorter (source, attr);
CREATE INDEX metabib_sorter_a_v_idx ON metabib.record_sorter (attr, value);

CREATE TEMP TABLE attr_set ON COMMIT DROP AS SELECT  DISTINCT id AS source, (each(attrs)).key,(each(attrs)).value FROM metabib.record_attr;
DELETE FROM attr_set WHERE BTRIM(value) = '';

-- Grab sort values for the new sorting mechanism
INSERT INTO metabib.record_sorter (source,attr,value)
    SELECT  a.source, a.key, a.value
      FROM  attr_set a
            JOIN config.record_attr_definition d ON (d.name = a.key AND d.sorter AND a.value IS NOT NULL);

-- Rewrite uncontrolled SVF record attrs as the seeds of an intarray vector
INSERT INTO metabib.uncontrolled_record_attr_value (attr,value)
    SELECT  DISTINCT a.key, a.value
      FROM  attr_set a
            JOIN config.record_attr_definition d ON (d.name = a.key AND d.filter AND a.value IS NOT NULL)
            LEFT JOIN config.coded_value_map m ON (m.ctype = a.key)
      WHERE m.id IS NULL;

-- Now construct the record-specific vector from the SVF data
INSERT INTO metabib.record_attr_vector_list (source,vlist)
    SELECT  a.id, ARRAY_AGG(COALESCE(u.id, c.id))
      FROM  metabib.record_attr a
            JOIN attr_set ON (a.id = attr_set.source)
            LEFT JOIN metabib.uncontrolled_record_attr_value u ON (u.attr = attr_set.key AND u.value = attr_set.value)
            LEFT JOIN config.coded_value_map c ON (c.ctype = attr_set.key AND c.code = attr_set.value)
      WHERE COALESCE(u.id,c.id) IS NOT NULL
      GROUP BY 1;

DROP VIEW IF EXISTS reporter.classic_current_circ; 
DROP VIEW metabib.rec_descriptor;
DROP TABLE metabib.record_attr;

CREATE TYPE metabib.record_attr_type AS (
    id      BIGINT,
    attrs   HSTORE
);

CREATE TABLE config.composite_attr_entry_definition(
    coded_value INT  PRIMARY KEY NOT NULL REFERENCES config.coded_value_map (id) ON UPDATE CASCADE ON DELETE CASCADE,
    definition  TEXT NOT NULL -- JSON
);

CREATE OR REPLACE VIEW metabib.record_attr_id_map AS
    SELECT id, attr, value FROM metabib.uncontrolled_record_attr_value
        UNION
    SELECT  c.id, c.ctype AS attr, c.code AS value
      FROM  config.coded_value_map c
            JOIN config.record_attr_definition d ON (d.name = c.ctype AND NOT d.composite);

CREATE VIEW metabib.composite_attr_id_map AS
    SELECT  c.id, c.ctype AS attr, c.code AS value
      FROM  config.coded_value_map c
            JOIN config.record_attr_definition d ON (d.name = c.ctype AND d.composite);

CREATE OR REPLACE VIEW metabib.full_attr_id_map AS
    SELECT id, attr, value FROM metabib.record_attr_id_map
        UNION
    SELECT id, attr, value FROM metabib.composite_attr_id_map;


-- Back-compat view ... we're moving to an INTARRAY world
CREATE VIEW metabib.record_attr_flat AS
    SELECT  v.source AS id,
            m.attr,
            m.value
      FROM  metabib.full_attr_id_map m
            JOIN  metabib.record_attr_vector_list v ON ( m.id = ANY( v.vlist ) );

CREATE VIEW metabib.record_attr AS
    SELECT id, HSTORE( ARRAY_AGG( attr ), ARRAY_AGG( value ) ) AS attrs FROM metabib.record_attr_flat GROUP BY 1;

CREATE VIEW metabib.rec_descriptor AS
    SELECT  id,
            id AS record,
            (populate_record(NULL::metabib.rec_desc_type, attrs)).*
      FROM  metabib.record_attr;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr_cache_init () RETURNS BOOL AS $f$
    $_SHARED{metabib_compile_composite_attr_cache} = {}
        if ! exists $_SHARED{metabib_compile_composite_attr_cache};
    return exists $_SHARED{metabib_compile_composite_attr_cache};
$f$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr_cache_disable () RETURNS BOOL AS $f$
    delete $_SHARED{metabib_compile_composite_attr_cache};
    return ! exists $_SHARED{metabib_compile_composite_attr_cache};
$f$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr_cache_invalidate () RETURNS BOOL AS $f$
    SELECT metabib.compile_composite_attr_cache_disable() AND metabib.compile_composite_attr_cache_init();
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.composite_attr_def_cache_inval_tgr () RETURNS TRIGGER AS $f$
BEGIN
    PERFORM metabib.compile_composite_attr_cache_invalidate();
    RETURN NULL;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER ccraed_cache_inval_tgr AFTER INSERT OR UPDATE OR DELETE ON config.composite_attr_entry_definition FOR EACH STATEMENT EXECUTE PROCEDURE metabib.composite_attr_def_cache_inval_tgr();
    
CREATE OR REPLACE FUNCTION metabib.compile_composite_attr ( cattr_def TEXT ) RETURNS query_int AS $func$

    use JSON::XS;

    my $json = shift;
    my $def = decode_json($json);

    die("Composite attribute definition not supplied") unless $def;

    my $_cache = (exists $_SHARED{metabib_compile_composite_attr_cache}) ? 1 : 0;

    return $_SHARED{metabib_compile_composite_attr_cache}{$json}
        if ($_cache && $_SHARED{metabib_compile_composite_attr_cache}{$json});

    sub recurse {
        my $d = shift;
        my $j = '&';
        my @list;

        if (ref $d eq 'HASH') { # node or AND
            if (exists $d->{_attr}) { # it is a node
                my $plan = spi_prepare('SELECT * FROM metabib.full_attr_id_map WHERE attr = $1 AND value = $2', qw/TEXT TEXT/);
                my $id = spi_exec_prepared(
                    $plan, {limit => 1}, $d->{_attr}, $d->{_val}
                )->{rows}[0]{id};
                spi_freeplan($plan);
                return $id;
            } elsif (exists $d->{_not} && scalar(keys(%$d)) == 1) { # it is a NOT
                return '!' . recurse($$d{_not});
            } else { # an AND list
                @list = map { recurse($$d{$_}) } sort keys %$d;
            }
        } elsif (ref $d eq 'ARRAY') {
            $j = '|';
            @list = map { recurse($_) } @$d;
        }

        @list = grep { defined && $_ ne '' } @list;

        return '(' . join($j,@list) . ')' if @list;
        return '';
    }

    my $val = recurse($def) || undef;
    $_SHARED{metabib_compile_composite_attr_cache}{$json} = $val if $_cache;
    return $val;

$func$ IMMUTABLE LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION metabib.compile_composite_attr ( cattr_id INT ) RETURNS query_int AS $func$
    SELECT metabib.compile_composite_attr(definition) FROM config.composite_attr_entry_definition WHERE coded_value = $1;
$func$ STRICT IMMUTABLE LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.reingest_record_attributes (rid BIGINT, pattr_list TEXT[] DEFAULT NULL, prmarc TEXT DEFAULT NULL, rdeleted BOOL DEFAULT TRUE) RETURNS VOID AS $func$
DECLARE
    transformed_xml TEXT;
    rmarc           TEXT := prmarc;
    tmp_val         TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_vector     INT[] := '{}'::INT[];
    attr_vector_tmp INT[];
    attr_list       TEXT[] := pattr_list;
    attr_value      TEXT[];
    norm_attr_value TEXT[];
    tmp_xml         XML;
    attr_def        config.record_attr_definition%ROWTYPE;
    ccvm_row        config.coded_value_map%ROWTYPE;
BEGIN

    IF attr_list IS NULL OR rdeleted THEN -- need to do the full dance on INSERT or undelete
        SELECT ARRAY_AGG(name) INTO attr_list FROM config.record_attr_definition;
    END IF;

    IF rmarc IS NULL THEN
        SELECT marc INTO rmarc FROM biblio.record_entry WHERE id = rid;
    END IF;

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE NOT composite AND name = ANY( attr_list ) ORDER BY format LOOP

        attr_value := '{}'::TEXT[];
        norm_attr_value := '{}'::TEXT[];
        attr_vector_tmp := '{}'::INT[];

        SELECT * INTO ccvm_row FROM config.coded_value_map c WHERE c.ctype = attr_def.name LIMIT 1; 

        -- tag+sf attrs only support SVF
        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  ARRAY[ARRAY_TO_STRING(ARRAY_AGG(value), COALESCE(attr_def.joiner,' '))] INTO attr_value
              FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
              WHERE record = rid
                    AND tag LIKE attr_def.tag
                    AND CASE
                        WHEN attr_def.sf_list IS NOT NULL 
                            THEN POSITION(subfield IN attr_def.sf_list) > 0
                        ELSE TRUE
                    END
              GROUP BY tag
              ORDER BY tag
              LIMIT 1;

        ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
            attr_value := vandelay.marc21_extract_fixed_field_list(rmarc, attr_def.fixed_field);

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
        
            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(rmarc,xfrm.xslt);
                ELSE
                    transformed_xml := rmarc;
                END IF;
    
                prev_xfrm := xfrm.name;
            END IF;

            IF xfrm.name IS NULL THEN
                -- just grab the marcxml (empty) transform
                SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                prev_xfrm := xfrm.name;
            END IF;

            FOR tmp_xml IN SELECT XPATH(attr_def.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]) LOOP
                tmp_val := oils_xpath_string(
                                '//*',
                                tmp_xml::TEXT,
                                COALESCE(attr_def.joiner,' '),
                                ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                            );
                IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                    attr_value := attr_value || tmp_val;
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END LOOP;

        ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
            SELECT  ARRAY_AGG(m.value) INTO attr_value
              FROM  vandelay.marc21_physical_characteristics(rmarc) v
                    LEFT JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
              WHERE v.subfield = attr_def.phys_char_sf AND (m.value IS NOT NULL AND BTRIM(m.value) <> '')
                    AND ( ccvm_row.id IS NULL OR ( ccvm_row.id IS NOT NULL AND v.id IS NOT NULL) );

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        END IF;

                -- apply index normalizers to attr_value
        FOR tmp_val IN SELECT value FROM UNNEST(attr_value) x(value) LOOP
            FOR normalizer IN
                SELECT  n.func AS func,
                        n.param_count AS param_count,
                        m.params AS params
                  FROM  config.index_normalizer n
                        JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                  WHERE attr = attr_def.name
                  ORDER BY m.pos LOOP
                    EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    COALESCE( quote_literal( tmp_val ), 'NULL' ) ||
                        CASE
                            WHEN normalizer.param_count > 0
                                THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                ELSE ''
                            END ||
                    ')' INTO tmp_val;

            END LOOP;
            IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                norm_attr_value := norm_attr_value || tmp_val;
            END IF;
        END LOOP;
        
        IF attr_def.filter THEN
            -- Create unknown uncontrolled values and find the IDs of the values
            IF ccvm_row.id IS NULL THEN
                FOR tmp_val IN SELECT value FROM UNNEST(norm_attr_value) x(value) LOOP
                    IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                        BEGIN -- use subtransaction to isolate unique constraint violations
                            INSERT INTO metabib.uncontrolled_record_attr_value ( attr, value ) VALUES ( attr_def.name, tmp_val );
                        EXCEPTION WHEN unique_violation THEN END;
                    END IF;
                END LOOP;

                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM metabib.uncontrolled_record_attr_value WHERE attr = attr_def.name AND value = ANY( norm_attr_value );
            ELSE
                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM config.coded_value_map WHERE ctype = attr_def.name AND code = ANY( norm_attr_value );
            END IF;

            -- Add the new value to the vector
            attr_vector := attr_vector || attr_vector_tmp;
        END IF;

        IF attr_def.sorter AND norm_attr_value[1] IS NOT NULL THEN
            DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
            INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, norm_attr_value[1]);
        END IF;

    END LOOP;

/* We may need to rewrite the vlist to contain
   the intersection of new values for requested
   attrs and old values for ignored attrs. To
   do this, we take the old attr vlist and
   subtract any values that are valid for the
   requested attrs, and then add back the new
   set of attr values. */

        IF ARRAY_LENGTH(pattr_list, 1) > 0 THEN 
            SELECT vlist INTO attr_vector_tmp FROM metabib.record_attr_vector_list WHERE source = rid;
            SELECT attr_vector_tmp - ARRAY_AGG(id::INT) INTO attr_vector_tmp FROM metabib.full_attr_id_map WHERE attr = ANY (pattr_list);
            attr_vector := attr_vector || attr_vector_tmp;
        END IF;

    -- On to composite attributes, now that the record attrs have been pulled.  Processed in name order, so later composite
    -- attributes can depend on earlier ones.
    PERFORM metabib.compile_composite_attr_cache_init();
    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE composite AND name = ANY( attr_list ) ORDER BY name LOOP

        FOR ccvm_row IN SELECT * FROM config.coded_value_map c WHERE c.ctype = attr_def.name ORDER BY value LOOP

            tmp_val := metabib.compile_composite_attr( ccvm_row.id );
            CONTINUE WHEN tmp_val IS NULL OR tmp_val = ''; -- nothing to do

            IF attr_def.filter THEN
                IF attr_vector @@ tmp_val::query_int THEN
                    attr_vector = attr_vector + intset(ccvm_row.id);
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END IF;

            IF attr_def.sorter THEN
                IF attr_vector @@ tmp_val THEN
                    DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
                    INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, ccvm_row.code);
                END IF;
            END IF;

        END LOOP;

    END LOOP;

    IF ARRAY_LENGTH(attr_vector, 1) > 0 THEN
        IF rdeleted THEN -- initial insert OR revivication
            DELETE FROM metabib.record_attr_vector_list WHERE source = rid;
            INSERT INTO metabib.record_attr_vector_list (source, vlist) VALUES (rid, attr_vector);
        ELSE
            UPDATE metabib.record_attr_vector_list SET vlist = attr_vector WHERE source = rid;
        END IF;
    END IF;

END;

$func$ LANGUAGE PLPGSQL;

-- AFTER UPDATE OR INSERT trigger for biblio.record_entry
CREATE OR REPLACE FUNCTION biblio.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
BEGIN

    IF NEW.deleted THEN -- If this bib is deleted
        PERFORM * FROM config.internal_flag WHERE
            name = 'ingest.metarecord_mapping.preserve_on_delete' AND enabled;
        IF NOT FOUND THEN
            -- One needs to keep these around to support searches
            -- with the #deleted modifier, so one should turn on the named
            -- internal flag for that functionality.
            DELETE FROM metabib.metarecord_source_map WHERE source = NEW.id;
            DELETE FROM metabib.record_attr_vector_list WHERE source = NEW.id;
        END IF;

        DELETE FROM authority.bib_linking WHERE bib = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = NEW.id; -- Separate any multi-homed items
        DELETE FROM metabib.browse_entry_def_map WHERE source = NEW.id; -- Don't auto-suggest deleted bibs
        RETURN NEW; -- and we're done
            END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;
    END IF;

    -- Record authority linking
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_linking' AND enabled;
    IF NOT FOUND THEN
        PERFORM biblio.map_authority_linking( NEW.id, NEW.marc );
    END IF;

    -- Flatten and insert the mfr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.reingest_metabib_full_rec(NEW.id);

        -- Now we pull out attribute data, which is dependent on the mfr for all but XPath-based fields
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_metabib_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.reingest_record_attributes(NEW.id, NULL, NEW.marc, TG_OP = 'INSERT' OR OLD.deleted);
        END IF;
    END IF;

    -- Gather and insert the field entry data
    PERFORM metabib.reingest_metabib_field_entries(NEW.id);

    -- Located URI magic
    IF TG_OP = 'INSERT' THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    ELSE
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_located_uri' AND enabled;
        IF NOT FOUND THEN
            PERFORM biblio.extract_located_uris( NEW.id, NEW.marc, NEW.editor );
        END IF;
    END IF;

    -- (re)map metarecord-bib linking
    IF TG_OP = 'INSERT' THEN -- if not deleted and performing an insert, check for the flag
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_insert' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    ELSE -- we're doing an update, and we're not deleted, remap
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.metarecord_mapping.skip_on_update' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.remap_metarecord_for_bib( NEW.id, NEW.fingerprint );
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION public.oils_tsearch2 () RETURNS TRIGGER AS $$
DECLARE
    normalizer      RECORD;
    value           TEXT := '';
    temp_vector     TEXT := '';
    ts_rec          RECORD;
    cur_weight      "char";
BEGIN

    value := NEW.value;
    NEW.index_vector = ''::tsvector;

    IF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos < 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;

        NEW.value = value;

        FOR normalizer IN
            SELECT  n.func AS func,
                    n.param_count AS param_count,
                    m.params AS params
              FROM  config.index_normalizer n
                    JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
              WHERE field = NEW.field AND m.pos >= 0
              ORDER BY m.pos LOOP
                EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    quote_literal( value ) ||
                    CASE
                        WHEN normalizer.param_count > 0
                            THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                            ELSE ''
                        END ||
                    ')' INTO value;

        END LOOP;
   END IF;

    IF TG_TABLE_NAME::TEXT ~ 'browse_entry$' THEN

        value :=  ARRAY_TO_STRING(
            evergreen.regexp_split_to_array(value, E'\\W+'), ' '
        );
        value := public.search_normalize(value);
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);

    ELSIF TG_TABLE_NAME::TEXT ~ 'field_entry$' THEN
        FOR ts_rec IN

            SELECT DISTINCT m.ts_config, m.index_weight
            FROM config.metabib_class_ts_map m
                 LEFT JOIN metabib.record_attr_vector_list r ON (r.source = NEW.source)
                 LEFT JOIN config.coded_value_map ccvm ON (
                    ccvm.ctype IN ('item_lang', 'language') AND
                    ccvm.code = m.index_lang AND
                    r.vlist @> intset(ccvm.id)
                )
            WHERE m.field_class = TG_ARGV[0]
                AND m.active
                AND (m.always OR NOT EXISTS (SELECT 1 FROM config.metabib_field_ts_map WHERE metabib_field = NEW.field))
                AND (m.index_lang IS NULL OR ccvm.id IS NOT NULL)
                        UNION
            SELECT DISTINCT m.ts_config, m.index_weight
            FROM config.metabib_field_ts_map m
                 LEFT JOIN metabib.record_attr_vector_list r ON (r.source = NEW.source)
                 LEFT JOIN config.coded_value_map ccvm ON (
                    ccvm.ctype IN ('item_lang', 'language') AND
                    ccvm.code = m.index_lang AND
                    r.vlist @> intset(ccvm.id)
                )
            WHERE m.metabib_field = NEW.field
                AND m.active
                AND (m.index_lang IS NULL OR ccvm.id IS NOT NULL)
            ORDER BY index_weight ASC

        LOOP

            IF cur_weight IS NOT NULL AND cur_weight != ts_rec.index_weight THEN
                NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
                temp_vector = '';
            END IF;

            cur_weight = ts_rec.index_weight;
            SELECT INTO temp_vector temp_vector || ' ' || to_tsvector(ts_rec.ts_config::regconfig, value)::TEXT;

        END LOOP;
        NEW.index_vector = NEW.index_vector || setweight(temp_vector::tsvector,cur_weight);
    ELSE
        NEW.index_vector = to_tsvector(TG_ARGV[0]::regconfig, value);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

-- add new sr_format attribute definition

INSERT INTO config.record_attr_definition (name, label, phys_char_sf)
VALUES (
    'sr_format', 
    oils_i18n_gettext('sr_format', 'Sound recording format', 'crad', 'label'),
    '62'
);

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
(557, 'sr_format', 'a', oils_i18n_gettext(557, '16 rpm', 'ccvm', 'value')),
(558, 'sr_format', 'b', oils_i18n_gettext(558, '33 1/3 rpm', 'ccvm', 'value')),
(559, 'sr_format', 'c', oils_i18n_gettext(559, '45 rpm', 'ccvm', 'value')),
(560, 'sr_format', 'f', oils_i18n_gettext(560, '1.4 m. per second', 'ccvm', 'value')),
(561, 'sr_format', 'd', oils_i18n_gettext(561, '78 rpm', 'ccvm', 'value')),
(562, 'sr_format', 'e', oils_i18n_gettext(562, '8 rpm', 'ccvm', 'value')),
(563, 'sr_format', 'l', oils_i18n_gettext(563, '1 7/8 ips', 'ccvm', 'value')),
(586, 'item_form', 'o', oils_i18n_gettext('586', 'Online', 'ccvm', 'value')),
(587, 'item_form', 'q', oils_i18n_gettext('587', 'Direct electronic', 'ccvm', 'value'));

INSERT INTO config.coded_value_map
    (id, ctype, code, value, search_label) VALUES 
(564, 'icon_format', 'book', 
    oils_i18n_gettext(564, 'Book', 'ccvm', 'value'),
    oils_i18n_gettext(564, 'Book', 'ccvm', 'search_label')),
(565, 'icon_format', 'braille', 
    oils_i18n_gettext(565, 'Braille', 'ccvm', 'value'),
    oils_i18n_gettext(565, 'Braille', 'ccvm', 'search_label')),
(566, 'icon_format', 'software', 
    oils_i18n_gettext(566, 'Software and video games', 'ccvm', 'value'),
    oils_i18n_gettext(566, 'Software and video games', 'ccvm', 'search_label')),
(567, 'icon_format', 'dvd', 
    oils_i18n_gettext(567, 'DVD', 'ccvm', 'value'),
    oils_i18n_gettext(567, 'DVD', 'ccvm', 'search_label')),
(568, 'icon_format', 'ebook', 
    oils_i18n_gettext(568, 'E-book', 'ccvm', 'value'),
    oils_i18n_gettext(568, 'E-book', 'ccvm', 'search_label')),
(569, 'icon_format', 'eaudio', 
    oils_i18n_gettext(569, 'E-audio', 'ccvm', 'value'),
    oils_i18n_gettext(569, 'E-audio', 'ccvm', 'search_label')),
(570, 'icon_format', 'kit', 
    oils_i18n_gettext(570, 'Kit', 'ccvm', 'value'),
    oils_i18n_gettext(570, 'Kit', 'ccvm', 'search_label')),
(571, 'icon_format', 'map', 
    oils_i18n_gettext(571, 'Map', 'ccvm', 'value'),
    oils_i18n_gettext(571, 'Map', 'ccvm', 'search_label')),
(572, 'icon_format', 'microform', 
    oils_i18n_gettext(572, 'Microform', 'ccvm', 'value'),
    oils_i18n_gettext(572, 'Microform', 'ccvm', 'search_label')),
(573, 'icon_format', 'score', 
    oils_i18n_gettext(573, 'Music Score', 'ccvm', 'value'),
    oils_i18n_gettext(573, 'Music Score', 'ccvm', 'search_label')),
(574, 'icon_format', 'picture', 
    oils_i18n_gettext(574, 'Picture', 'ccvm', 'value'),
    oils_i18n_gettext(574, 'Picture', 'ccvm', 'search_label')),
(575, 'icon_format', 'equip', 
    oils_i18n_gettext(575, 'Equipment, games, toys', 'ccvm', 'value'),
    oils_i18n_gettext(575, 'Equipment, games, toys', 'ccvm', 'search_label')),
(576, 'icon_format', 'serial', 
    oils_i18n_gettext(576, 'Serials and magazines', 'ccvm', 'value'),
    oils_i18n_gettext(576, 'Serials and magazines', 'ccvm', 'search_label')),
(577, 'icon_format', 'vhs', 
    oils_i18n_gettext(577, 'VHS', 'ccvm', 'value'),
    oils_i18n_gettext(577, 'VHS', 'ccvm', 'search_label')),
(578, 'icon_format', 'evideo', 
    oils_i18n_gettext(578, 'E-video', 'ccvm', 'value'),
    oils_i18n_gettext(578, 'E-video', 'ccvm', 'search_label')),
(579, 'icon_format', 'cdaudiobook', 
    oils_i18n_gettext(579, 'CD Audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(579, 'CD Audiobook', 'ccvm', 'search_label')),
(580, 'icon_format', 'cdmusic', 
    oils_i18n_gettext(580, 'CD Music recording', 'ccvm', 'value'),
    oils_i18n_gettext(580, 'CD Music recording', 'ccvm', 'search_label')),
(581, 'icon_format', 'casaudiobook', 
    oils_i18n_gettext(581, 'Cassette audiobook', 'ccvm', 'value'),
    oils_i18n_gettext(581, 'Cassette audiobook', 'ccvm', 'search_label')),
(582, 'icon_format', 'casmusic',
    oils_i18n_gettext(582, 'Audiocassette music recording', 'ccvm', 'value'),
    oils_i18n_gettext(582, 'Audiocassette music recording', 'ccvm', 'search_label')),
(583, 'icon_format', 'phonospoken', 
    oils_i18n_gettext(583, 'Phonograph spoken recording', 'ccvm', 'value'),
    oils_i18n_gettext(583, 'Phonograph spoken recording', 'ccvm', 'search_label')),
(584, 'icon_format', 'phonomusic', 
    oils_i18n_gettext(584, 'Phonograph music recording', 'ccvm', 'value'),
    oils_i18n_gettext(584, 'Phonograph music recording', 'ccvm', 'search_label')),
(585, 'icon_format', 'lpbook', 
    oils_i18n_gettext(585, 'Large Print Book', 'ccvm', 'value'),
    oils_i18n_gettext(585, 'Large Print Book', 'ccvm', 'search_label'))
;

-- add the new icon format attribute definition

INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'opac.icon_attr',
    oils_i18n_gettext(
        'opac.icon_attr', 
        'OPAC Format Icons Attribute',
        'cgf',
        'label'
    ),
    'icon_format', 
    TRUE
);

INSERT INTO config.record_attr_definition 
    (name, label, multi, filter, composite) VALUES (
    'icon_format',
    oils_i18n_gettext(
        'icon_format',
        'OPAC Format Icons',
        'crad',
        'label'
    ),
    TRUE, TRUE, TRUE
);

-- icon format composite definitions

INSERT INTO config.composite_attr_entry_definition 
    (coded_value, definition) VALUES
--book
(564, '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":{"_not":[{"_attr":"item_form","_val":"a"},{"_attr":"item_form","_val":"b"},{"_attr":"item_form","_val":"c"},{"_attr":"item_form","_val":"d"},{"_attr":"item_form","_val":"f"},{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"q"},{"_attr":"item_form","_val":"r"},{"_attr":"item_form","_val":"s"}]},"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}'),

-- braille
(565, '{"0":{"_attr":"item_type","_val":"a"},"1":{"_attr":"item_form","_val":"f"}}'),

-- software
(566, '{"_attr":"item_type","_val":"m"}'),

-- dvd
(567, '{"_attr":"vr_format","_val":"v"}'),

-- ebook
(568, '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":[{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"s"},{"_attr":"item_form","_val":"q"}],"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}'),

-- eaudio
(569, '{"0":{"_attr":"item_type","_val":"i"},"1":[{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"q"},{"_attr":"item_form","_val":"s"}]}'),

-- kit
(570, '[{"_attr":"item_type","_val":"o"},{"_attr":"item_type","_val":"p"}]'),

-- map
(571, '[{"_attr":"item_type","_val":"e"},{"_attr":"item_type","_val":"f"}]'),

-- microform
(572, '[{"_attr":"item_form","_val":"a"},{"_attr":"item_form","_val":"b"},{"_attr":"item_form","_val":"c"}]'),

-- score
(573, '[{"_attr":"item_type","_val":"c"},{"_attr":"item_type","_val":"d"}]'),

-- picture
(574, '{"_attr":"item_type","_val":"k"}'),

-- equip
(575, '{"_attr":"item_type","_val":"r"}'),

-- serial
(576, '[{"_attr":"bib_level","_val":"b"},{"_attr":"bib_level","_val":"s"}]'),

-- vhs
(577, '{"_attr":"vr_format","_val":"b"}'),

-- evideo
(578, '{"0":{"_attr":"item_type","_val":"g"},"1":[{"_attr":"item_form","_val":"o"},{"_attr":"item_form","_val":"s"},{"_attr":"item_form","_val":"q"}]}'),

-- cdaudiobook
(579, '{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"sr_format","_val":"f"}}'),

-- cdmusic
(580, '{"0":{"_attr":"item_type","_val":"j"},"1":{"_attr":"sr_format","_val":"f"}}'),

-- casaudiobook
(581, '{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"sr_format","_val":"l"}}'),

-- casmusic
(582, '{"0":{"_attr":"item_type","_val":"j"},"1":{"_attr":"sr_format","_val":"l"}}'),

-- phonospoken
(583, '{"0":{"_attr":"item_type","_val":"i"},"1":[{"_attr":"sr_format","_val":"a"},{"_attr":"sr_format","_val":"b"},{"_attr":"sr_format","_val":"c"},{"_attr":"sr_format","_val":"d"},{"_attr":"sr_format","_val":"e"}]}'),

-- phonomusic
(584, '{"0":{"_attr":"item_type","_val":"j"},"1":[{"_attr":"sr_format","_val":"a"},{"_attr":"sr_format","_val":"b"},{"_attr":"sr_format","_val":"c"},{"_attr":"sr_format","_val":"d"},{"_attr":"sr_format","_val":"e"}]}'),

-- lpbook
(585, '{"0":[{"_attr":"item_type","_val":"a"},{"_attr":"item_type","_val":"t"}],"1":{"_attr":"item_form","_val":"d"},"2":[{"_attr":"bib_level","_val":"a"},{"_attr":"bib_level","_val":"c"},{"_attr":"bib_level","_val":"d"},{"_attr":"bib_level","_val":"m"}]}');




CREATE OR REPLACE FUNCTION unapi.mra (
    obj_id BIGINT,
    format TEXT,
    ename TEXT,
    includes TEXT[],
    org TEXT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    include_xmlns BOOL DEFAULT TRUE
) RETURNS XML AS $F$
    SELECT  XMLELEMENT(
        name attributes,
        XMLATTRIBUTES(
            CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
            'tag:open-ils.org:U2@mra/' || $1 AS id, 
            'tag:open-ils.org:U2@bre/' || $1 AS record 
        ),  
        (SELECT XMLAGG(foo.y)
          FROM (
            SELECT  XMLELEMENT(
                        name field,
                        XMLATTRIBUTES(
                            mra.attr AS name,
                            cvm.value AS "coded-value",
                            cvm.id AS "cvmid",
                            rad.composite,
                            rad.multi,
                            rad.filter,
                            rad.sorter
                        ),
                        mra.value
                    )
              FROM  metabib.record_attr_flat mra
                    JOIN config.record_attr_definition rad ON (mra.attr = rad.name)
                    LEFT JOIN config.coded_value_map cvm ON (cvm.ctype = mra.attr AND code = mra.value)
              WHERE mra.id = $1
            )foo(y)
        )   
    )   
$F$ LANGUAGE SQL STABLE;

COMMIT;
\qecho 'We dropped reporter.classic_current_circ earlier from the'
\qecho 'example.reporter-extension.sql sample. You will need to'
\qecho 'run it again to recreate that custom reporter view.'
