--Upgrade Script for 3.3.4 to 3.3.5
\set eg_version '''3.3.5'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.3.5', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1185', :eg_version); -- csharp / gmcharlt / jboyer

ALTER FUNCTION permission.grp_descendants( INT ) STABLE;


SELECT evergreen.upgrade_deps_block_check('1187', :eg_version);

CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
DECLARE
found char := 'N';
BEGIN

    -- If there are any renewals for this circulation, don't archive or delete
    -- it yet.   We'll do so later, when we archive and delete the renewals.

    SELECT 'Y' INTO found
    FROM action.circulation
    WHERE parent_circ = OLD.id
    LIMIT 1;

    IF found = 'Y' THEN
        RETURN NULL;  -- don't delete
	END IF;

    -- Archive a copy of the old row to action.aged_circulation

    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining
        FROM action.all_circulation WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';



SELECT evergreen.upgrade_deps_block_check('1188', :eg_version);

UPDATE action.circulation SET auto_renewal = FALSE WHERE auto_renewal IS NULL;

UPDATE action.aged_circulation SET auto_renewal = FALSE WHERE auto_renewal IS NULL;


-- The following two changes cannot occur in a transaction with the
-- above updates because we will get an error about not being able to
-- alter a table with pending transactions.  They also need to occur
-- after the above updates or the SET NOT NULL change will fail.

ALTER TABLE action.circulation ALTER COLUMN auto_renewal SET DEFAULT FALSE;
ALTER TABLE action.circulation ALTER COLUMN auto_renewal SET NOT NULL;

ALTER TABLE action.aged_circulation ALTER COLUMN auto_renewal SET DEFAULT FALSE;
ALTER TABLE action.aged_circulation ALTER COLUMN auto_renewal SET NOT NULL;

SELECT evergreen.upgrade_deps_block_check('1189', :eg_version);

CREATE OR REPLACE VIEW action.open_circulation AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	checkin_time IS NULL
	  ORDER BY due_date;

CREATE OR REPLACE VIEW action.billable_circulations AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	xact_finish IS NULL;

CREATE OR REPLACE VIEW reporter.overdue_circs AS
SELECT  *
  FROM  "action".circulation
  WHERE checkin_time is null
        AND (stop_fines NOT IN ('LOST','CLAIMSRETURNED') OR stop_fines IS NULL)
        AND due_date < now();

CREATE OR REPLACE VIEW reporter.circ_type AS
SELECT	id,
	CASE WHEN opac_renewal OR phone_renewal OR desk_renewal OR auto_renewal
		THEN 'RENEWAL'
		ELSE 'CHECKOUT'
	END AS "type"
  FROM	action.circulation;


SELECT evergreen.upgrade_deps_block_check('1190', :eg_version);

UPDATE action.circulation SET desk_renewal = FALSE WHERE auto_renewal IS TRUE;

UPDATE action.aged_circulation SET desk_renewal = FALSE WHERE auto_renewal IS TRUE;


SELECT evergreen.upgrade_deps_block_check('1191', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) SELECT DISTINCT
  619,
  'EDIT_SELF_IN_CLIENT',
  oils_i18n_gettext(619,
    'Allow a user to edit their own account in the staff client', 'ppl', 'description'
  )
  FROM permission.perm_list
  WHERE NOT EXISTS (SELECT 1 FROM permission.perm_list WHERE code = 'EDIT_SELF_IN_CLIENT');


SELECT evergreen.upgrade_deps_block_check('1193', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.circ.patron.xact_details_details_bills', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.circ.patron.xact_details_details_bills',
    'Grid Config: circ.patron.xact_details_details_bills',
    'cwst', 'label')
), (
    'eg.grid.circ.patron.xact_details_details_payments', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.circ.patron.xact_details_details_payments',
    'Grid Config: circ.patron.xact_details_details_payments',
    'cwst', 'label')
);


SELECT evergreen.upgrade_deps_block_check('1195', :eg_version);

CREATE OR REPLACE FUNCTION metabib.suggest_browse_entries(raw_query_text text, search_class text, headline_opts text, visibility_org integer, query_limit integer, normalization integer)
 RETURNS TABLE(value text, field integer, buoyant_and_class_match boolean, field_match boolean, field_weight integer, rank real, buoyant boolean, match text)
AS $f$
DECLARE
    prepared_query_texts    TEXT[];
    query                   TSQUERY;
    plain_query             TSQUERY;
    opac_visibility_join    TEXT;
    search_class_join       TEXT;
    r_fields                RECORD;
    b_tests                 TEXT := '';
BEGIN
    prepared_query_texts := metabib.autosuggest_prepare_tsquery(raw_query_text);

    query := TO_TSQUERY('keyword', prepared_query_texts[1]);
    plain_query := TO_TSQUERY('keyword', prepared_query_texts[2]);

    visibility_org := NULLIF(visibility_org,-1);
    IF visibility_org IS NOT NULL THEN
        PERFORM FROM actor.org_unit WHERE id = visibility_org AND parent_ou IS NULL;
        IF FOUND THEN
            opac_visibility_join := '';
        ELSE
            PERFORM 1 FROM config.internal_flag WHERE enabled AND name = 'opac.located_uri.act_as_copy';
            IF FOUND THEN
                b_tests := search.calculate_visibility_attribute_test(
                    'luri_org',
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_full_path(visibility_org))
                );
            ELSE
                b_tests := search.calculate_visibility_attribute_test(
                    'luri_org',
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_ancestors(visibility_org))
                );
            END IF;
            opac_visibility_join := '
    LEFT JOIN asset.copy_vis_attr_cache acvac ON (acvac.record = x.source)
    LEFT JOIN biblio.record_entry b ON (b.id = x.source)
    JOIN vm ON (acvac.vis_attr_vector @@
            (vm.c_attrs || $$&$$ ||
                search.calculate_visibility_attribute_test(
                    $$circ_lib$$,
                    (SELECT ARRAY_AGG(id) FROM actor.org_unit_descendants($4))
                )
            )::query_int
         ) OR (b.vis_attr_vector @@ $$' || b_tests || '$$::query_int)
';
        END IF;
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
WITH vm AS ( SELECT * FROM asset.patron_default_visibility_mask() ),
     mbe AS (SELECT * FROM metabib.browse_entry WHERE index_vector @@ $1 LIMIT 10000)
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
                JOIN mbe ON (mbe.id = mbedm.entry)
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
$f$ LANGUAGE plpgsql ROWS 10;

COMMIT;
