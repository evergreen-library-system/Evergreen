/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

CREATE OR REPLACE FUNCTION public.non_filing_normalize ( TEXT, "char" ) RETURNS TEXT AS $$
        SELECT  SUBSTRING(
                        REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                        $1,
                                        E'\W*$',
					''
				),
                                '  ',
                                ' '
                        ),
                        CASE
				WHEN $2::INT NOT BETWEEN 48 AND 57 THEN 1
				ELSE $2::TEXT::INT + 1
			END
		);
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$

    use strict;
    use Unicode::Normalize;
    use Encode;

    my $str = decode_utf8(shift);
    my $sf = shift;

    # Apply NACO normalization to input string; based on
    # http://www.loc.gov/catdir/pcc/naco/SCA_PccNormalization_Final_revised.pdf
    #
    # Note that unlike a strict reading of the NACO normalization rules,
    # output is returned as lowercase instead of uppercase for compatibility
    # with previous versions of the Evergreen naco_normalize routine.

    # Convert to upper-case first; even though final output will be lowercase, doing this will
    # ensure that the German eszett (ß) and certain ligatures (ﬀ, ﬁ, ﬄ, etc.) will be handled correctly.
    # If there are any bugs in Perl's implementation of upcasing, they will be passed through here.
    $str = uc $str;

    # remove non-filing strings
    $str =~ s/\x{0098}.*?\x{009C}//g;

    $str = NFKD($str);

    # additional substitutions - 3.6.
    $str =~ s/\x{00C6}/AE/g;
    $str =~ s/\x{00DE}/TH/g;
    $str =~ s/\x{0152}/OE/g;
    $str =~ tr/\x{0110}\x{00D0}\x{00D8}\x{0141}\x{2113}\x{02BB}\x{02BC}]['/DDOLl/d;

    # transformations based on Unicode category codes
    $str =~ s/[\p{Cc}\p{Cf}\p{Co}\p{Cs}\p{Lm}\p{Mc}\p{Me}\p{Mn}]//g;

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($str, ',');
		if ($commapos > -1) {
			if ($commapos != length($str) - 1) {
                $str =~ s/,/\x07/; # preserve first comma
			}
		}
	}

    # since we've stripped out the control characters, we can now
    # use a few as placeholders temporarily
    $str =~ tr/+&@\x{266D}\x{266F}#/\x01\x02\x03\x04\x05\x06/;
    $str =~ s/[\p{Pc}\p{Pd}\p{Pe}\p{Pf}\p{Pi}\p{Po}\p{Ps}\p{Sk}\p{Sm}\p{So}\p{Zl}\p{Zp}\p{Zs}]/ /g;
    $str =~ tr/\x01\x02\x03\x04\x05\x06\x07/+&@\x{266D}\x{266F}#,/;

    # decimal digits
    $str =~ tr/\x{0660}-\x{0669}\x{06F0}-\x{06F9}\x{07C0}-\x{07C9}\x{0966}-\x{096F}\x{09E6}-\x{09EF}\x{0A66}-\x{0A6F}\x{0AE6}-\x{0AEF}\x{0B66}-\x{0B6F}\x{0BE6}-\x{0BEF}\x{0C66}-\x{0C6F}\x{0CE6}-\x{0CEF}\x{0D66}-\x{0D6F}\x{0E50}-\x{0E59}\x{0ED0}-\x{0ED9}\x{0F20}-\x{0F29}\x{1040}-\x{1049}\x{1090}-\x{1099}\x{17E0}-\x{17E9}\x{1810}-\x{1819}\x{1946}-\x{194F}\x{19D0}-\x{19D9}\x{1A80}-\x{1A89}\x{1A90}-\x{1A99}\x{1B50}-\x{1B59}\x{1BB0}-\x{1BB9}\x{1C40}-\x{1C49}\x{1C50}-\x{1C59}\x{A620}-\x{A629}\x{A8D0}-\x{A8D9}\x{A900}-\x{A909}\x{A9D0}-\x{A9D9}\x{AA50}-\x{AA59}\x{ABF0}-\x{ABF9}\x{FF10}-\x{FF19}/0-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-90-9/;

    # intentionally skipping step 8 of the NACO algorithm; if the string
    # gets normalized away, that's fine.

    # leading and trailing spaces
    $str =~ s/\s+/ /g;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//g;

    return lc $str;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT ) RETURNS TEXT AS $func$
	SELECT public.naco_normalize($1,'');
