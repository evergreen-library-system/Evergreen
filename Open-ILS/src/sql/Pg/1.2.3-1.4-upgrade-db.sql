/*
 * Copyright (C) 2008  Equinox Software, Inc.
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

/* Need to run 953.data.MODS32-xsl.sql after running this */


BEGIN;

CREATE TABLE config.upgrade_log (
    version         TEXT    PRIMARY KEY,
    install_date    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);
INSERT INTO config.upgrade_log (version) VALUES ('1.4.0.0rc2');

SELECT set_curcfg('default');

CREATE OR REPLACE FUNCTION public.extract_marc_field ( TEXT, BIGINT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(array_to_string( array_accum( output ),' ' ),$4,'','g') FROM xpath_table('id', 'marc', $1, $3, 'id='||$2)x(id INT, output TEXT);
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.extract_marc_field ( TEXT, BIGINT, TEXT ) RETURNS TEXT AS $$
	SELECT public.extract_marc_field($1,$2,$3,'');
$$ LANGUAGE SQL;

CREATE TABLE config.i18n_locale (
    code        TEXT    PRIMARY KEY,
    marc_code   TEXT    NOT NULL REFERENCES config.language_map (code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name        TEXT    UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE config.i18n_core (
    id              BIGSERIAL   PRIMARY KEY,
    fq_field        TEXT        NOT NULL,
    identity_value  TEXT        NOT NULL,
    translation     TEXT        NOT NULL    REFERENCES config.i18n_locale (code) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    string          TEXT        NOT NULL
);
CREATE UNIQUE INDEX i18n_identity ON config.i18n_core (fq_field,identity_value,translation);
 
CREATE OR REPLACE FUNCTION oils_i18n_xlate ( keytable TEXT, keyclass TEXT, keycol TEXT, identcol TEXT, keyvalue TEXT, raw_locale TEXT ) RETURNS TEXT AS $func$
DECLARE
    locale      TEXT := REGEXP_REPLACE( REGEXP_REPLACE( raw_locale, E'[;, ].+$', '' ), E'_', '-', 'g' );
    language    TEXT := REGEXP_REPLACE( locale, E'-.+$', '' );
    result      config.i18n_core%ROWTYPE;
    fallback    TEXT;
    keyfield    TEXT := keyclass || '.' || keycol;
BEGIN

    -- Try the full locale
    SELECT  * INTO result
      FROM  config.i18n_core
      WHERE fq_field = keyfield
            AND identity_value = keyvalue
            AND translation = locale;

    -- Try just the language
    IF NOT FOUND THEN
        SELECT  * INTO result
          FROM  config.i18n_core
          WHERE fq_field = keyfield
                AND identity_value = keyvalue
                AND translation = language;
    END IF;

    -- Fall back to the string we passed in in the first place
    IF NOT FOUND THEN
	EXECUTE
            'SELECT ' ||
                keycol ||
            ' FROM ' || keytable ||
            ' WHERE ' || identcol || ' = ' || quote_literal(keyvalue)
                INTO fallback;
        RETURN fallback;
    END IF;

    RETURN result.string;
END;
$func$ LANGUAGE PLPGSQL;

-- Functions for marking translatable strings in SQL statements
-- Parameters are: primary key, string, class hint, property
CREATE OR REPLACE FUNCTION oils_i18n_gettext( INT, TEXT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT $2;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION oils_i18n_gettext( TEXT, TEXT, TEXT, TEXT ) RETURNS TEXT AS $$
    SELECT $2;
$$ LANGUAGE SQL;

ALTER TABLE config.xml_transform DROP CONSTRAINT xml_transform_namespace_uri_key;
INSERT INTO config.xml_transform VALUES ( 'mods32', 'http://www.loc.gov/mods/', 'mods', '' );


/* Upgrade to MODS32 for transforms */
ALTER TABLE config.metabib_field ALTER COLUMN format SET DEFAULT 'mods32';
UPDATE config.metabib_field SET format = 'mods32';

/* Update index definitions to MODS32-compliant XPaths */
UPDATE config.metabib_field
        SET xpath = $$//mods:mods/mods:name[@type='corporate']/mods:namePart[../mods:role/mods:roleTerm[text()='creator']]$$
        WHERE field_class = 'author' AND name = 'corporate';
UPDATE config.metabib_field
        SET xpath = $$//mods:mods/mods:name[@type='personal']/mods:namePart[../mods:role/mods:roleTerm[text()='creator']]$$
        WHERE field_class = 'author' AND name = 'personal';
UPDATE config.metabib_field
        SET xpath = $$//mods:mods/mods:name[@type='conference']/mods:namePart[../mods:role/mods:roleTerm[text()='creator']]$$
        WHERE field_class = 'author' AND name = 'conference';

/* And they all want mods32: as their prefix */
UPDATE config.metabib_field SET xpath = regexp_replace(xpath, 'mods:', 'mods32:', 'g');


ALTER TABLE config.copy_status ADD COLUMN opac_visible BOOL NOT NULL DEFAULT FALSE;
UPDATE config.copy_status SET opac_visible = holdable;

CREATE TABLE config.z3950_source (
    name                TEXT    PRIMARY KEY,
    label               TEXT    NOT NULL UNIQUE,
    host                TEXT    NOT NULL,
    port                INT     NOT NULL,
    db                  TEXT    NOT NULL,
    record_format       TEXT    NOT NULL DEFAULT 'FI',
    transmission_format TEXT    NOT NULL DEFAULT 'usmarc',
    auth                BOOL    NOT NULL DEFAULT TRUE
);

CREATE TABLE config.z3950_attr (
    id          SERIAL  PRIMARY KEY,
    source      TEXT    NOT NULL REFERENCES config.z3950_source (name),
    name        TEXT    NOT NULL,
    label       TEXT    NOT NULL,
    code        INT     NOT NULL,
    format      INT     NOT NULL,
    truncation  INT     NOT NULL DEFAULT 0,
    CONSTRAINT z_code_format_once_per_source UNIQUE (code,format,source)
);


CREATE TABLE actor.org_lasso (
    id      SERIAL  PRIMARY KEY,
    name   	TEXT    UNIQUE
);

CREATE TABLE actor.org_lasso_map (
    id          SERIAL  PRIMARY KEY,
    lasso       INT     NOT NULL REFERENCES actor.org_lasso (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    org_unit    INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);
CREATE UNIQUE INDEX ou_lasso_lasso_ou_idx ON actor.org_lasso_map (lasso, org_unit);
CREATE INDEX ou_lasso_org_unit_idx ON actor.org_lasso_map (org_unit);
 

CREATE TABLE permission.usr_object_perm_map (
	id		SERIAL	PRIMARY KEY,
	usr		INT	NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	perm		INT	NOT NULL REFERENCES permission.perm_list (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	object_type TEXT NOT NULL,
	object_id   TEXT NOT NULL,
	grantable	BOOL	NOT NULL DEFAULT FALSE,
		CONSTRAINT perm_usr_obj_once UNIQUE (usr,perm,object_type,object_id)
);

CREATE INDEX uopm_usr_idx ON permission.usr_object_perm_map (usr);



CREATE OR REPLACE FUNCTION permission.grp_ancestors ( INT ) RETURNS SETOF permission.grp_tree AS $$
        SELECT  a.*
        FROM    connectby('permission.grp_tree'::text,'parent'::text,'id'::text,'name'::text,$1::text,100,'.'::text)
                        AS t(keyid text, parent_keyid text, level int, branch text,pos int)
                JOIN permission.grp_tree a ON a.id::text = t.keyid::text
        ORDER BY
                CASE WHEN a.parent IS NULL
                        THEN 0
                        ELSE 1
                END, a.name;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION permission.usr_has_object_perm ( iuser INT, tperm TEXT, obj_type TEXT, obj_id TEXT, target_ou INT ) RETURNS BOOL AS $$
DECLARE
	r_usr	actor.usr%ROWTYPE;
	res     BOOL;
BEGIN

	SELECT * INTO r_usr FROM actor.usr WHERE id = iuser;

	IF r_usr.active = FALSE THEN
		RETURN FALSE;
	END IF;

	IF r_usr.super_user = TRUE THEN
		RETURN TRUE;
	END IF;

	SELECT TRUE INTO res FROM permission.usr_object_perm_map WHERE usr = r_usr.id AND object_type = obj_type AND object_id = obj_id;

	IF FOUND THEN
		RETURN TRUE;
	END IF;

	IF target_ou > -1 THEN
		RETURN permission.usr_has_perm( iuser, tperm, target_ou);
	END IF;

	RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION permission.usr_has_object_perm ( INT, TEXT, TEXT, TEXT ) RETURNS BOOL AS $$
    SELECT permission.usr_has_object_perm( $1, $2, $3, $4, -1 );
$$ LANGUAGE SQL;

/* Enable LIKE to use an index for database clusters with locales other than C or POSIX */
CREATE INDEX authority_full_rec_value_tpo_index ON authority.full_rec (value text_pattern_ops);
 

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT, TEXT ) RETURNS TEXT AS $func$
    use Unicode::Normalize;

	my $txt = lc(shift);
	my $sf = shift;

    $txt = NFD($txt);
	$txt =~ s/\pM+//go;	# Remove diacritics

	$txt =~ s/\xE6/AE/go;	# Convert ae digraph
	$txt =~ s/\x{153}/OE/go;# Convert oe digraph
	$txt =~ s/\xFE/TH/go;	# Convert Icelandic thorn

	$txt =~ tr/\x{2070}\x{2071}\x{2072}\x{2073}\x{2074}\x{2075}\x{2076}\x{2077}\x{2078}\x{2079}\x{207A}\x{207B}/0123456789+-/;# Convert superscript numbers
	$txt =~ tr/\x{2080}\x{2081}\x{2082}\x{2083}\x{2084}\x{2085}\x{2086}\x{2087}\x{2088}\x{2089}\x{208A}\x{208B}/0123456889+-/;# Convert subscript numbers

	$txt =~ tr/\x{0251}\x{03B1}\x{03B2}\x{0262}\x{03B3}/AABGG/;	 	# Convert Latin and Greek
	$txt =~ tr/\x{2113}\xF0\!\"\(\)\-\{\}\<\>\;\:\.\?\xA1\xBF\/\\\@\*\%\=\xB1\+\xAE\xA9\x{2117}\$\xA3\x{FFE1}\xB0\^\_\~\`/LD /;	# Convert Misc
	$txt =~ tr/\'\[\]\|//d;							# Remove Misc

	if ($sf && $sf =~ /^a/o) {
		my $commapos = index($txt,',');
		if ($commapos > -1) {
			if ($commapos != length($txt) - 1) {
				my @list = split /,/, $txt;
				my $first = shift @list;
				$txt = $first . ',' . join(' ', @list);
			} else {
				$txt =~ s/,/ /go;
			}
		}
	} else {
		$txt =~ s/,/ /go;
	}

	$txt =~ s/\s+/ /go;	# Compress multiple spaces
	$txt =~ s/^\s+//o;	# Remove leading space
	$txt =~ s/\s+$//o;	# Remove trailing space

	return $txt;
$func$ LANGUAGE 'plperlu' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.naco_normalize( TEXT ) RETURNS TEXT AS $func$
	SELECT public.naco_normalize($1,'');
$func$ LANGUAGE 'sql' STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION public.normalize_space( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(regexp_replace(regexp_replace($1, E'\\n', ' ', 'g'), E'(?:^\\s+)|(\\s+$)', '', 'g'), E'\\s+', ' ', 'g');
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.lowercase( TEXT ) RETURNS TEXT AS $$
    return lc(shift);
$$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION public.uppercase( TEXT ) RETURNS TEXT AS $$
    return uc(shift);
$$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION public.remove_diacritics( TEXT ) RETURNS TEXT AS $$
    use Unicode::Normalize;

    my $x = NFD(shift);
    $x =~ s/\pM+//go;
    return $x;

$$ LANGUAGE PLPERLU;

CREATE OR REPLACE FUNCTION public.entityize( TEXT ) RETURNS TEXT AS $$
    use Unicode::Normalize;

    my $x = NFC(shift);
    $x =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;
    return $x;

$$ LANGUAGE PLPERLU;


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


CREATE OR REPLACE FUNCTION actor.org_unit_descendants ( INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	a.*
	  FROM	connectby('actor.org_unit'::text,'id'::text,'parent_ou'::text,'name'::text,$1::text,100,'.'::text)
	  		AS t(keyid text, parent_keyid text, level int, branch text,pos int)
		JOIN actor.org_unit a ON a.id::text = t.keyid::text
	  ORDER BY  CASE WHEN a.parent_ou IS NULL THEN 0 ELSE 1 END, a.name;
$$ LANGUAGE SQL STABLE;
 
CREATE OR REPLACE FUNCTION actor.org_unit_ancestors ( INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	a.*
	  FROM	connectby('actor.org_unit'::text,'parent_ou'::text,'id'::text,'name'::text,$1::text,100,'.'::text)
	  		AS t(keyid text, parent_keyid text, level int, branch text,pos int)
		JOIN actor.org_unit a ON a.id::text = t.keyid::text
	  ORDER BY  CASE WHEN a.parent_ou IS NULL THEN 0 ELSE 1 END, a.name;
$$ LANGUAGE SQL STABLE;
 
CREATE OR REPLACE FUNCTION actor.org_unit_descendants ( INT,INT ) RETURNS SETOF actor.org_unit AS $$
	SELECT	a.*
	  FROM	connectby('actor.org_unit'::text,'id'::text,'parent_ou'::text,'name'::text,
	  			(SELECT	x.id
				   FROM	actor.org_unit_ancestors($1) x
				   	JOIN actor.org_unit_type y ON x.ou_type = y.id
				  WHERE	y.depth = $2)::text
		,100,'.'::text)
	  		AS t(keyid text, parent_keyid text, level int, branch text,pos int)
		JOIN actor.org_unit a ON a.id::text = t.keyid::text
	  ORDER BY  CASE WHEN a.parent_ou IS NULL THEN 0 ELSE 1 END, a.name;
$$ LANGUAGE SQL STABLE;
 
ALTER TABLE metabib.rec_descriptor ADD COLUMN date1 TEXT;
ALTER TABLE metabib.rec_descriptor ADD COLUMN date2 TEXT;

UPDATE	metabib.rec_descriptor
  SET	date1 = regexp_replace(substring(metabib.full_rec.value,8,4),E'\\D','0','g'),
	date2 = regexp_replace(substring(metabib.full_rec.value,12,4),E'\\D','9','g')
  FROM	metabib.full_rec
  WHERE	metabib.full_rec.record = metabib.rec_descriptor.record AND metabib.full_rec.tag = '008';

ALTER TABLE asset.copy_location ADD COLUMN hold_verify BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE asset.copy ALTER price DROP NOT NULL;
ALTER TABLE asset.copy ALTER price DROP DEFAULT;

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
	moved_cns INT := 0;
	source_cn asset.call_number%ROWTYPE;
	target_cn asset.call_number%ROWTYPE;
BEGIN
	FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

		SELECT	INTO target_cn *
		  FROM	asset.call_number
		  WHERE	label = source_cn.label
			AND owning_lib = source_cn.owning_lib
			AND record = target_record;

		IF FOUND THEN
			UPDATE	asset.copy
			  SET	call_number = target_cn.id
			  WHERE	call_number = source_cn.id;
			DELETE FROM asset.call_number
			  WHERE id = target_cn.id;
		ELSE
			UPDATE	asset.call_number
			  SET	record = target_record
			  WHERE	id = source_cn.id;
		END IF;

		moved_cns := moved_cns + 1;
	END LOOP;

	RETURN moved_cns;
END;
$func$ LANGUAGE plpgsql;
 

ALTER TABLE money.billable_xact ADD COLUMN unrecovered BOOL;

CREATE OR REPLACE VIEW money.billable_xact_summary AS
	SELECT	xact.id,
		xact.usr,
		xact.xact_start,
		xact.xact_finish,
		credit.amount AS total_paid,
		credit.payment_ts AS last_payment_ts,
		credit.note AS last_payment_note,
		credit.payment_type AS last_payment_type,
		debit.amount AS total_owed,
		debit.billing_ts AS last_billing_ts,
		debit.note AS last_billing_note,
		debit.billing_type AS last_billing_type,
		COALESCE(debit.amount, 0::numeric) - COALESCE(credit.amount, 0::numeric) AS balance_owed,
		p.relname AS xact_type
	  FROM	money.billable_xact xact
		JOIN pg_class p ON xact.tableoid = p.oid
		LEFT JOIN (
			SELECT	billing.xact,
				sum(billing.amount) AS amount,
				max(billing.billing_ts) AS billing_ts,
				last(billing.note) AS note,
				last(billing.billing_type) AS billing_type
			  FROM	money.billing
			  WHERE	billing.voided IS FALSE
			  GROUP BY billing.xact
			) debit ON xact.id = debit.xact
		LEFT JOIN (
			SELECT	payment_view.xact,
				sum(payment_view.amount) AS amount,
				max(payment_view.payment_ts) AS payment_ts,
				last(payment_view.note) AS note,
				last(payment_view.payment_type) AS payment_type
			  FROM	money.payment_view
			  WHERE	payment_view.voided IS FALSE
			  GROUP BY payment_view.xact
			) credit ON xact.id = credit.xact
	  ORDER BY debit.billing_ts, credit.payment_ts;
 
ALTER TABLE action.circulation ADD COLUMN create_time TIMESTAMP WITH TIME ZONE DEFAULT NOW();


CREATE TABLE action.aged_circulation (
	usr_post_code		TEXT,
	usr_home_ou		INT	NOT NULL,
	usr_profile		INT	NOT NULL,
	usr_birth_year		INT,
	copy_call_number	INT	NOT NULL,
	copy_location		INT	NOT NULL,
	copy_owning_lib		INT	NOT NULL,
	copy_circ_lib		INT	NOT NULL,
	copy_bib_record		BIGINT	NOT NULL,
	LIKE action.circulation

);
ALTER TABLE action.aged_circulation ADD PRIMARY KEY (id);
ALTER TABLE action.aged_circulation DROP COLUMN usr;
CREATE INDEX aged_circ_circ_lib_idx ON "action".aged_circulation (circ_lib);
CREATE INDEX aged_circ_start_idx ON "action".aged_circulation (xact_start);
CREATE INDEX aged_circ_copy_circ_lib_idx ON "action".aged_circulation (copy_circ_lib);
CREATE INDEX aged_circ_copy_owning_lib_idx ON "action".aged_circulation (copy_owning_lib);
CREATE INDEX aged_circ_copy_location_idx ON "action".aged_circulation (copy_location);

CREATE OR REPLACE VIEW action.all_circulation AS
	SELECT	id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
		copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
		circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
		stop_fines_time, checkin_time, create_time, duration, fine_interval, recuring_fine,
		max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recuring_fine_rule,
		max_fine_rule, stop_fines
	  FROM	action.aged_circulation
			UNION ALL
	SELECT	circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
		cp.call_number AS copy_call_number, cp.location AS copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
		cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
		circ.checkin_lib, circ.renewal_remaining, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
		circ.fine_interval, circ.recuring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
		circ.recuring_fine_rule, circ.max_fine_rule, circ.stop_fines
       FROM  action.circulation circ
             JOIN asset.copy cp ON (circ.target_copy = cp.id)
		JOIN asset.call_number cn ON (cp.call_number = cn.id)
		JOIN actor.usr p ON (circ.usr = p.id)
		LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
		LEFT JOIN actor.usr_address b ON (p.billing_address = a.id);

CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
BEGIN
	INSERT INTO action.aged_circulation
		(id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
		copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
		circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
		stop_fines_time, checkin_time, create_time, duration, fine_interval, recuring_fine,
		max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recuring_fine_rule,
		max_fine_rule, stop_fines)
	  SELECT
		id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
		copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
		circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, due_date,
		stop_fines_time, checkin_time, create_time, duration, fine_interval, recuring_fine,
		max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recuring_fine_rule,
		max_fine_rule, stop_fines
	    FROM action.all_circulation WHERE id = OLD.id;

	RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER action_circulation_aging_tgr
	BEFORE DELETE ON action.circulation
	FOR EACH ROW
	EXECUTE PROCEDURE action.age_circ_on_delete ();

CREATE OR REPLACE VIEW extend_reporter.full_circ_count AS
 SELECT cp.id, COALESCE(sum(c.circ_count), 0::bigint) + COALESCE(count(circ.id), 0::bigint) AS circ_count
   FROM asset."copy" cp
   LEFT JOIN extend_reporter.legacy_circ_count c USING (id)
   LEFT JOIN "action".all_circulation circ ON circ.target_copy = c.id
  GROUP BY cp.id;



CREATE OR REPLACE FUNCTION search.staged_fts (

    param_search_ou INT,
    param_depth     INT,
    param_searches  TEXT, -- JSON hash, to be turned into a resultset via search.parse_search_args
    param_statuses  INT[],
    param_locations INT[],
    param_audience  TEXT[],
    param_language  TEXT[],
    param_lit_form  TEXT[],
    param_types     TEXT[],
    param_forms     TEXT[],
    param_vformats  TEXT[],
    param_bib_level TEXT[],
    param_before    TEXT,
    param_after     TEXT,
    param_during    TEXT,
    param_between   TEXT[],
    param_pref_lang TEXT,
    param_pref_lang_multiplier REAL,
    param_sort      TEXT,
    param_sort_desc BOOL,
    metarecord      BOOL,
    staff           BOOL,
    param_rel_limit INT,
    param_chk_limit INT,
    param_skip_chk  INT
 
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    query_part          search.search_args%ROWTYPE;
    phrase_query_part   search.search_args%ROWTYPE;
    rank_adjust_id      INT;
    core_rel_limit      INT;
    core_chk_limit      INT;
    core_skip_chk       INT;
    rank_adjust         search.relevance_adjustment%ROWTYPE;
    query_table         TEXT;
    tmp_text            TEXT;
    tmp_int             INT;
    current_rank        TEXT;
    ranks               TEXT[] := '{}';
    query_table_alias   TEXT;
    from_alias_array    TEXT[] := '{}';
    used_ranks          TEXT[] := '{}';
    mb_field            INT;
    mb_field_list       INT[];
    search_org_list     INT[];
    select_clause       TEXT := 'SELECT';
    from_clause         TEXT := ' FROM  metabib.metarecord_source_map m JOIN metabib.rec_descriptor mrd ON (m.source = mrd.record) ';
    where_clause        TEXT := ' WHERE 1=1 ';
    mrd_used            BOOL := FALSE;
    sort_desc           BOOL := FALSE;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;
    vis_limit_query     TEXT;
    inner_where_clause  TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

BEGIN

    core_rel_limit := COALESCE( param_rel_limit, 25000 );
    core_chk_limit := COALESCE( param_chk_limit, 1000 );
    core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF metarecord THEN
        select_clause := select_clause || ' m.metarecord as id, array_accum(distinct m.source) as records,';
    ELSE
        select_clause := select_clause || ' m.source as id, array_accum(distinct m.source) as records,';
    END IF;

    -- first we need to construct the base query
    FOR query_part IN SELECT * FROM search.parse_search_args(param_searches) WHERE term_type = 'fts_query' LOOP

        inner_where_clause := 'index_vector @@ ' || query_part.term;

        IF query_part.field_name IS NOT NULL THEN

           SELECT  id INTO mb_field
             FROM  config.metabib_field
             WHERE field_class = query_part.field_class
                   AND name = query_part.field_name;

            IF FOUND THEN
                inner_where_clause := inner_where_clause ||
                    ' AND ' || 'field = ' || mb_field;
            END IF;

        END IF;

        -- moving on to the rank ...
        SELECT  * INTO query_part
          FROM  search.parse_search_args(param_searches)
          WHERE term_type = 'fts_rank'
                AND table_alias = query_part.table_alias;

        current_rank := query_part.term || ' * ' || query_part.table_alias || '_weight.weight';

        IF query_part.field_name IS NOT NULL THEN

           SELECT  array_accum(distinct id) INTO mb_field_list
             FROM  config.metabib_field
             WHERE field_class = query_part.field_class
                   AND name = query_part.field_name;

        ELSE

           SELECT  array_accum(distinct id) INTO mb_field_list
             FROM  config.metabib_field
             WHERE field_class = query_part.field_class;

        END IF;

        FOR rank_adjust IN SELECT * FROM search.relevance_adjustment WHERE active AND field IN ( SELECT * FROM search.explode_array( mb_field_list ) ) LOOP

            IF NOT rank_adjust.bump_type = ANY (used_ranks) THEN

                IF rank_adjust.bump_type = 'first_word' THEN
                    SELECT  term INTO tmp_text
                      FROM  search.parse_search_args(param_searches)
                      WHERE table_alias = query_part.table_alias AND term_type = 'word'
                      ORDER BY id
                      LIMIT 1;

                    tmp_text := query_part.table_alias || '.value ILIKE ' || quote_literal( tmp_text || '%' );

                ELSIF rank_adjust.bump_type = 'word_order' THEN
                    SELECT  array_to_string( array_accum( term ), '%' ) INTO tmp_text
                      FROM  search.parse_search_args(param_searches)
                      WHERE table_alias = query_part.table_alias AND term_type = 'word';

                    tmp_text := query_part.table_alias || '.value ILIKE ' || quote_literal( '%' || tmp_text || '%' );

                ELSIF rank_adjust.bump_type = 'full_match' THEN
                    SELECT  array_to_string( array_accum( term ), E'\\s+' ) INTO tmp_text
                      FROM  search.parse_search_args(param_searches)
                      WHERE table_alias = query_part.table_alias AND term_type = 'word';

                    tmp_text := query_part.table_alias || '.value  ~ ' || quote_literal( '^' || tmp_text || E'\\W*$' );

                END IF;


                IF tmp_text IS NOT NULL THEN
                    current_rank := current_rank || ' * ( CASE WHEN ' || tmp_text ||
                        ' THEN ' || rank_adjust.multiplier || '::REAL ELSE 1.0 END )';
                END IF;

                used_ranks := array_append( used_ranks, rank_adjust.bump_type );

            END IF;

        END LOOP;

        ranks := array_append( ranks, current_rank );
        used_ranks := '{}';

        FOR phrase_query_part IN
            SELECT  * 
              FROM  search.parse_search_args(param_searches)
              WHERE term_type = 'phrase'
                    AND table_alias = query_part.table_alias LOOP

            tmp_text := replace( phrase_query_part.term, '*', E'\\*' );
            tmp_text := replace( tmp_text, '?', E'\\?' );
            tmp_text := replace( tmp_text, '+', E'\\+' );
            tmp_text := replace( tmp_text, '|', E'\\|' );
            tmp_text := replace( tmp_text, '(', E'\\(' );
            tmp_text := replace( tmp_text, ')', E'\\)' );
            tmp_text := replace( tmp_text, '[', E'\\[' );
            tmp_text := replace( tmp_text, ']', E'\\]' );

            inner_where_clause := inner_where_clause || ' AND ' || 'value  ~* ' || quote_literal( E'(^|\\W+)' || regexp_replace(tmp_text, E'\\s+',E'\\\\s+','g') || E'(\\W+|\$)' );

        END LOOP;

        query_table := search.pick_table(query_part.field_class);

        from_clause := from_clause ||
            ' JOIN ( SELECT * FROM ' || query_table || ' WHERE ' || inner_where_clause ||
                    CASE WHEN core_rel_limit > 0 THEN ' LIMIT ' || core_rel_limit::TEXT ELSE '' END || ' ) AS ' || query_part.table_alias ||
                ' ON ( m.source = ' || query_part.table_alias || '.source )' ||
            ' JOIN config.metabib_field AS ' || query_part.table_alias || '_weight' ||
                ' ON ( ' || query_part.table_alias || '.field = ' || query_part.table_alias || '_weight.id  AND  ' || query_part.table_alias || '_weight.search_field)';

        from_alias_array := array_append(from_alias_array, query_part.table_alias);

    END LOOP;

    IF param_pref_lang IS NOT NULL AND param_pref_lang_multiplier IS NOT NULL THEN
        current_rank := ' CASE WHEN mrd.item_lang = ' || quote_literal( param_pref_lang ) ||
            ' THEN ' || param_pref_lang_multiplier || '::REAL ELSE 1.0 END ';

        -- ranks := array_append( ranks, current_rank );
    END IF;

    current_rank := ' AVG( ( (' || array_to_string( ranks, ') + (' ) || ') ) * ' || current_rank || ' ) ';
    select_clause := select_clause || current_rank || ' AS rel,';

    sort_desc = param_sort_desc;

    IF param_sort = 'pubdate' THEN

        tmp_text := '999999';
        IF param_sort_desc THEN tmp_text := '0'; END IF;

        current_rank := $$ COALESCE( FIRST(NULLIF(REGEXP_REPLACE(mrd.date1, E'\\D+', '9', 'g'),'')), $$ || quote_literal(tmp_text) || $$ )::INT $$;

    ELSIF param_sort = 'title' THEN

        tmp_text := 'zzzzzz';
        IF param_sort_desc THEN tmp_text := '    '; END IF;

        current_rank := $$
            ( COALESCE( FIRST ((
                SELECT  LTRIM(SUBSTR( frt.value, COALESCE(SUBSTRING(frt.ind2 FROM E'\\d+'),'0')::INT + 1 ))
                  FROM  metabib.full_rec frt
                  WHERE frt.record = m.source
                    AND frt.tag = '245'
                    AND frt.subfield = 'a'
                  LIMIT 1
            )),$$ || quote_literal(tmp_text) || $$))
        $$;

    ELSIF param_sort = 'author' THEN

        tmp_text := 'zzzzzz';
        IF param_sort_desc THEN tmp_text := '    '; END IF;

        current_rank := $$
            ( COALESCE( FIRST ((
                SELECT  LTRIM(fra.value)
                  FROM  metabib.full_rec fra
                  WHERE fra.record = m.source
                    AND fra.tag LIKE '1%'
                    AND fra.subfield = 'a'
                  ORDER BY fra.tag::text::int
                  LIMIT 1
            )),$$ || quote_literal(tmp_text) || $$))
        $$;

    ELSIF param_sort = 'create_date' THEN
            current_rank := $$( FIRST (( SELECT create_date FROM biblio.record_entry rbr WHERE rbr.id = m.source)) )$$;
    ELSIF param_sort = 'edit_date' THEN
            current_rank := $$( FIRST (( SELECT edit_date FROM biblio.record_entry rbr WHERE rbr.id = m.source)) )$$;
    ELSE
        sort_desc := NOT COALESCE(param_sort_desc, FALSE);
    END IF;

    select_clause := select_clause || current_rank || ' AS rank';

    -- now add the other qualifiers
    IF param_audience IS NOT NULL AND array_upper(param_audience, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.audience IN ('$$ || array_to_string(param_audience, $$','$$) || $$') $$;
    END IF;

    IF param_language IS NOT NULL AND array_upper(param_language, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.item_lang IN ('$$ || array_to_string(param_language, $$','$$) || $$') $$;
    END IF;

    IF param_lit_form IS NOT NULL AND array_upper(param_lit_form, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.lit_form IN ('$$ || array_to_string(param_lit_form, $$','$$) || $$') $$;
    END IF;

    IF param_types IS NOT NULL AND array_upper(param_types, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.item_type IN ('$$ || array_to_string(param_types, $$','$$) || $$') $$;
    END IF;

    IF param_forms IS NOT NULL AND array_upper(param_forms, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.item_form IN ('$$ || array_to_string(param_forms, $$','$$) || $$') $$;
    END IF;

    IF param_vformats IS NOT NULL AND array_upper(param_vformats, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.vr_format IN ('$$ || array_to_string(param_vformats, $$','$$) || $$') $$;
    END IF;

    IF param_bib_level IS NOT NULL AND array_upper(param_bib_level, 1) > 0 THEN
        where_clause = where_clause || $$ AND mrd.bib_level IN ('$$ || array_to_string(param_bib_level, $$','$$) || $$') $$;
    END IF;

    IF param_before IS NOT NULL AND param_before <> '' THEN
        where_clause = where_clause || $$ AND mrd.date1 <= $$ || quote_literal(param_before) || ' ';
    END IF;

    IF param_after IS NOT NULL AND param_after <> '' THEN
        where_clause = where_clause || $$ AND mrd.date1 >= $$ || quote_literal(param_after) || ' ';
    END IF;

    IF param_during IS NOT NULL AND param_during <> '' THEN
        where_clause = where_clause || $$ AND $$ || quote_literal(param_during) || $$ BETWEEN mrd.date1 AND mrd.date2 $$;
    END IF;

    IF param_between IS NOT NULL AND array_upper(param_between, 1) > 1 THEN
        where_clause = where_clause || $$ AND mrd.date1 BETWEEN '$$ || array_to_string(param_between, $$' AND '$$) || $$' $$;
    END IF;

    core_rel_query := select_clause || from_clause || where_clause ||
                        ' GROUP BY 1 ORDER BY 4' || CASE WHEN sort_desc THEN ' DESC' ELSE ' ASC' END || ';';
    --RAISE NOTICE 'Base Query:  %', core_rel_query;

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT array_accum(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;
    ELSIF param_search_ou < 0 THEN
        SELECT array_accum(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;
    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    OPEN core_cursor FOR EXECUTE core_rel_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;


        IF total_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % total, % checked so far ... ', total_count, check_count;
        END IF;

        IF core_chk_limit > 0 AND total_count - core_skip_chk + 1 >= core_chk_limit THEN
            total_count := total_count + 1;
            CONTINUE;
        END IF;

        total_count := total_count + 1;

        CONTINUE WHEN param_skip_chk IS NOT NULL and total_count < param_skip_chk;

        check_count := check_count + 1;

        PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );
        IF NOT FOUND THEN
            -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
            deleted_count := deleted_count + 1;
            CONTINUE;
        END IF;

        PERFORM 1
          FROM  biblio.record_entry b
                JOIN config.bib_source s ON (b.source = s.id)
          WHERE s.transcendant
                AND b.id IN ( SELECT * FROM search.explode_array( core_result.records ) );

        IF FOUND THEN
            -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
            visible_count := visible_count + 1;

            current_res.id = core_result.id;
            current_res.rel = core_result.rel;

            tmp_int := 1;
            IF metarecord THEN
                SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
            END IF;

            IF tmp_int = 1 THEN
                current_res.record = core_result.records[1];
            ELSE
                current_res.record = NULL;
            END IF;

            RETURN NEXT current_res;

            CONTINUE;
        END IF;

        IF param_statuses IS NOT NULL AND array_upper(param_statuses, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.status IN ( SELECT * FROM search.explode_array( param_statuses ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all status-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.location IN ( SELECT * FROM search.explode_array( param_locations ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all copy_location-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        END IF;

        IF staff IS NULL OR NOT staff THEN

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
                    JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                    JOIN asset.copy_location cl ON (cp.location = cl.id)
                    JOIN config.copy_status cs ON (cp.status = cs.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cs.opac_visible
                    AND cl.opac_visible
                    AND cp.opac_visible
                    AND a.opac_visible
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                excluded_count := excluded_count + 1;
                CONTINUE;
            END IF;

        ELSE

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
                    JOIN actor.org_unit a ON (cp.circ_lib = a.id)
                    JOIN asset.copy_location cl ON (cp.location = cl.id)
              WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM search.explode_array( search_org_list ) )
                    AND cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
              LIMIT 1;

            IF NOT FOUND THEN

                PERFORM 1
                  FROM  asset.call_number cn
                  WHERE cn.record IN ( SELECT * FROM search.explode_array( core_result.records ) )
                  LIMIT 1;

                IF FOUND THEN
                    -- RAISE NOTICE ' % were all visibility-excluded ... ', core_result.records;
                    excluded_count := excluded_count + 1;
                    CONTINUE;
                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;

        tmp_int := 1;
        IF metarecord THEN
            SELECT COUNT(DISTINCT s.source) INTO tmp_int FROM metabib.metarecord_source_map s WHERE s.metarecord = core_result.id;
        END IF;

        IF tmp_int = 1 THEN
            current_res.record = core_result.records[1];
        ELSE
            current_res.record = NULL;
        END IF;

        RETURN NEXT current_res;

        IF visible_count % 1000 = 0 THEN
            -- RAISE NOTICE ' % visible so far ... ', visible_count;
        END IF;

    END LOOP;

    current_res.id = NULL;
    current_res.rel = NULL;
    current_res.record = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;

-- To avoid any updates while we're doin' our thing...
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- This index, right here, is the reason for this change.
DROP INDEX metabib.metabib_full_rec_value_idx;

-- So, on to it.
-- Move the table out of the way ...
ALTER TABLE metabib.full_rec RENAME TO real_full_rec;

-- ... and let the trigger management functions know about the change ...
CREATE OR REPLACE FUNCTION reporter.disable_materialized_simple_record_trigger () RETURNS VOID AS $$
    DROP TRIGGER zzz_update_materialized_simple_record_tgr ON metabib.real_full_rec;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION reporter.enable_materialized_simple_record_trigger () RETURNS VOID AS $$

    TRUNCATE TABLE reporter.materialized_simple_record;

    INSERT INTO reporter.materialized_simple_record
        (id,fingerprint,quality,tcn_source,tcn_value,title,author,publisher,pubdate,isbn,issn)
        SELECT DISTINCT ON (id) * FROM reporter.old_super_simple_record;

    CREATE TRIGGER zzz_update_materialized_simple_record_tgr
        AFTER INSERT OR UPDATE OR DELETE ON metabib.real_full_rec
        FOR EACH ROW EXECUTE PROCEDURE reporter.simple_rec_sync();

$$ LANGUAGE SQL;

-- ... replace the table with a suitable view, which applies the index contstraint we'll use ...
CREATE OR REPLACE VIEW metabib.full_rec AS
    SELECT  id,
            record,
            tag,
            ind1,
            ind2,
            subfield,
            SUBSTRING(value,1,1024) AS value,
            index_vector
      FROM  metabib.real_full_rec;

-- ... now some rules to transform DML against the view into DML against the underlying table ...
CREATE OR REPLACE RULE metabib_full_rec_insert_rule
    AS ON INSERT TO metabib.full_rec
    DO INSTEAD
    INSERT INTO metabib.real_full_rec VALUES (
        COALESCE(NEW.id, NEXTVAL('metabib.full_rec_id_seq'::REGCLASS)),
        NEW.record,
        NEW.tag,
        NEW.ind1,
        NEW.ind2,
        NEW.subfield,
        NEW.value,
        NEW.index_vector
    );

CREATE OR REPLACE RULE metabib_full_rec_update_rule
    AS ON UPDATE TO metabib.full_rec
    DO INSTEAD
    UPDATE  metabib.real_full_rec SET
        id = NEW.id,
        record = NEW.record,
        tag = NEW.tag,
        ind1 = NEW.ind1,
        ind2 = NEW.ind2,
        subfield = NEW.subfield,
        value = NEW.value,
        index_vector = NEW.index_vector
      WHERE id = OLD.id;

CREATE OR REPLACE RULE metabib_full_rec_delete_rule
    AS ON DELETE TO metabib.full_rec
    DO INSTEAD
    DELETE FROM metabib.real_full_rec WHERE id = OLD.id;

-- ... and last, but not least, create a fore-shortened index on the value column.
CREATE INDEX metabib_full_rec_value_idx ON metabib.real_full_rec (substring(value,1,1024));


CREATE OR REPLACE FUNCTION explode_array(anyarray) RETURNS SETOF anyelement AS $BODY$
    SELECT ($1)[s] FROM generate_series(1, array_upper($1, 1)) AS s;
$BODY$
LANGUAGE 'sql' IMMUTABLE;

-- NOTE: current config.item_type should get sip2_media_type and magnetic_media columns

-- New table needed to handle circ modifiers inside the DB.  Will still require
-- central admin.  The circ_modifier column on asset.copy will become an fkey to this table.
CREATE TABLE config.circ_modifier (
	code    		TEXT	PRIMARY KEY,
	name	    	TEXT	UNIQUE NOT NULL,
	description	    TEXT	NOT NULL,
	sip2_media_type	TEXT	NOT NULL,
	magnetic_media	BOOL	NOT NULL DEFAULT TRUE
);

UPDATE asset.copy SET circ_modifier = UPPER(circ_modifier) WHERE circ_modifier IS NOT NULL AND circ_modifier <> '';
UPDATE asset.copy SET circ_modifier = NULL WHERE circ_modifier = '';

INSERT INTO config.circ_modifier (code, name, description, sip2_media_type )
    SELECT DISTINCT
            UPPER(circ_modifier),
            UPPER(circ_modifier),
            LOWER(circ_modifier),
            '001'
      FROM  asset.copy
      WHERE circ_modifier IS NOT NULL;

-- add an fkey pointing to the new circ mod table
ALTER TABLE asset.copy ADD CONSTRAINT circ_mod_fkey FOREIGN KEY (circ_modifier) REFERENCES config.circ_modifier (code) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- config table to hold the vr_format names
CREATE TABLE config.videorecording_format_map (
	code	TEXT	PRIMARY KEY,
	value	TEXT	NOT NULL
);

INSERT INTO config.videorecording_format_map VALUES ('a','Beta');
INSERT INTO config.videorecording_format_map VALUES ('b','VHS');
INSERT INTO config.videorecording_format_map VALUES ('c','U-matic');
INSERT INTO config.videorecording_format_map VALUES ('d','EIAJ');
INSERT INTO config.videorecording_format_map VALUES ('e','Type C');
INSERT INTO config.videorecording_format_map VALUES ('f','Quadruplex');
INSERT INTO config.videorecording_format_map VALUES ('g','Laserdisc');
INSERT INTO config.videorecording_format_map VALUES ('h','CED');
INSERT INTO config.videorecording_format_map VALUES ('i','Betacam');
INSERT INTO config.videorecording_format_map VALUES ('j','Betacam SP');
INSERT INTO config.videorecording_format_map VALUES ('k','Super-VHS');
INSERT INTO config.videorecording_format_map VALUES ('m','M-II');
INSERT INTO config.videorecording_format_map VALUES ('o','D-2');
INSERT INTO config.videorecording_format_map VALUES ('p','8 mm.');
INSERT INTO config.videorecording_format_map VALUES ('q','Hi-8 mm.');
INSERT INTO config.videorecording_format_map VALUES ('u','Unknown');
INSERT INTO config.videorecording_format_map VALUES ('v','DVD');
INSERT INTO config.videorecording_format_map VALUES ('z','Other');

CREATE TABLE config.circ_matrix_matchpoint (
	id	    		SERIAL	PRIMARY KEY,
	active			BOOL	NOT NULL DEFAULT TRUE,
	org_unit		INT	NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,	-- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
	grp		    	INT	NOT NULL REFERENCES permission.grp_tree (id) DEFERRABLE INITIALLY DEFERRED,	-- Set to the top applicable group from the group tree; will need descendents and prox functions for filtering
	circ_modifier	TEXT	REFERENCES config.circ_modifier (code) DEFERRABLE INITIALLY DEFERRED,
	marc_type		TEXT	REFERENCES config.item_type_map (code) DEFERRABLE INITIALLY DEFERRED,
	marc_form		TEXT	REFERENCES config.item_form_map (code) DEFERRABLE INITIALLY DEFERRED,
	marc_vr_format	TEXT	REFERENCES config.videorecording_format_map (code) DEFERRABLE INITIALLY DEFERRED,
	ref_flag		BOOL,
	is_renewal    	BOOL,
	usr_age_lower_bound	INTERVAL,
	usr_age_upper_bound	INTERVAL,
	CONSTRAINT ep_once_per_grp_loc_mod_marc UNIQUE (grp, org_unit, circ_modifier, marc_type, marc_form, marc_vr_format, ref_flag, usr_age_lower_bound, usr_age_upper_bound, is_renewal)
);


-- Tests to determine if circ can occur for this item at this location for this patron
CREATE TABLE config.circ_matrix_test (
	matchpoint      INT     PRIMARY KEY NOT NULL REFERENCES config.circ_matrix_matchpoint (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	circulate       BOOL    NOT NULL DEFAULT TRUE,	-- Hard "can't circ" flag requiring an override
	max_items_out   INT,                        	-- Total current active circulations must be less than this, NULL means skip (always pass)
	max_overdue     INT,                            -- Total overdue active circulations must be less than this, NULL means skip (always pass)
	max_fines       NUMERIC(8,2),                   -- Total fines owed must be less than this, NULL means skip (always pass)
	org_depth       INT,                            -- Set to the top OU for the max-out applicability range
	script_test     TEXT                            -- filename or javascript source ??
);

-- Tests for max items out by circ_modifier
CREATE TABLE config.circ_matrix_circ_mod_test (
	id          SERIAL     PRIMARY KEY,
	matchpoint  INT     NOT NULL REFERENCES config.circ_matrix_matchpoint (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	items_out   INT     NOT NULL,                        	-- Total current active circulations must be less than this, NULL means skip (always pass)
	circ_mod    TEXT    NOT NULL REFERENCES config.circ_modifier (code) ON DELETE CASCADE ON UPDATE CASCADE  DEFERRABLE INITIALLY DEFERRED-- circ_modifier type that the max out applies to
);


-- How to circ, assuming tests pass
CREATE TABLE config.circ_matrix_ruleset (
	matchpoint		INT	PRIMARY KEY REFERENCES config.circ_matrix_matchpoint (id) DEFERRABLE INITIALLY DEFERRED,
	duration_rule		INT	NOT NULL REFERENCES config.rule_circ_duration (id) DEFERRABLE INITIALLY DEFERRED,
	recurring_fine_rule	INT	NOT NULL REFERENCES config.rule_recuring_fine (id) DEFERRABLE INITIALLY DEFERRED,
	max_fine_rule		INT	NOT NULL REFERENCES config.rule_max_fine (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE OR REPLACE FUNCTION action.find_circ_matrix_matchpoint( context_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS INT AS $func$
DECLARE
	current_group	permission.grp_tree%ROWTYPE;
	user_object	actor.usr%ROWTYPE;
	item_object	asset.copy%ROWTYPE;
	rec_descriptor	metabib.rec_descriptor%ROWTYPE;
	current_mp	config.circ_matrix_matchpoint%ROWTYPE;
	matchpoint	config.circ_matrix_matchpoint%ROWTYPE;
BEGIN
	SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
	SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
	SELECT INTO rec_descriptor r.* FROM metabib.rec_descriptor r JOIN asset.call_number c USING (record) WHERE c.id = item_object.call_number;
	SELECT INTO current_group * FROM permission.grp_tree WHERE id = user_object.profile;

	LOOP 
		-- for each potential matchpoint for this ou and group ...
		FOR current_mp IN
			SELECT	m.*
			  FROM	config.circ_matrix_matchpoint m
				JOIN actor.org_unit_ancestors( context_ou ) d ON (m.org_unit = d.id)
				LEFT JOIN actor.org_unit_proximity p ON (p.from_org = context_ou AND p.to_org = d.id)
			  WHERE	m.grp = current_group.id AND m.active
			  ORDER BY	CASE WHEN p.prox		IS NULL THEN 999 ELSE p.prox END,
					CASE WHEN m.is_renewal = renewal        THEN 64 ELSE 0 END +
					CASE WHEN m.circ_modifier	IS NOT NULL THEN 32 ELSE 0 END +
					CASE WHEN m.marc_type		IS NOT NULL THEN 16 ELSE 0 END +
					CASE WHEN m.marc_form		IS NOT NULL THEN 8 ELSE 0 END +
					CASE WHEN m.marc_vr_format	IS NOT NULL THEN 4 ELSE 0 END +
					CASE WHEN m.ref_flag		IS NOT NULL THEN 2 ELSE 0 END +
					CASE WHEN m.usr_age_lower_bound	IS NOT NULL THEN 0.5 ELSE 0 END +
					CASE WHEN m.usr_age_upper_bound	IS NOT NULL THEN 0.5 ELSE 0 END DESC LOOP

			IF current_mp.circ_modifier IS NOT NULL THEN
				CONTINUE WHEN current_mp.circ_modifier <> item_object.circ_modifier;
			END IF;

			IF current_mp.marc_type IS NOT NULL THEN
				IF item_object.circ_as_type IS NOT NULL THEN
					CONTINUE WHEN current_mp.marc_type <> item_object.circ_as_type;
				ELSE
					CONTINUE WHEN current_mp.marc_type <> rec_descriptor.item_type;
				END IF;
			END IF;

			IF current_mp.marc_form IS NOT NULL THEN
				CONTINUE WHEN current_mp.marc_form <> rec_descriptor.item_form;
			END IF;

			IF current_mp.marc_vr_format IS NOT NULL THEN
				CONTINUE WHEN current_mp.marc_vr_format <> rec_descriptor.vr_format;
			END IF;

			IF current_mp.ref_flag IS NOT NULL THEN
				CONTINUE WHEN current_mp.ref_flag <> item_object.ref;
			END IF;

			IF current_mp.usr_age_lower_bound IS NOT NULL THEN
				CONTINUE WHEN user_object.dob IS NULL OR current_mp.usr_age_lower_bound < age(user_object.dob);
			END IF;

			IF current_mp.usr_age_upper_bound IS NOT NULL THEN
				CONTINUE WHEN user_object.dob IS NULL OR current_mp.usr_age_upper_bound > age(user_object.dob);
			END IF;


			-- everything was undefined or matched
			matchpoint = current_mp;

			EXIT WHEN matchpoint.id IS NOT NULL;
		END LOOP;

		EXIT WHEN current_group.parent IS NULL OR matchpoint.id IS NOT NULL;

		SELECT INTO current_group * FROM permission.grp_tree WHERE id = current_group.parent;
	END LOOP;

	RETURN matchpoint.id;
END;
$func$ LANGUAGE plpgsql;


CREATE TYPE action.matrix_test_result AS ( success BOOL, matchpoint INT, fail_part TEXT );
CREATE OR REPLACE FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
	matchpoint_id		INT;
	user_object		actor.usr%ROWTYPE;
	item_object		asset.copy%ROWTYPE;
	item_status_object	config.copy_status%ROWTYPE;
	item_location_object	asset.copy_location%ROWTYPE;
	result			action.matrix_test_result;
	circ_test		config.circ_matrix_test%ROWTYPE;
	out_by_circ_mod		config.circ_matrix_circ_mod_test%ROWTYPE;
	items_out		INT;
	items_overdue		INT;
	overdue_orgs		INT[];
	current_fines		NUMERIC(8,2) := 0.0;
	tmp_fines		NUMERIC(8,2);
	tmp_groc		RECORD;
	tmp_circ		RECORD;
	done			BOOL := FALSE;
BEGIN
	result.success := TRUE;

	-- Fail if the user is BARRED
	SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

	-- Fail if we couldn't find a set of tests
	IF user_object.id IS NULL THEN
		result.fail_part := 'no_user';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
		RETURN;
	END IF;

	IF user_object.barred IS TRUE THEN
		result.fail_part := 'actor.usr.barred';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
	END IF;

	-- Fail if the item can't circulate
	SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
	IF item_object.circulate IS FALSE THEN
		result.fail_part := 'asset.copy.circulate';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
	END IF;

	-- Fail if the item isn't in a circulateable status on a non-renewal
	IF NOT renewal AND item_object.status NOT IN ( 0, 7, 8 ) THEN 
		result.fail_part := 'asset.copy.status';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
	ELSIF renewal AND item_object.status <> 1 THEN
		result.fail_part := 'asset.copy.status';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
	END IF;

	-- Fail if the item can't circulate because of the shelving location
	SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;
	IF item_location_object.circulate IS FALSE THEN
		result.fail_part := 'asset.copy_location.circulate';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
	END IF;

	SELECT INTO matchpoint_id action.find_circ_matrix_matchpoint(circ_ou, match_item, match_user, renewal);
	result.matchpoint := matchpoint_id;

	SELECT INTO circ_test * from config.circ_matrix_test WHERE matchpoint = result.matchpoint;

	IF circ_test.org_depth IS NOT NULL THEN
		SELECT INTO overdue_orgs ARRAY_ACCUM(id) FROM actor.org_unit_descendants( circ_ou, circ_test.org_depth );
	END IF; 

	-- Fail if we couldn't find a set of tests
	IF result.matchpoint IS NULL THEN
		result.fail_part := 'no_matchpoint';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
	END IF;

	-- Fail if the test is set to hard non-circulating
	IF circ_test.circulate IS FALSE THEN
		result.fail_part := 'config.circ_matrix_test.circulate';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
	END IF;

	-- Fail if the user has too many items checked out
	IF circ_test.max_items_out IS NOT NULL THEN
    	SELECT  INTO items_out COUNT(*)
          FROM  action.circulation
          WHERE usr = match_user
                AND (circ_test.org_depth IS NULL OR (circ_test.org_depth IS NOT NULL AND circ_lib IN ( SELECT * FROM explode_array(overdue_orgs) )))
                AND checkin_time IS NULL
                AND (stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE') OR stop_fines IS NULL);
	   	IF items_out >= circ_test.max_items_out THEN
		    	result.fail_part := 'config.circ_matrix_test.max_items_out';
			result.success := FALSE;
			done := TRUE;
	   		RETURN NEXT result;
   		END IF;
	END IF;

	-- Fail if the user has too many items with specific circ_modifiers checked out
	FOR out_by_circ_mod IN SELECT * FROM config.circ_matrix_circ_mod_test WHERE matchpoint = matchpoint_id LOOP
		SELECT  INTO items_out COUNT(*)
		  FROM  action.circulation circ
			JOIN asset.copy cp ON (cp.id = circ.target_copy)
		  WHERE circ.usr = match_user
                	AND (circ_test.org_depth IS NULL OR (circ_test.org_depth IS NOT NULL AND circ_lib IN ( SELECT * FROM explode_array(overdue_orgs) )))
			AND circ.checkin_time IS NULL
			AND (circ.stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE') OR circ.stop_fines IS NULL)
			AND cp.circ_modifier = out_by_circ_mod.circ_mod;
		IF items_out >= out_by_circ_mod.items_out THEN
			result.fail_part := 'config.circ_matrix_circ_mod_test';
			result.success := FALSE;
			done := TRUE;
			RETURN NEXT result;
		END IF;
	END LOOP;

	-- Fail if the user has too many overdue items
	IF circ_test.max_overdue IS NOT NULL THEN
		SELECT  INTO items_overdue COUNT(*)
		  FROM  action.circulation
		  WHERE usr = match_user
                	AND (circ_test.org_depth IS NULL OR (circ_test.org_depth IS NOT NULL AND circ_lib IN ( SELECT * FROM explode_array(overdue_orgs) )))
			AND checkin_time IS NULL
			AND due_date < NOW()
			AND (stop_fines NOT IN ('LOST','CLAIMSRETURNED','LONGOVERDUE') OR stop_fines IS NULL);
		IF items_overdue >= circ_test.max_overdue THEN
			result.fail_part := 'config.circ_matrix_test.max_overdue';
			result.success := FALSE;
			done := TRUE;
			RETURN NEXT result;
		END IF;
	END IF;

	-- Fail if the user has a high fine balance
	IF circ_test.max_fines IS NOT NULL THEN
		FOR tmp_groc IN SELECT * FROM money.grocery WHERE usr = match_usr AND xact_finish IS NULL AND (circ_test.org_depth IS NULL OR (circ_test.org_depth IS NOT NULL AND billing_location IN ( SELECT * FROM explode_array(overdue_orgs) ))) LOOP
			SELECT INTO tmp_fines SUM( amount ) FROM money.billing WHERE xact = tmp_groc.id AND NOT voided;
			current_fines = current_fines + COALESCE(tmp_fines, 0.0);
			SELECT INTO tmp_fines SUM( amount ) FROM money.payment WHERE xact = tmp_groc.id AND NOT voided;
			current_fines = current_fines - COALESCE(tmp_fines, 0.0);
		END LOOP;

		FOR tmp_circ IN SELECT * FROM action.circulation WHERE usr = match_usr AND xact_finish IS NULL AND (circ_test.org_depth IS NULL OR (circ_test.org_depth IS NOT NULL AND circ_lib IN ( SELECT * FROM explode_array(overdue_orgs) ))) LOOP
			SELECT INTO tmp_fines SUM( amount ) FROM money.billing WHERE xact = tmp_circ.id AND NOT voided;
			current_fines = current_fines + COALESCE(tmp_fines, 0.0);
			SELECT INTO tmp_fines SUM( amount ) FROM money.payment WHERE xact = tmp_circ.id AND NOT voided;
			current_fines = current_fines - COALESCE(tmp_fines, 0.0);
		END LOOP;

		IF current_fines >= circ_test.max_fines THEN
			result.fail_part := 'config.circ_matrix_test.max_fines';
			result.success := FALSE;
			RETURN NEXT result;
			done := TRUE;
		END IF;
	END IF;

	-- If we passed everything, return the successful matchpoint id
	IF NOT done THEN
		RETURN NEXT result;
	END IF;

	RETURN;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION action.item_user_circ_test( INT, BIGINT, INT ) RETURNS SETOF action.matrix_test_result AS $func$
	SELECT * FROM action.item_user_circ_test( $1, $2, $3, FALSE );
$func$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION action.item_user_renew_test( INT, BIGINT, INT ) RETURNS SETOF action.matrix_test_result AS $func$
	SELECT * FROM action.item_user_circ_test( $1, $2, $3, TRUE );
$func$ LANGUAGE SQL;


CREATE TABLE config.hold_matrix_matchpoint (
	id			SERIAL	    PRIMARY KEY,
	active			BOOL	NOT NULL DEFAULT TRUE,
	user_home_ou	INT	    REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,	-- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
	request_ou		INT	    REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,	-- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
	pickup_ou		INT	    REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,	-- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
	item_owning_ou	INT	    REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,	-- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
	item_circ_ou	INT	    REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,	-- Set to the top OU for the matchpoint applicability range; we can use org_unit_prox to choose the "best"
	usr_grp			INT	    REFERENCES permission.grp_tree (id) DEFERRABLE INITIALLY DEFERRED,	-- Set to the top applicable group from the group tree; will need descendents and prox functions for filtering
	requestor_grp	INT	    NOT NULL REFERENCES permission.grp_tree (id) DEFERRABLE INITIALLY DEFERRED,	-- Set to the top applicable group from the group tree; will need descendents and prox functions for filtering
	circ_modifier	TEXT	REFERENCES config.circ_modifier (code) DEFERRABLE INITIALLY DEFERRED,
	marc_type		TEXT	REFERENCES config.item_type_map (code) DEFERRABLE INITIALLY DEFERRED,
	marc_form		TEXT	REFERENCES config.item_form_map (code) DEFERRABLE INITIALLY DEFERRED,
	marc_vr_format	TEXT	REFERENCES config.videorecording_format_map (code) DEFERRABLE INITIALLY DEFERRED,
	ref_flag		BOOL,
	CONSTRAINT hous_once_per_grp_loc_mod_marc UNIQUE (user_home_ou, request_ou, pickup_ou, item_owning_ou, item_circ_ou, requestor_grp, usr_grp, circ_modifier, marc_type, marc_form, marc_vr_format)
);

-- Tests to determine if hold against a specific copy is possible for a user at (and from) a location
CREATE TABLE config.hold_matrix_test (
	matchpoint		        INT	PRIMARY KEY REFERENCES config.hold_matrix_matchpoint (id) DEFERRABLE INITIALLY DEFERRED,
	holdable		        BOOL	NOT NULL DEFAULT TRUE,				-- Hard "can't hold" flag requiring an override
	distance_is_from_owner	BOOL	NOT NULL DEFAULT FALSE,				-- How to calculate transit_range.  True means owning lib, false means copy circ lib
	transit_range		    INT	REFERENCES actor.org_unit_type (id) DEFERRABLE INITIALLY DEFERRED,		-- Can circ inside range of cn.owner/cp.circ_lib at depth of the org_unit_type specified here
	max_holds		        INT,							-- Total hold requests must be less than this, NULL means skip (always pass)
	include_frozen_holds	BOOL	NOT NULL DEFAULT TRUE,				-- Include frozen hold requests in the count for max_holds test
	stop_blocked_user   	BOOL	NOT NULL DEFAULT FALSE,				-- Stop users who cannot check out items from placing holds
	age_hold_protect_rule	INT	REFERENCES config.rule_age_hold_protect (id) DEFERRABLE INITIALLY DEFERRED	-- still not sure we want to move this off the copy
);

CREATE OR REPLACE FUNCTION action.find_hold_matrix_matchpoint( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS INT AS $func$
DECLARE
	current_requestor_group	permission.grp_tree%ROWTYPE;
	root_ou			actor.org_unit%ROWTYPE;
	requestor_object	actor.usr%ROWTYPE;
	user_object		actor.usr%ROWTYPE;
	item_object		asset.copy%ROWTYPE;
	item_cn_object		asset.call_number%ROWTYPE;
	rec_descriptor		metabib.rec_descriptor%ROWTYPE;
	current_mp_weight	FLOAT;
	matchpoint_weight	FLOAT;
	tmp_weight		FLOAT;
	current_mp		config.hold_matrix_matchpoint%ROWTYPE;
	matchpoint		config.hold_matrix_matchpoint%ROWTYPE;
BEGIN
	SELECT INTO root_ou * FROM actor.org_unit WHERE parent_ou IS NULL;
	SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
	SELECT INTO requestor_object * FROM actor.usr WHERE id = match_requestor;
	SELECT INTO item_object * FROM asset.copy WHERE id = match_item;
	SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
	SELECT INTO rec_descriptor r.* FROM metabib.rec_descriptor r WHERE r.record = item_cn_object.record;
	SELECT INTO current_requestor_group * FROM permission.grp_tree WHERE id = requestor_object.profile;

	LOOP 
		-- for each potential matchpoint for this ou and group ...
		FOR current_mp IN
			SELECT	m.*
			  FROM	config.hold_matrix_matchpoint m
			  WHERE	m.requestor_grp = current_requestor_group.id AND m.active
			  ORDER BY	CASE WHEN m.circ_modifier	IS NOT NULL THEN 16 ELSE 0 END +
					CASE WHEN m.marc_type		IS NOT NULL THEN 8 ELSE 0 END +
					CASE WHEN m.marc_form		IS NOT NULL THEN 4 ELSE 0 END +
					CASE WHEN m.marc_vr_format	IS NOT NULL THEN 2 ELSE 0 END +
					CASE WHEN m.ref_flag		IS NOT NULL THEN 1 ELSE 0 END DESC LOOP

			current_mp_weight := 5.0;

			IF current_mp.circ_modifier IS NOT NULL THEN
				CONTINUE WHEN current_mp.circ_modifier <> item_object.circ_modifier;
			END IF;

			IF current_mp.marc_type IS NOT NULL THEN
				IF item_object.circ_as_type IS NOT NULL THEN
					CONTINUE WHEN current_mp.marc_type <> item_object.circ_as_type;
				ELSE
					CONTINUE WHEN current_mp.marc_type <> rec_descriptor.item_type;
				END IF;
			END IF;

			IF current_mp.marc_form IS NOT NULL THEN
				CONTINUE WHEN current_mp.marc_form <> rec_descriptor.item_form;
			END IF;

			IF current_mp.marc_vr_format IS NOT NULL THEN
				CONTINUE WHEN current_mp.marc_vr_format <> rec_descriptor.vr_format;
			END IF;

			IF current_mp.ref_flag IS NOT NULL THEN
				CONTINUE WHEN current_mp.ref_flag <> item_object.ref;
			END IF;


			-- caclulate the rule match weight
			IF current_mp.item_owning_ou IS NOT NULL AND current_mp.item_owning_ou <> root_ou.id THEN
				SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.item_owning_ou, item_cn_object.owning_lib)::FLOAT + 1.0)::FLOAT;
				current_mp_weight := current_mp_weight - tmp_weight;
			END IF; 

			IF current_mp.item_circ_ou IS NOT NULL AND current_mp.item_circ_ou <> root_ou.id THEN
				SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.item_circ_ou, item_object.circ_lib)::FLOAT + 1.0)::FLOAT;
				current_mp_weight := current_mp_weight - tmp_weight;
			END IF; 

			IF current_mp.pickup_ou IS NOT NULL AND current_mp.pickup_ou <> root_ou.id THEN
				SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.pickup_ou, pickup_ou)::FLOAT + 1.0)::FLOAT;
				current_mp_weight := current_mp_weight - tmp_weight;
			END IF; 

			IF current_mp.request_ou IS NOT NULL AND current_mp.request_ou <> root_ou.id THEN
				SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.request_ou, request_ou)::FLOAT + 1.0)::FLOAT;
				current_mp_weight := current_mp_weight - tmp_weight;
			END IF; 

			IF current_mp.user_home_ou IS NOT NULL AND current_mp.user_home_ou <> root_ou.id THEN
				SELECT INTO tmp_weight 1.0 / (actor.org_unit_proximity(current_mp.user_home_ou, user_object.home_ou)::FLOAT + 1.0)::FLOAT;
				current_mp_weight := current_mp_weight - tmp_weight;
			END IF; 

			-- set the matchpoint if we found the best one
			IF matchpoint_weight IS NULL OR matchpoint_weight > current_mp_weight THEN
				matchpoint = current_mp;
				matchpoint_weight = current_mp_weight;
			END IF;

		END LOOP;

		EXIT WHEN current_requestor_group.parent IS NULL OR matchpoint.id IS NOT NULL;

		SELECT INTO current_requestor_group * FROM permission.grp_tree WHERE id = current_requestor_group.parent;
	END LOOP;

	RETURN matchpoint.id;
END;
$func$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
	matchpoint_id		INT;
	user_object		actor.usr%ROWTYPE;
	age_protect_object	config.rule_age_hold_protect%ROWTYPE;
	transit_range_ou_type	actor.org_unit_type%ROWTYPE;
	transit_source		actor.org_unit%ROWTYPE;
	item_object		asset.copy%ROWTYPE;
	result			action.matrix_test_result;
	hold_test		config.hold_matrix_test%ROWTYPE;
	hold_count		INT;
	hold_transit_prox	INT;
	frozen_hold_count	INT;
	patron_penalties	INT;
	done			BOOL := FALSE;
BEGIN
	SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

	-- Fail if we couldn't find a user
	IF user_object.id IS NULL THEN
		result.fail_part := 'no_user';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
		RETURN;
	END IF;

	-- Fail if user is barred
	IF user_object.barred IS TRUE THEN
		result.fail_part := 'actor.usr.barred';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
		RETURN;
	END IF;

	SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

	-- Fail if we couldn't find a copy
	IF item_object.id IS NULL THEN
		result.fail_part := 'no_item';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
		RETURN;
	END IF;

	SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(pickup_ou, request_ou, match_item, match_user, match_requestor);

	-- Fail if we couldn't find any matchpoint (requires a default)
	IF matchpoint_id IS NULL THEN
		result.fail_part := 'no_matchpoint';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
		RETURN;
	END IF;

	SELECT INTO hold_test * FROM config.hold_matrix_test WHERE matchpoint = matchpoint_id;

	result.matchpoint := matchpoint_id;
	result.success := TRUE;

	IF hold_test.holdable IS FALSE THEN
		result.fail_part := 'config.hold_matrix_test.holdable';
		result.success := FALSE;
		done := TRUE;
		RETURN NEXT result;
	END IF;

	IF hold_test.transit_range IS NOT NULL THEN
		SELECT INTO transit_range_ou_type * FROM actor.org_unit_type WHERE id = hold_test.transit_range;
		IF hold_test.distance_is_from_owner THEN
			SELECT INTO transit_source ou.* FROM actor.org_unit ou JOIN asset.call_number cn ON (cn.owning_lib = ou.id) WHERE cn.id = item_object.call_number;
		ELSE
			SELECT INTO transit_source * FROM actor.org_unit WHERE id = item_object.circ_lib;
		END IF;

		PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = pickup_ou;

		IF NOT FOUND THEN
			result.fail_part := 'transit_range';
			result.success := FALSE;
			done := TRUE;
			RETURN NEXT result;
		END IF;
	END IF;

	IF hold_test.stop_blocked_user IS TRUE THEN
		SELECT	INTO patron_penalties COUNT(*)
		  FROM	actor.usr_standing_penalty
		  WHERE	usr = match_user;

		IF items_out > 0 THEN
			result.fail_part := 'config.hold_matrix_test.stop_blocked_user';
			result.success := FALSE;
			done := TRUE;
			RETURN NEXT result;
		END IF;
	END IF;

	IF hold_test.max_holds IS NOT NULL THEN
		SELECT	INTO hold_count COUNT(*)
		  FROM	action.hold_request
		  WHERE	usr = match_user
			AND fulfillment_time IS NULL
			AND cancel_time IS NULL
			AND CASE WHEN hold_test.include_frozen_holds THEN TRUE ELSE frozen IS FALSE END;

		IF items_out >= hold_test.max_holds THEN
			result.fail_part := 'config.hold_matrix_test.max_holds';
			result.success := FALSE;
			done := TRUE;
			RETURN NEXT result;
		END IF;
	END IF;

	IF item_object.age_protect IS NOT NULL THEN
		SELECT INTO age_protect_object * FROM config.rule_age_hold_protect WHERE id = item_object.age_protect;

		IF item_object.create_date + age_protect_object.age > NOW() THEN
			IF hold_test.distance_is_from_owner THEN
				SELECT INTO hold_transit_prox prox FROM actor.org_unit_prox WHERE from_org = item_cn_object.owning_lib AND to_org = pickup_ou;
			ELSE
				SELECT INTO hold_transit_prox prox FROM actor.org_unit_prox WHERE from_org = item_object.circ_lib AND to_org = pickup_ou;
			END IF;

			IF hold_transit_prox > age_protect_object.prox THEN
				result.fail_part := 'config.rule_age_hold_protect.prox';
				result.success := FALSE;
				done := TRUE;
				RETURN NEXT result;
			END IF;
		END IF;
	END IF;

	IF NOT done THEN
		RETURN NEXT result;
	END IF;

	RETURN;
END;
$func$ LANGUAGE plpgsql;

INSERT INTO config.circ_matrix_matchpoint (org_unit,grp) VALUES (1,1);
INSERT INTO config.circ_matrix_ruleset (matchpoint,duration_rule,recurring_fine_rule,max_fine_rule) VALUES (1,11,1,1);
INSERT INTO config.hold_matrix_matchpoint (requestor_grp) VALUES (1);

-- COMMIT;

