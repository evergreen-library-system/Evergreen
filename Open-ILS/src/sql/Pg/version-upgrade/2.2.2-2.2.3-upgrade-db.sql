--Upgrade Script for 2.2.2 to 2.2.3
\set eg_version '''2.2.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.2.3', :eg_version);

-- 0738.schema.vandelay.import-match-no-like-any.sql

SELECT evergreen.upgrade_deps_block_check('0738', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.match_set_test_marcxml(
    match_set_id INTEGER, record_xml TEXT
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
    SELECT ARRAY_TO_STRING(
        ARRAY_ACCUM('COALESCE(n' || q::TEXT || '.quality, 0)'), ' + '
    ) INTO coal FROM _vandelay_tmp_qrows;

    -- our query string so far is the SELECT clause and the inital FROM.
    -- no JOINs yet nor the WHERE clause
    query_ := query_ || coal || ' AS quality ' || E'\n';

    -- jrows table is for the joins we must make (and the real text conditions)
    SELECT ARRAY_TO_STRING(ARRAY_ACCUM(j), E'\n') INTO joins
        FROM _vandelay_tmp_jrows;

    -- add those joins and the where clause to our query.
    query_ := query_ || joins || E'\n' || 'JOIN biblio.record_entry bre ON (bre.id = record) ' || 'WHERE ' || wq || ' AND not bre.deleted';

    -- this will return rows of record,quality
    FOR rec IN EXECUTE query_ USING tags_rstore, svf_rstore LOOP
        RETURN NEXT rec;
    END LOOP;

    DROP TABLE _vandelay_tmp_qrows;
    DROP TABLE _vandelay_tmp_jrows;
    RETURN;
END;

$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set(
    match_set_id INTEGER,
    tags_rstore HSTORE
) RETURNS TEXT AS $$
DECLARE
    root    vandelay.match_set_point;
BEGIN
    SELECT * INTO root FROM vandelay.match_set_point
        WHERE parent IS NULL AND match_set = match_set_id;

    RETURN vandelay.get_expr_from_match_set_point(root, tags_rstore);
END;
$$  LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay.get_expr_from_match_set_point(
    node vandelay.match_set_point,
    tags_rstore HSTORE
) RETURNS TEXT AS $$
DECLARE
    q           TEXT;
    i           INTEGER;
    this_op     TEXT;
    children    INTEGER[];
    child       vandelay.match_set_point;
BEGIN
    SELECT ARRAY_ACCUM(id) INTO children FROM vandelay.match_set_point
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
            q := q || vandelay.get_expr_from_match_set_point(child, tags_rstore);
        END LOOP;
        q := q || ')';
        RETURN q;
    ELSIF node.bool_op IS NULL THEN
        PERFORM vandelay._get_expr_push_qrow(node);
        PERFORM vandelay._get_expr_push_jrow(node, tags_rstore);
        RETURN vandelay._get_expr_render_one(node);
    ELSE
        RETURN '';
    END IF;
END;
$$  LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION vandelay._get_expr_push_jrow(
    node vandelay.match_set_point,
    tags_rstore HSTORE
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
BEGIN
    -- remember $1 is tags_rstore, and $2 is svf_rstore

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
            ' AS quality FROM metabib.full_rec mfr WHERE mfr.tag = ''' ||
            node.tag || '''';
        IF node.subfield IS NOT NULL THEN
            jrow := jrow || ' AND mfr.subfield = ''' ||
                node.subfield || '''';
        END IF;
        jrow := jrow || ' AND (';
        jrow := jrow || vandelay._node_tag_comparisons(caseless, op, tags_rstore, tagkey);
        jrow := jrow || ')) ' || my_alias || my_using || E'\n';
    ELSE    -- svf
        jrow := jrow || 'id AS record, ' || node.quality ||
            ' AS quality FROM metabib.record_attr mra WHERE mra.attrs->''' ||
            node.svf || ''' ' || op || ' $2->''' || node.svf || ''') ' ||
            my_alias || my_using || E'\n';
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

-- drop old versions of these functions with fewer args
DROP FUNCTION vandelay.get_expr_from_match_set( INTEGER );
DROP FUNCTION vandelay.get_expr_from_match_set_point( vandelay.match_set_point );
DROP FUNCTION vandelay._get_expr_push_jrow( vandelay.match_set_point );

-- This next index might fully supplant an existing one but leaving both for now
-- (they are not too large)
-- The reason we need this index is to ensure that the query parser always
-- prefers this index over the simpler tag/subfield index, as this greatly
-- increases Vandelay overlay speed for these identifiers, especially when
-- a record has many of these fields (around > 4-6 seems like the cutoff
-- on at least one PG9.1 system)
-- A similar index could be added for other fields (e.g. 010), but one should
-- leave out the LOWER() in all other cases.
-- TODO: verify whether we can discard the non tag/subfield/substring version
-- (metabib_full_rec_isxn_caseless_idx)
CREATE INDEX metabib_full_rec_02x_tag_subfield_lower_substring
    ON metabib.real_full_rec (tag, subfield, LOWER(substring(value, 1, 1024)))
    WHERE tag IN ('020', '022', '024');



SELECT evergreen.upgrade_deps_block_check('0740', :eg_version);

CREATE OR REPLACE
    FUNCTION metabib.suggest_browse_entries(
        raw_query_text  TEXT,   -- actually typed by humans at the UI level
        search_class    TEXT,   -- 'alias' or 'class' or 'class|field..', etc
        headline_opts   TEXT,   -- markup options for ts_headline()
        visibility_org  INTEGER,-- null if you don't want opac visibility test
        query_limit     INTEGER,-- use in LIMIT clause of interal query
        normalization   INTEGER -- argument to TS_RANK_CD()
    ) RETURNS TABLE (
        value                   TEXT,   -- plain
        field                   INTEGER,
        buoyant_and_class_match BOOL,
        field_match             BOOL,
        field_weight            INTEGER,
        rank                    REAL,
        buoyant                 BOOL,
        match                   TEXT    -- marked up
    ) AS $func$
DECLARE
    prepared_query_texts    TEXT[];
    query                   TSQUERY;
    plain_query             TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
BEGIN
    prepared_query_texts := metabib.autosuggest_prepare_tsquery(raw_query_text);

    query := TO_TSQUERY('keyword', prepared_query_texts[1]);
    plain_query := TO_TSQUERY('keyword', prepared_query_texts[2]);

    visibility_org := NULLIF(visibility_org,-1);
    IF visibility_org IS NOT NULL THEN
        opac_visibility_join := '
    JOIN asset.opac_visible_copies aovc ON (
        aovc.record = x.source AND
        aovc.circ_lib IN (SELECT id FROM actor.org_unit_descendants($4))
    )';
    ELSE
        opac_visibility_join := '';
    END IF;

    -- The following determines whether we only provide suggestsons matching
    -- the user's selected search_class, or whether we show other suggestions
    -- too. The reason for MIN() is that for search_classes like
    -- 'title|proper|uniform' you would otherwise get multiple rows.  The
    -- implication is that if title as a class doesn't have restrict,
    -- nor does the proper field, but the uniform field does, you're going
    -- to get 'false' for your overall evaluation of 'should we restrict?'
    -- To invert that, change from MIN() to MAX().

    SELECT
        INTO r_fields
            MIN(cmc.restrict::INT) AS restrict_class,
            MIN(cmf.restrict::INT) AS restrict_field
        FROM metabib.search_class_to_registered_components(search_class)
            AS _registered (field_class TEXT, field INT)
        JOIN
            config.metabib_class cmc ON (cmc.name = _registered.field_class)
        LEFT JOIN
            config.metabib_field cmf ON (cmf.id = _registered.field);

    -- evaluate 'should we restrict?'
    IF r_fields.restrict_field::BOOL OR r_fields.restrict_class::BOOL THEN
        search_class_join := '
    JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            (_registered.field IS NULL AND
                _registered.field_class = cmf.field_class) OR
            (_registered.field = cmf.id)
        )
    ';
    ELSE
        search_class_join := '
    LEFT JOIN
        metabib.search_class_to_registered_components($2)
        AS _registered (field_class TEXT, field INT) ON (
            _registered.field_class = cmc.name
        )
    ';
    END IF;

    RETURN QUERY EXECUTE '
SELECT  DISTINCT
        x.value,
        x.id,
        x.push,
        x.restrict,
        x.weight,
        x.ts_rank_cd,
        x.buoyant,
        TS_HEADLINE(value, $7, $3)
  FROM  (SELECT DISTINCT
                mbe.value,
                cmf.id,
                cmc.buoyant AND _registered.field_class IS NOT NULL AS push,
                _registered.field = cmf.id AS restrict,
                cmf.weight,
                TS_RANK_CD(mbe.index_vector, $1, $6),
                cmc.buoyant,
                mbedm.source
          FROM  metabib.browse_entry_def_map mbedm
                JOIN (SELECT * FROM metabib.browse_entry WHERE index_vector @@ $1 LIMIT 10000) mbe ON (mbe.id = mbedm.entry)
                JOIN config.metabib_field cmf ON (cmf.id = mbedm.def)
                JOIN config.metabib_class cmc ON (cmf.field_class = cmc.name)
                '  || search_class_join || '
          ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
          LIMIT 1000) AS x
        ' || opac_visibility_join || '
  ORDER BY 3 DESC, 4 DESC NULLS LAST, 5 DESC, 6 DESC, 7 DESC, 1 ASC
  LIMIT $5
'   -- sic, repeat the order by clause in the outer select too
    USING
        query, search_class, headline_opts,
        visibility_org, query_limit, normalization, plain_query
        ;

    -- sort order:
    --  buoyant AND chosen class = match class
    --  chosen field = match field
    --  field weight
    --  rank
    --  buoyancy
    --  value itself

END;
$func$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('0742', :eg_version);

-- Prepare for the July 2013 introduction of OCLC's "on" prefix
-- Per LP# 1049171

CREATE OR REPLACE FUNCTION maintain_control_numbers() RETURNS TRIGGER AS $func$
use strict;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use Encode;
use Unicode::Normalize;

MARC::Charset->assume_unicode(1);

my $record = MARC::Record->new_from_xml($_TD->{new}{marc});
my $schema = $_TD->{table_schema};
my $rec_id = $_TD->{new}{id};

# Short-circuit if maintaining control numbers per MARC21 spec is not enabled
my $enable = spi_exec_query("SELECT enabled FROM config.global_flag WHERE name = 'cat.maintain_control_numbers'");
if (!($enable->{processed}) or $enable->{rows}[0]->{enabled} eq 'f') {
    return;
}

# Get the control number identifier from an OU setting based on $_TD->{new}{owner}
my $ou_cni = 'EVRGRN';

my $owner;
if ($schema eq 'serial') {
    $owner = $_TD->{new}{owning_lib};
} else {
    # are.owner and bre.owner can be null, so fall back to the consortial setting
    $owner = $_TD->{new}{owner} || 1;
}

my $ous_rv = spi_exec_query("SELECT value FROM actor.org_unit_ancestor_setting('cat.marc_control_number_identifier', $owner)");
if ($ous_rv->{processed}) {
    $ou_cni = $ous_rv->{rows}[0]->{value};
    $ou_cni =~ s/"//g; # Stupid VIM syntax highlighting"
} else {
    # Fall back to the shortname of the OU if there was no OU setting
    $ous_rv = spi_exec_query("SELECT shortname FROM actor.org_unit WHERE id = $owner");
    if ($ous_rv->{processed}) {
        $ou_cni = $ous_rv->{rows}[0]->{shortname};
    }
}

my ($create, $munge) = (0, 0);

my @scns = $record->field('035');

foreach my $id_field ('001', '003') {
    my $spec_value;
    my @controls = $record->field($id_field);

    if ($id_field eq '001') {
        $spec_value = $rec_id;
    } else {
        $spec_value = $ou_cni;
    }

    # Create the 001/003 if none exist
    if (scalar(@controls) == 1) {
        # Only one field; check to see if we need to munge it
        unless (grep $_->data() eq $spec_value, @controls) {
            $munge = 1;
        }
    } else {
        # Delete the other fields, as with more than 1 001/003 we do not know which 003/001 to match
        foreach my $control (@controls) {
            $record->delete_field($control);
        }
        $record->insert_fields_ordered(MARC::Field->new($id_field, $spec_value));
        $create = 1;
    }
}

my $cn = $record->field('001')->data();
# Special handling of OCLC numbers, often found in records that lack 003
if ($cn =~ /^o(c[nm]|n)\d/) {
    $cn =~ s/^o(c[nm]|n)0*(\d+)/$2/;
    $record->field('003')->data('OCoLC');
    $create = 0;
}

# Now, if we need to munge the 001, we will first push the existing 001/003
# into the 035; but if the record did not have one (and one only) 001 and 003
# to begin with, skip this process
if ($munge and not $create) {

    my $scn = "(" . $record->field('003')->data() . ")" . $cn;

    # Do not create duplicate 035 fields
    unless (grep $_->subfield('a') eq $scn, @scns) {
        $record->insert_fields_ordered(MARC::Field->new('035', '', '', 'a' => $scn));
    }
}

# Set the 001/003 and update the MARC
if ($create or $munge) {
    $record->field('001')->data($rec_id);
    $record->field('003')->data($ou_cni);

    my $xml = $record->as_xml_record();
    $xml =~ s/\n//sgo;
    $xml =~ s/^<\?xml.+\?\s*>//go;
    $xml =~ s/>\s+</></go;
    $xml =~ s/\p{Cc}//go;

    # Embed a version of OpenILS::Application::AppUtils->entityize()
    # to avoid having to set PERL5LIB for PostgreSQL as well

    # If we are going to convert non-ASCII characters to XML entities,
    # we had better be dealing with a UTF8 string to begin with
    $xml = decode_utf8($xml);

    $xml = NFC($xml);

    # Convert raw ampersands to entities
    $xml =~ s/&(?!\S+;)/&amp;/gso;

    # Convert Unicode characters to entities
    $xml =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

    $xml =~ s/[\x00-\x1f]//go;
    $_TD->{new}{marc} = $xml;

    return "MODIFY";
}

return;
$func$ LANGUAGE PLPERLU;

COMMIT;
