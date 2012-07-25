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

CREATE OR REPLACE FUNCTION public.first_word ( TEXT ) RETURNS TEXT AS $$
        SELECT COALESCE(SUBSTRING( $1 FROM $_$^\S+$_$), '');
$$ LANGUAGE SQL STRICT IMMUTABLE;

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
    SELECT ou.* FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad USING (id) ORDER BY ouad.distance DESC;
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

-- Given the IDs of two rows in actor.org_unit, *the second being an ancestor
-- of the first*, return in array form the path from the ancestor to the
-- descendant, with each point in the path being an org_unit ID.  This is
-- useful for sorting org_units by their position in a depth-first (display
-- order) representation of the tree.
--
-- This breaks with the precedent set by actor.org_unit_full_path() and others,
-- and gets the parameters "backwards," but otherwise this function would
-- not be very usable within json_query.
CREATE OR REPLACE FUNCTION actor.org_unit_simple_path(INT, INT)
RETURNS INT[] AS $$
    WITH RECURSIVE descendant_depth(id, path) AS (
        SELECT  aou.id,
                ARRAY[aou.id]
          FROM  actor.org_unit aou
                JOIN actor.org_unit_type aout ON (aout.id = aou.ou_type)
          WHERE aou.id = $2
            UNION ALL
        SELECT  aou.id,
                dd.path || ARRAY[aou.id]
          FROM  actor.org_unit aou
                JOIN actor.org_unit_type aout ON (aout.id = aou.ou_type)
                JOIN descendant_depth dd ON (dd.id = aou.parent_ou)
    ) SELECT dd.path
        FROM actor.org_unit aou
        JOIN descendant_depth dd USING (id)
        WHERE aou.id = $1 ORDER BY dd.path;
$$ LANGUAGE SQL STABLE;

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

CREATE OR REPLACE FUNCTION evergreen.get_barcodes(select_ou INT, type TEXT, in_barcode TEXT) RETURNS SETOF evergreen.barcode_set AS $$
DECLARE
    cur_barcode TEXT;
    barcode_len INT;
    completion_len  INT;
    asset_barcodes  TEXT[];
    actor_barcodes  TEXT[];
    do_asset    BOOL = false;
    do_serial   BOOL = false;
    do_booking  BOOL = false;
    do_actor    BOOL = false;
    completion_set  config.barcode_completion%ROWTYPE;
BEGIN

    IF position('asset' in type) > 0 THEN
        do_asset = true;
    END IF;
    IF position('serial' in type) > 0 THEN
        do_serial = true;
    END IF;
    IF position('booking' in type) > 0 THEN
        do_booking = true;
    END IF;
    IF do_asset OR do_serial OR do_booking THEN
        asset_barcodes = asset_barcodes || in_barcode;
    END IF;
    IF position('actor' in type) > 0 THEN
        do_actor = true;
        actor_barcodes = actor_barcodes || in_barcode;
    END IF;

    barcode_len := length(in_barcode);

    FOR completion_set IN
      SELECT * FROM config.barcode_completion
        WHERE active
        AND org_unit IN (SELECT aou.id FROM actor.org_unit_ancestors(select_ou) aou)
        LOOP
        IF completion_set.prefix IS NULL THEN
            completion_set.prefix := '';
        END IF;
        IF completion_set.suffix IS NULL THEN
            completion_set.suffix := '';
        END IF;
        IF completion_set.length = 0 OR completion_set.padding IS NULL OR length(completion_set.padding) = 0 THEN
            cur_barcode = completion_set.prefix || in_barcode || completion_set.suffix;
        ELSE
            completion_len = completion_set.length - length(completion_set.prefix) - length(completion_set.suffix);
            IF completion_len >= barcode_len THEN
                IF completion_set.padding_end THEN
                    cur_barcode = rpad(in_barcode, completion_len, completion_set.padding);
                ELSE
                    cur_barcode = lpad(in_barcode, completion_len, completion_set.padding);
                END IF;
                cur_barcode = completion_set.prefix || cur_barcode || completion_set.suffix;
            END IF;
        END IF;
        IF completion_set.actor THEN
            actor_barcodes = actor_barcodes || cur_barcode;
        END IF;
        IF completion_set.asset THEN
            asset_barcodes = asset_barcodes || cur_barcode;
        END IF;
    END LOOP;

    IF do_asset AND do_serial THEN
        RETURN QUERY SELECT 'asset'::TEXT, id, barcode FROM ONLY asset.copy WHERE barcode = ANY(asset_barcodes) AND deleted = false;
        RETURN QUERY SELECT 'serial'::TEXT, id, barcode FROM serial.unit WHERE barcode = ANY(asset_barcodes) AND deleted = false;
    ELSIF do_asset THEN
        RETURN QUERY SELECT 'asset'::TEXT, id, barcode FROM asset.copy WHERE barcode = ANY(asset_barcodes) AND deleted = false;
    ELSIF do_serial THEN
        RETURN QUERY SELECT 'serial'::TEXT, id, barcode FROM serial.unit WHERE barcode = ANY(asset_barcodes) AND deleted = false;
    END IF;
    IF do_booking THEN
        RETURN QUERY SELECT 'booking'::TEXT, id::BIGINT, barcode FROM booking.resource WHERE barcode = ANY(asset_barcodes);
    END IF;
    IF do_actor THEN
        RETURN QUERY SELECT 'actor'::TEXT, c.usr::BIGINT, c.barcode FROM actor.card c JOIN actor.usr u ON c.usr = u.id WHERE c.barcode = ANY(actor_barcodes) AND c.active AND NOT u.deleted ORDER BY usr;
    END IF;
    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION evergreen.get_barcodes(INT, TEXT, TEXT) IS $$
