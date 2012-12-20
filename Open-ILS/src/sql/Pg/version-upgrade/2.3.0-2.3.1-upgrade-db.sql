--Upgrade Script for 2.3.0 to 2.3.1
\set eg_version '''2.3.1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.3.1', :eg_version);

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