$func$ LANGUAGE 'sql' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.first_word ( TEXT ) RETURNS TEXT AS $$
        SELECT COALESCE(SUBSTRING( $1 FROM $_$^\S+$_$), '');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.naco_normalize_keep_comma( TEXT ) RETURNS TEXT AS $func$
        SELECT public.naco_normalize($1,'a');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.normalize_space( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(regexp_replace(regexp_replace($1, E'\\n', ' ', 'g'), E'(?:^\\s+)|(\\s+$)', '', 'g'), E'\\s+', ' ', 'g');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.remove_commas( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace($1, ',', '', 'g');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.remove_paren_substring( TEXT ) RETURNS TEXT AS $func$
    SELECT regexp_replace($1, $$\([^)]+\)$$, '', 'g');
$func$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.remove_whitespace( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(normalize_space($1), E'\\s+', '', 'g');
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.uppercase( TEXT ) RETURNS TEXT AS $$
    return uc(shift);
$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.remove_diacritics( TEXT ) RETURNS TEXT AS $$
    use Unicode::Normalize;

    my $x = NFD(shift);
    $x =~ s/\pM+//go;
    return $x;

$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.entityize( TEXT ) RETURNS TEXT AS $$
    use Unicode::Normalize;

    my $x = NFC(shift);
    $x =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
    return $x;

$$ LANGUAGE PLPERLU STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.call_number_dewey( TEXT ) RETURNS TEXT AS $$
	my $txt = shift;
	$txt =~ s/^\s+//o;
	$txt =~ s/[\[\]\{\}\(\)`'"#<>\*\?\-\+\$\\]+//og;
	$txt =~ s/\s+$//o;
	if ($txt =~ /(\d{3}(?:\.\d+)?)/o) {
		return $1;
	} else {
		return (split /\s+/, $txt)[0];
	}
$$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.call_number_dewey( TEXT, INT ) RETURNS TEXT AS $$
	SELECT SUBSTRING(call_number_dewey($1) FROM 1 FOR $2);
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION tableoid2name ( oid ) RETURNS TEXT AS $$
	BEGIN
		RETURN $1::regclass;
	END;
$$ language 'plpgsql';

CREATE OR REPLACE FUNCTION actor.org_unit_descendants( INT, INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ad ON (ad.id = ou.id)
          WHERE ad.depth = $2
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ), anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
          WHERE ou.id = $1
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ) SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id);
$$ LANGUAGE SQL ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_descendants( INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
          WHERE ou.id = $1
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
          FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ) SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id);
$$ LANGUAGE SQL ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_descendants_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_descendants_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.id, oudd.distance+1
            FROM actor.org_unit ou JOIN org_unit_descendants_distance oudd ON (ou.parent_ou = oudd.id)
    )
    SELECT * FROM org_unit_descendants_distance;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors( INT ) RETURNS SETOF actor.org_unit AS $$
    WITH RECURSIVE org_unit_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent_ou, ouad.distance+1
            FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad ON (ou.id = ouad.id)
            WHERE ou.parent_ou IS NOT NULL
    )
    SELECT ou.* FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad USING (id) ORDER BY ouad.distance;
$$ LANGUAGE SQL ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_at_depth ( INT,INT ) RETURNS actor.org_unit AS $$
	SELECT	a.*
	  FROM	actor.org_unit a
	  WHERE	id = ( SELECT FIRST(x.id)
	  		 FROM	actor.org_unit_ancestors($1) x
			   	JOIN actor.org_unit_type y
					ON x.ou_type = y.id AND y.depth = $2);
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent_ou, ouad.distance+1
            FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad ON (ou.id = ouad.id)
            WHERE ou.parent_ou IS NOT NULL
    )
    SELECT * FROM org_unit_ancestors_distance;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_full_path ( INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	*
	  FROM	actor.org_unit_ancestors($1)
			UNION
	SELECT	*
	  FROM	actor.org_unit_descendants($1);
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_full_path ( INT, INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	* FROM actor.org_unit_full_path((actor.org_unit_ancestor_at_depth($1, $2)).id)
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_combined_ancestors ( INT, INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	*
	  FROM	actor.org_unit_ancestors($1)
			UNION
	SELECT	*
	  FROM	actor.org_unit_ancestors($2);
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_common_ancestors ( INT, INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	*
	  FROM	actor.org_unit_ancestors($1)
			INTERSECT
	SELECT	*
	  FROM	actor.org_unit_ancestors($2);
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION actor.org_unit_proximity ( INT, INT ) RETURNS INT AS $$
	SELECT COUNT(id)::INT FROM (
		SELECT id FROM actor.org_unit_combined_ancestors($1, $2)
			EXCEPT
		SELECT id FROM actor.org_unit_common_ancestors($1, $2)
	) z;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION actor.org_unit_ancestor_setting( setting_name TEXT, org_id INT ) RETURNS SETOF actor.org_unit_setting AS $$
DECLARE
    setting RECORD;
    cur_org INT;
BEGIN
    cur_org := org_id;
    LOOP
        SELECT INTO setting * FROM actor.org_unit_setting WHERE org_unit = cur_org AND name = setting_name;
        IF FOUND THEN
            RETURN NEXT setting;
            EXIT;
        END IF;
        SELECT INTO cur_org parent_ou FROM actor.org_unit WHERE id = cur_org;
        EXIT WHEN cur_org IS NULL;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql STABLE ROWS 1;

COMMENT ON FUNCTION actor.org_unit_ancestor_setting( TEXT, INT) IS $$
Search "up" the org_unit tree until we find the first occurrence of an 
org_unit_setting with the given name.
$$;

-- Intended to be used in a unique index on authority.record_entry like so:
-- CREATE UNIQUE INDEX unique_by_heading_and_thesaurus
--   ON authority.record_entry (authority.normalize_heading(marc))
--   WHERE deleted IS FALSE or deleted = FALSE;
CREATE OR REPLACE FUNCTION authority.normalize_heading( TEXT ) RETURNS TEXT AS $func$
    use strict;
    use warnings;

    use utf8;
    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF8');
    use MARC::Charset;
    use UUID::Tiny ':std';

    MARC::Charset->assume_unicode(1);

    my $xml = shift() or return undef;

    my $r;

    # Prevent errors in XML parsing from blowing out ungracefully
    eval {
        $r = MARC::Record->new_from_xml( $xml );
        1;
    } or do {
       return 'BAD_MARCXML_' . create_uuid_as_string(UUID_MD5, $xml);
    };

    if (!$r) {
       return 'BAD_MARCXML_' . create_uuid_as_string(UUID_MD5, $xml);
    }

    # From http://www.loc.gov/standards/sourcelist/subject.html
    my $thes_code_map = {
        a => 'lcsh',
        b => 'lcshac',
        c => 'mesh',
        d => 'nal',
        k => 'cash',
        n => 'notapplicable',
        r => 'aat',
        s => 'sears',
        v => 'rvm',
    };

    # Default to "No attempt to code" if the leader is horribly broken
    my $fixed_field = $r->field('008');
    my $thes_char = '|';
    if ($fixed_field) { 
        $thes_char = substr($fixed_field->data(), 11, 1) || '|';
    }

    my $thes_code = 'UNDEFINED';

    if ($thes_char eq 'z') {
        # Grab the 040 $f per http://www.loc.gov/marc/authority/ad040.html
        $thes_code = $r->subfield('040', 'f') || 'UNDEFINED';
    } elsif ($thes_code_map->{$thes_char}) {
        $thes_code = $thes_code_map->{$thes_char};
    }

    my $auth_txt = '';
    my $head = $r->field('1..');
    if ($head) {
        # Concatenate all of these subfields together, prefixed by their code
        # to prevent collisions along the lines of "Fiction, North Carolina"
        foreach my $sf ($head->subfields()) {
            $auth_txt .= '‡' . $sf->[0] . ' ' . $sf->[1];
        }
    }
    
    if ($auth_txt) {
        my $stmt = spi_prepare('SELECT public.naco_normalize($1) AS norm_text', 'TEXT');
        my $result = spi_exec_prepared($stmt, $auth_txt);
        my $norm_txt = $result->{rows}[0]->{norm_text};
        spi_freeplan($stmt);
        undef($stmt);
        return $head->tag() . "_" . $thes_code . " " . $norm_txt;
    }

    return 'NOHEADING_' . $thes_code . ' ' . create_uuid_as_string(UUID_MD5, $xml);
$func$ LANGUAGE 'plperlu' IMMUTABLE;

COMMENT ON FUNCTION authority.normalize_heading( TEXT ) IS $$
Extract the authority heading, thesaurus, and NACO-normalized values
from an authority record. The primary purpose is to build a unique
index to defend against duplicated authority records from the same
thesaurus.
$$;