Given user input, find an appropriate barcode in the proper class.

Will add prefix/suffix information to do so, and return all results.
$$;

CREATE OR REPLACE FUNCTION actor.org_unit_prox_update () RETURNS TRIGGER as $$
BEGIN


IF TG_OP = 'DELETE' THEN

    DELETE FROM actor.org_unit_proximity WHERE (from_org = OLD.id or to_org= OLD.id);

END IF;

IF TG_OP = 'UPDATE' THEN

    IF NEW.parent_ou <> OLD.parent_ou THEN

        DELETE FROM actor.org_unit_proximity WHERE (from_org = OLD.id or to_org= OLD.id);
            INSERT INTO actor.org_unit_proximity (from_org, to_org, prox)
            SELECT  l.id, r.id, actor.org_unit_proximity(l.id,r.id)
                FROM  actor.org_unit l, actor.org_unit r
                WHERE (l.id = NEW.id or r.id = NEW.id);

    END IF;

END IF;

IF TG_OP = 'INSERT' THEN

     INSERT INTO actor.org_unit_proximity (from_org, to_org, prox)
     SELECT  l.id, r.id, actor.org_unit_proximity(l.id,r.id)
         FROM  actor.org_unit l, actor.org_unit r
         WHERE (l.id = NEW.id or r.id = NEW.id);

END IF;

RETURN null;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER proximity_update_tgr AFTER INSERT OR UPDATE OR DELETE ON actor.org_unit FOR EACH ROW EXECUTE PROCEDURE actor.org_unit_prox_update ();

CREATE OR REPLACE FUNCTION evergreen.get_locale_name(
    IN locale TEXT,
    OUT name TEXT,
    OUT description TEXT
) AS $$
DECLARE
    eg_locale TEXT;
BEGIN
    eg_locale := LOWER(SUBSTRING(locale FROM 1 FOR 2)) || '-' || UPPER(SUBSTRING(locale FROM 4 FOR 2));
        
    SELECT i18nc.string INTO name
    FROM config.i18n_locale i18nl
       INNER JOIN config.i18n_core i18nc ON i18nl.code = i18nc.translation
    WHERE i18nc.identity_value = eg_locale
       AND code = eg_locale
       AND i18nc.fq_field = 'i18n_l.name';

    IF name IS NULL THEN
       SELECT i18nl.name INTO name
       FROM config.i18n_locale i18nl
       WHERE code = eg_locale;
    END IF;

    SELECT i18nc.string INTO description
    FROM config.i18n_locale i18nl
       INNER JOIN config.i18n_core i18nc ON i18nl.code = i18nc.translation
    WHERE i18nc.identity_value = eg_locale
       AND code = eg_locale
       AND i18nc.fq_field = 'i18n_l.description';

    IF description IS NULL THEN
       SELECT i18nl.description INTO description
       FROM config.i18n_locale i18nl
       WHERE code = eg_locale;
    END IF;
END;
$$ LANGUAGE PLPGSQL COST 1 STABLE;
