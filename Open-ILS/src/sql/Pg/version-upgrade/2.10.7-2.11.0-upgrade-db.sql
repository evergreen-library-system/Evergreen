--Upgrade Script for 2.10.7 to 2.11.0
\set eg_version '''2.11.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.11.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0979', :eg_version);

-- Replace connectby from the tablefunc extension with CTEs


CREATE OR REPLACE FUNCTION permission.grp_ancestors( INT ) RETURNS SETOF permission.grp_tree AS $$
    WITH RECURSIVE grp_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent, ouad.distance+1
            FROM permission.grp_tree ou JOIN grp_ancestors_distance ouad ON (ou.id = ouad.id)
            WHERE ou.parent IS NOT NULL
    )
    SELECT ou.* FROM permission.grp_tree ou JOIN grp_ancestors_distance ouad USING (id) ORDER BY ouad.distance DESC;
$$ LANGUAGE SQL ROWS 1;

-- Add a utility function to find descendant groups.

CREATE OR REPLACE FUNCTION permission.grp_descendants( INT ) RETURNS SETOF permission.grp_tree AS $$
    WITH RECURSIVE descendant_depth AS (
        SELECT  gr.id,
                gr.parent
          FROM  permission.grp_tree gr
          WHERE gr.id = $1
            UNION ALL
        SELECT  gr.id,
                gr.parent
          FROM  permission.grp_tree gr
                JOIN descendant_depth dd ON (dd.id = gr.parent)
    ) SELECT gr.* FROM permission.grp_tree gr JOIN descendant_depth USING (id);
$$ LANGUAGE SQL ROWS 1;

-- Add utility functions to work with permission groups as general tree-ish sets.

CREATE OR REPLACE FUNCTION permission.grp_tree_full_path ( INT ) RETURNS SETOF permission.grp_tree AS $$
        SELECT  *
          FROM  permission.grp_ancestors($1)
                        UNION
        SELECT  *
          FROM  permission.grp_descendants($1);
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION permission.grp_tree_combined_ancestors ( INT, INT ) RETURNS SETOF permission.grp_tree AS $$
        SELECT  *
          FROM  permission.grp_ancestors($1)
                        UNION
        SELECT  *
          FROM  permission.grp_ancestors($2);
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION permission.grp_tree_common_ancestors ( INT, INT ) RETURNS SETOF permission.grp_tree AS $$
        SELECT  *
          FROM  permission.grp_ancestors($1)
                        INTERSECT
        SELECT  *
          FROM  permission.grp_ancestors($2);
$$ LANGUAGE SQL STABLE ROWS 1;



SELECT evergreen.upgrade_deps_block_check('0980', :eg_version);

ALTER TABLE vandelay.merge_profile ADD COLUMN update_bib_source BOOLEAN NOT NULL DEFAULT false;
UPDATE vandelay.merge_profile SET update_bib_source = true WHERE id=2;

CREATE OR REPLACE FUNCTION vandelay.overlay_bib_record ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    editor_string   TEXT;
    editor_id       INT;
    v_marc          TEXT;
    v_bib_source    INT;
    update_fields   TEXT[];
    update_query    TEXT;
    update_bib      BOOL;
BEGIN

    SELECT  q.marc, q.bib_source INTO v_marc, v_bib_source
      FROM  vandelay.queued_bib_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or bib record';
        RETURN FALSE;
    END IF;

    IF vandelay.template_overlay_bib_record( v_marc, eg_id, merge_profile_id) THEN
        UPDATE  vandelay.queued_bib_record
          SET   imported_as = eg_id,
                import_time = NOW()
          WHERE id = import_id;

	  SELECT q.update_bib_source INTO update_bib FROM vandelay.merge_profile q where q.id = merge_profile_id;

          IF update_bib THEN
		editor_string := (oils_xpath('//*[@tag="905"]/*[@code="u"]/text()',v_marc))[1];

		IF editor_string IS NOT NULL AND editor_string <> '' THEN
		    SELECT usr INTO editor_id FROM actor.card WHERE barcode = editor_string;

		    IF editor_id IS NULL THEN
			SELECT id INTO editor_id FROM actor.usr WHERE usrname = editor_string;
		    END IF;

		    IF editor_id IS NOT NULL THEN
			--only update the edit date if we have a valid editor
			update_fields := ARRAY_APPEND(update_fields, 'editor = ' || editor_id || ', edit_date = NOW()');
		    END IF;
		END IF;

		IF v_bib_source IS NOT NULL THEN
		    update_fields := ARRAY_APPEND(update_fields, 'source = ' || v_bib_source);
		END IF;

		IF ARRAY_LENGTH(update_fields, 1) > 0 THEN
		    update_query := 'UPDATE biblio.record_entry SET ' || ARRAY_TO_STRING(update_fields, ',') || ' WHERE id = ' || eg_id || ';';
		    --RAISE NOTICE 'query: %', update_query;
		    EXECUTE update_query;
		END IF;
        END IF;

        RETURN TRUE;
    END IF;

    -- RAISE NOTICE 'update of biblio.record_entry failed';

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('0982', :eg_version);

CREATE OR REPLACE FUNCTION permission.usr_has_perm_at_nd(
	user_id    IN INTEGER,
	perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
--
-- Return a set of all the org units for which a given user has a given
-- permission, granted directly (not through inheritance from a parent
-- org unit).
--
-- The permissions apply to a minimum depth of the org unit hierarchy,
-- for the org unit(s) to which the user is assigned.  (They also apply
-- to the subordinates of those org units, but we don't report the
-- subordinates here.)
--
-- For purposes of this function, the permission.usr_work_ou_map table
-- defines which users belong to which org units.  I.e. we ignore the
-- home_ou column of actor.usr.
--
-- The result set may contain duplicates, which should be eliminated
-- by a DISTINCT clause.
--
DECLARE
	b_super       BOOLEAN;
	n_perm        INTEGER;
	n_min_depth   INTEGER; 
	n_work_ou     INTEGER;
	n_curr_ou     INTEGER;
	n_depth       INTEGER;
	n_curr_depth  INTEGER;
BEGIN
	--
	-- Check for superuser
	--
	SELECT INTO b_super
		super_user
	FROM
		actor.usr
	WHERE
		id = user_id;
	--
	IF NOT FOUND THEN
		return;				-- No user?  No permissions.
	ELSIF b_super THEN
		--
		-- Super user has all permissions everywhere
		--
		FOR n_work_ou IN
			SELECT
				id
			FROM
				actor.org_unit
			WHERE
				parent_ou IS NULL
		LOOP
			RETURN NEXT n_work_ou; 
		END LOOP;
		RETURN;
	END IF;
	--
	-- Translate the permission name
	-- to a numeric permission id
	--
	SELECT INTO n_perm
		id
	FROM
		permission.perm_list
	WHERE
		code = perm_code;
	--
	IF NOT FOUND THEN
		RETURN;               -- No such permission
	END IF;
	--
	-- Find the highest-level org unit (i.e. the minimum depth)
	-- to which the permission is applied for this user
	--
	-- This query is modified from the one in permission.usr_perms().
	--
	SELECT INTO n_min_depth
		min( depth )
	FROM	(
		SELECT depth 
		  FROM permission.usr_perm_map upm
		 WHERE upm.usr = user_id 
		   AND (upm.perm = n_perm OR upm.perm = -1)
       				UNION
		SELECT	gpm.depth
		  FROM	permission.grp_perm_map gpm
		  WHERE	(gpm.perm = n_perm OR gpm.perm = -1)
	        AND gpm.grp IN (
	 		   SELECT	(permission.grp_ancestors(
					(SELECT profile FROM actor.usr WHERE id = user_id)
				)).id
			)
       				UNION
		SELECT	p.depth
		  FROM	permission.grp_perm_map p 
		  WHERE (p.perm = n_perm OR p.perm = -1)
		    AND p.grp IN (
		  		SELECT (permission.grp_ancestors(m.grp)).id 
				FROM   permission.usr_grp_map m
				WHERE  m.usr = user_id
			)
	) AS x;
	--
	IF NOT FOUND THEN
		RETURN;                -- No such permission for this user
	END IF;
	--
	-- Identify the org units to which the user is assigned.  Note that
	-- we pay no attention to the home_ou column in actor.usr.
	--
	FOR n_work_ou IN
		SELECT
			work_ou
		FROM
			permission.usr_work_ou_map
		WHERE
			usr = user_id
	LOOP            -- For each org unit to which the user is assigned
		--
		-- Determine the level of the org unit by a lookup in actor.org_unit_type.
		-- We take it on faith that this depth agrees with the actual hierarchy
		-- defined in actor.org_unit.
		--
		SELECT INTO n_depth
		    type.depth
		FROM
		    actor.org_unit_type type
		        INNER JOIN actor.org_unit ou
		            ON ( ou.ou_type = type.id )
		WHERE
		    ou.id = n_work_ou;
		--
		IF NOT FOUND THEN
			CONTINUE;        -- Maybe raise exception?
		END IF;
		--
		-- Compare the depth of the work org unit to the
		-- minimum depth, and branch accordingly
		--
		IF n_depth = n_min_depth THEN
			--
			-- The org unit is at the right depth, so return it.
			--
			RETURN NEXT n_work_ou;
		ELSIF n_depth > n_min_depth THEN
			--
			-- Traverse the org unit tree toward the root,
			-- until you reach the minimum depth determined above
			--
			n_curr_depth := n_depth;
			n_curr_ou := n_work_ou;
			WHILE n_curr_depth > n_min_depth LOOP
				SELECT INTO n_curr_ou
					parent_ou
				FROM
					actor.org_unit
				WHERE
					id = n_curr_ou;
				--
				IF FOUND THEN
					n_curr_depth := n_curr_depth - 1;
				ELSE
					--
					-- This can happen only if the hierarchy defined in
					-- actor.org_unit is corrupted, or out of sync with
					-- the depths defined in actor.org_unit_type.
					-- Maybe we should raise an exception here, instead
					-- of silently ignoring the problem.
					--
					n_curr_ou = NULL;
					EXIT;
				END IF;
			END LOOP;
			--
			IF n_curr_ou IS NOT NULL THEN
				RETURN NEXT n_curr_ou;
			END IF;
		ELSE
			--
			-- The permission applies only at a depth greater than the work org unit.
			-- Use connectby() to find all dependent org units at the specified depth.
			--
			FOR n_curr_ou IN
				SELECT id
				FROM actor.org_unit_descendants_distance(n_work_ou)
				WHERE
					distance = n_min_depth - n_depth
			LOOP
				RETURN NEXT n_curr_ou;
			END LOOP;
		END IF;
		--
	END LOOP;
	--
	RETURN;
	--
END;
$$ LANGUAGE 'plpgsql' ROWS 1;


CREATE OR REPLACE FUNCTION permission.usr_has_perm_at_all_nd(
	user_id    IN INTEGER,
	perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
--
-- Return a set of all the org units for which a given user has a given
-- permission, granted either directly or through inheritance from a parent
-- org unit.
--
-- The permissions apply to a minimum depth of the org unit hierarchy, and
-- to the subordinates of those org units, for the org unit(s) to which the
-- user is assigned.
--
-- For purposes of this function, the permission.usr_work_ou_map table
-- assigns users to org units.  I.e. we ignore the home_ou column of actor.usr.
--
-- The result set may contain duplicates, which should be eliminated
-- by a DISTINCT clause.
--
DECLARE
	n_head_ou     INTEGER;
	n_child_ou    INTEGER;
BEGIN
	FOR n_head_ou IN
		SELECT DISTINCT * FROM permission.usr_has_perm_at_nd( user_id, perm_code )
	LOOP
		--
		-- The permission applies only at a depth greater than the work org unit.
		--
		FOR n_child_ou IN
            SELECT id
            FROM actor.org_unit_descendants(n_head_ou)
		LOOP
			RETURN NEXT n_child_ou;
		END LOOP;
	END LOOP;
	--
	RETURN;
	--
END;
$$ LANGUAGE 'plpgsql' ROWS 1;


\qecho The tablefunc database extension is no longer necessary for Evergreen.
\qecho Unless you use some of its functions in your own scripts, you may
\qecho want to run the following command in the database to drop it:
\qecho DROP EXTENSION tablefunc;


SELECT evergreen.upgrade_deps_block_check('0983', :eg_version);

-- Create these so that the queries in the UDFs will validate
CREATE TEMP TABLE precalc_filter_bib_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bib_filter_bib_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_src_filter_bib_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_copy_filter_bib_list (
    id  BIGINT,
    copy  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_circ_mod_filter_bib_list (
    id  BIGINT,
    copy  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_location_filter_bib_list (
    id  BIGINT,
    copy  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_attr_filter_bib_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bibs_by_copy_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bibs_by_uri_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bibs_by_copy_or_uri_list (
    id  BIGINT
) ON COMMIT DROP;

CREATE TEMP TABLE precalc_bib_list (
    id  BIGINT
) ON COMMIT DROP;

-- rhrr needs to be a real table, so it can be fast. To that end, we use
-- a materialized view updated via a trigger.

DROP VIEW reporter.hold_request_record;

CREATE TABLE reporter.hold_request_record  AS
SELECT  id,
        target,
        hold_type,
        CASE
                WHEN hold_type = 'T'
                        THEN target
                WHEN hold_type = 'I'
                        THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = ahr.target)
                WHEN hold_type = 'V'
                        THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = ahr.target)
                WHEN hold_type IN ('C','R','F')
                        THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = ahr.target)
                WHEN hold_type = 'M'
                        THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = ahr.target)
                WHEN hold_type = 'P'
                        THEN (SELECT bmp.record FROM biblio.monograph_part bmp WHERE bmp.id = ahr.target)
        END AS bib_record
  FROM  action.hold_request ahr;

CREATE UNIQUE INDEX reporter_hold_request_record_pkey_idx ON reporter.hold_request_record (id);
CREATE INDEX reporter_hold_request_record_bib_record_idx ON reporter.hold_request_record (bib_record);

ALTER TABLE reporter.hold_request_record ADD PRIMARY KEY USING INDEX reporter_hold_request_record_pkey_idx;

CREATE FUNCTION reporter.hold_request_record_mapper () RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO reporter.hold_request_record (id, target, hold_type, bib_record)
        SELECT  NEW.id,
                NEW.target,
                NEW.hold_type,
                CASE
                    WHEN NEW.hold_type = 'T'
                        THEN NEW.target
                    WHEN NEW.hold_type = 'I'
                        THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = NEW.target)
                    WHEN NEW.hold_type = 'V'
                        THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = NEW.target)
                    WHEN NEW.hold_type IN ('C','R','F')
                        THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = NEW.target)
                    WHEN NEW.hold_type = 'M'
                        THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = NEW.target)
                    WHEN NEW.hold_type = 'P'
                        THEN (SELECT bmp.record FROM biblio.monograph_part bmp WHERE bmp.id = NEW.target)
                END AS bib_record;
    ELSIF TG_OP = 'UPDATE' AND (OLD.target <> NEW.target OR OLD.hold_type <> NEW.hold_type) THEN
        UPDATE  reporter.hold_request_record
          SET   target = NEW.target,
                hold_type = NEW.hold_type,
                bib_record = CASE
                    WHEN NEW.hold_type = 'T'
                        THEN NEW.target
                    WHEN NEW.hold_type = 'I'
                        THEN (SELECT ssub.record_entry FROM serial.subscription ssub JOIN serial.issuance si ON (si.subscription = ssub.id) WHERE si.id = NEW.target)
                    WHEN NEW.hold_type = 'V'
                        THEN (SELECT cn.record FROM asset.call_number cn WHERE cn.id = NEW.target)
                    WHEN NEW.hold_type IN ('C','R','F')
                        THEN (SELECT cn.record FROM asset.call_number cn JOIN asset.copy cp ON (cn.id = cp.call_number) WHERE cp.id = NEW.target)
                    WHEN NEW.hold_type = 'M'
                        THEN (SELECT mr.master_record FROM metabib.metarecord mr WHERE mr.id = NEW.target)
                    WHEN NEW.hold_type = 'P'
                        THEN (SELECT bmp.record FROM biblio.monograph_part bmp WHERE bmp.id = NEW.target)
                END;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER reporter_hold_request_record_trigger AFTER INSERT OR UPDATE ON action.hold_request
    FOR EACH ROW EXECUTE PROCEDURE reporter.hold_request_record_mapper();

CREATE SCHEMA rating;

INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'opac.default_sort',
    'OPAC Default Sort (titlesort, authorsort, pubdate, popularity, poprel, or empty for relevance)',
    '',
    TRUE
);

INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'search.max_popularity_importance_multiplier',
    oils_i18n_gettext(
        'search.max_popularity_importance_multiplier',
        'Maximum popularity importance multiplier for popularity-adjusted relevance searches (decimal value between 1.0 and 2.0)',
        'cgf',
        'label'
    ),
    '1.1',
    TRUE
);

CREATE TABLE rating.popularity_parameter (
    id          INT     PRIMARY KEY,
    name        TEXT    NOT NULL UNIQUE, -- i18n
    description TEXT,
    func        TEXT,
    require_horizon     BOOL    NOT NULL DEFAULT FALSE,
    require_importance  BOOL    NOT NULL DEFAULT FALSE,
    require_percentile  BOOL    NOT NULL DEFAULT FALSE
);

INSERT INTO rating.popularity_parameter (id,name,func,require_horizon,require_importance,require_percentile) VALUES
    (1,'Holds Filled Over Time','rating.holds_filled_over_time',TRUE,FALSE,TRUE),
    (2,'Holds Requested Over Time','rating.holds_placed_over_time',TRUE,FALSE,TRUE),
    (3,'Current Hold Count','rating.current_hold_count',FALSE,FALSE,TRUE),
    (4,'Circulations Over Time','rating.circs_over_time',TRUE,FALSE,TRUE),
    (5,'Current Circulation Count','rating.current_circ_count',FALSE,FALSE,TRUE),
    (6,'Out/Total Ratio','rating.checked_out_total_ratio',FALSE,FALSE,TRUE),
    (7,'Holds/Total Ratio','rating.holds_total_ratio',FALSE,FALSE,TRUE),
    (8,'Holds/Holdable Ratio','rating.holds_holdable_ratio',FALSE,FALSE,TRUE),
    (9,'Percent of Time Circulating','rating.percent_time_circulating',FALSE,FALSE,TRUE),
    (10,'Bibliographic Record Age (days, newer is better)','rating.bib_record_age',FALSE,FALSE,TRUE),
    (11,'Publication Age (days, newer is better)','rating.bib_pub_age',FALSE,FALSE,TRUE),
    (12,'On-line Bib has attributes','rating.generic_fixed_rating_by_uri',FALSE,FALSE,FALSE),
    (13,'Bib has attributes and copies','rating.generic_fixed_rating_by_copy',FALSE,FALSE,FALSE),
    (14,'Bib has attributes and copies or URIs','rating.generic_fixed_rating_by_copy_or_uri',FALSE,FALSE,FALSE),
    (15,'Bib has attributes','rating.generic_fixed_rating_global',FALSE,FALSE,FALSE);

CREATE TABLE rating.badge (
    id                      SERIAL      PRIMARY KEY,
    name                    TEXT        NOT NULL,
    description             TEXT,
    scope                   INT         NOT NULL REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    weight                  INT         NOT NULL DEFAULT 1,
    horizon_age             INTERVAL,
    importance_age          INTERVAL,
    importance_interval     INTERVAL    NOT NULL DEFAULT '1 day',
    importance_scale        NUMERIC     CHECK (importance_scale IS NULL OR importance_scale > 0.0),
    recalc_interval         INTERVAL    NOT NULL DEFAULT '1 month',
    attr_filter             TEXT,
    src_filter              INT         REFERENCES config.bib_source (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    circ_mod_filter         TEXT        REFERENCES config.circ_modifier (code) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    loc_grp_filter          INT         REFERENCES asset.copy_location_group (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    popularity_parameter    INT         NOT NULL REFERENCES rating.popularity_parameter (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    fixed_rating            INT         CHECK (fixed_rating IS NULL OR fixed_rating BETWEEN -5 AND 5),
    percentile              NUMERIC     CHECK (percentile IS NULL OR (percentile >= 50.0 AND percentile < 100.0)),
    discard                 INT         NOT NULL DEFAULT 0, 
    last_calc               TIMESTAMPTZ,
    CONSTRAINT unique_name_scope UNIQUE (name,scope)
);

CREATE TABLE rating.record_badge_score (
    id          BIGSERIAL   PRIMARY KEY,
    record      BIGINT      NOT NULL REFERENCES biblio.record_entry (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    badge       INT         NOT NULL REFERENCES rating.badge (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    score       INT         NOT NULL CHECK (score BETWEEN -5 AND 5),
    CONSTRAINT unique_record_badge UNIQUE (record,badge)
);
CREATE INDEX record_badge_score_badge_idx ON rating.record_badge_score (badge);
CREATE INDEX record_badge_score_record_idx ON rating.record_badge_score (record);

CREATE OR REPLACE VIEW rating.badge_with_orgs AS
    WITH    org_scope AS (
                SELECT  id,
                        array_agg(tree) AS orgs
                  FROM  (SELECT id,
                                (actor.org_unit_descendants(id)).id AS tree
                          FROM  actor.org_unit
                        ) x
                  GROUP BY 1
            )
    SELECT  b.*,
            s.orgs
      FROM  rating.badge b
            JOIN org_scope s ON (b.scope = s.id);

CREATE OR REPLACE FUNCTION rating.precalc_src_filter(src INT)
    RETURNS INT AS $f$
DECLARE
    cnt     INT     := 0;
BEGIN

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_src_filter_bib_list;
    IF src IS NOT NULL THEN
        CREATE TEMP TABLE precalc_src_filter_bib_list ON COMMIT DROP AS
            SELECT id FROM biblio.record_entry
            WHERE source = src AND NOT deleted;
    ELSE
        CREATE TEMP TABLE precalc_src_filter_bib_list ON COMMIT DROP AS
            SELECT id FROM biblio.record_entry
            WHERE id > 0 AND NOT deleted;
    END IF;

    SELECT count(*) INTO cnt FROM precalc_src_filter_bib_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_circ_mod_filter(cm TEXT)
    RETURNS INT AS $f$
DECLARE
    cnt     INT     := 0;
BEGIN

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_circ_mod_filter_bib_list;
    IF cm IS NOT NULL THEN
        CREATE TEMP TABLE precalc_circ_mod_filter_bib_list ON COMMIT DROP AS
            SELECT  cn.record AS id,
                    cp.id AS copy
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cn.id = cp.call_number)
              WHERE cp.circ_modifier = cm
                    AND NOT cp.deleted;
    ELSE
        CREATE TEMP TABLE precalc_circ_mod_filter_bib_list ON COMMIT DROP AS
            SELECT  cn.record AS id,
                    cp.id AS copy
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cn.id = cp.call_number)
              WHERE NOT cp.deleted;
    END IF;

    SELECT count(*) INTO cnt FROM precalc_circ_mod_filter_bib_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_location_filter(loc INT)
    RETURNS INT AS $f$
DECLARE
    cnt     INT     := 0;
BEGIN

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_location_filter_bib_list;
    IF loc IS NOT NULL THEN
        CREATE TEMP TABLE precalc_location_filter_bib_list ON COMMIT DROP AS
            SELECT  cn.record AS id,
                    cp.id AS copy
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cn.id = cp.call_number)
                    JOIN asset.copy_location_group_map lg ON (cp.location = lg.location)
              WHERE lg.lgroup = loc
                    AND NOT cp.deleted;
    ELSE
        CREATE TEMP TABLE precalc_location_filter_bib_list ON COMMIT DROP AS
            SELECT  cn.record AS id,
                    cp.id AS copy
              FROM  asset.call_number cn
                    JOIN asset.copy cp ON (cn.id = cp.call_number)
              WHERE NOT cp.deleted;
    END IF;

    SELECT count(*) INTO cnt FROM precalc_location_filter_bib_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

-- all or limited...
CREATE OR REPLACE FUNCTION rating.precalc_attr_filter(attr_filter TEXT)
    RETURNS INT AS $f$
DECLARE
    cnt     INT := 0;
    afilter TEXT;
BEGIN

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_attr_filter_bib_list;
    IF attr_filter IS NOT NULL THEN
        afilter := metabib.compile_composite_attr(attr_filter);
        CREATE TEMP TABLE precalc_attr_filter_bib_list ON COMMIT DROP AS
            SELECT source AS id FROM metabib.record_attr_vector_list
            WHERE vlist @@ metabib.compile_composite_attr(attr_filter);
    ELSE
        CREATE TEMP TABLE precalc_attr_filter_bib_list ON COMMIT DROP AS
            SELECT source AS id FROM metabib.record_attr_vector_list;
    END IF;

    SELECT count(*) INTO cnt FROM precalc_attr_filter_bib_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_bibs_by_copy(badge_id INT)
    RETURNS INT AS $f$
DECLARE
    cnt         INT     := 0;
    badge_row   rating.badge_with_orgs%ROWTYPE;
    base        TEXT;
    whr         TEXT;
BEGIN

    SELECT * INTO badge_row FROM rating.badge_with_orgs WHERE id = badge_id;

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bibs_by_copy_list;
    CREATE TEMP TABLE precalc_bibs_by_copy_list ON COMMIT DROP AS
        SELECT  DISTINCT cn.record AS id
          FROM  asset.call_number cn
                JOIN asset.copy cp ON (cp.call_number = cn.id AND NOT cp.deleted)
                JOIN precalc_copy_filter_bib_list f ON (cp.id = f.copy)
          WHERE cn.owning_lib = ANY (badge_row.orgs)
                AND NOT cn.deleted;

    SELECT count(*) INTO cnt FROM precalc_bibs_by_copy_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_bibs_by_uri(badge_id INT)
    RETURNS INT AS $f$
DECLARE
    cnt         INT     := 0;
    badge_row   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge_row FROM rating.badge_with_orgs WHERE id = badge_id;

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bibs_by_uri_list;
    CREATE TEMP TABLE precalc_bibs_by_uri_list ON COMMIT DROP AS
        SELECT  DISTINCT record AS id
          FROM  asset.call_number cn
                JOIN asset.uri_call_number_map urim ON (urim.call_number = cn.id)
                JOIN asset.uri uri ON (urim.uri = uri.id AND uri.active)
          WHERE cn.owning_lib = ANY (badge_row.orgs)
                AND cn.label = '##URI##'
                AND NOT cn.deleted;

    SELECT count(*) INTO cnt FROM precalc_bibs_by_uri_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.precalc_bibs_by_copy_or_uri(badge_id INT)
    RETURNS INT AS $f$
DECLARE
    cnt         INT     := 0;
BEGIN

    PERFORM rating.precalc_bibs_by_copy(badge_id);
    PERFORM rating.precalc_bibs_by_uri(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bibs_by_copy_or_uri_list;
    CREATE TEMP TABLE precalc_bibs_by_copy_or_uri_list ON COMMIT DROP AS
        SELECT id FROM precalc_bibs_by_copy_list
            UNION
        SELECT id FROM precalc_bibs_by_uri_list;

    SELECT count(*) INTO cnt FROM precalc_bibs_by_copy_or_uri_list;
    RETURN cnt;
END;
$f$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION rating.recalculate_badge_score ( badge_id INT, setup_only BOOL DEFAULT FALSE ) RETURNS VOID AS $f$
DECLARE
    badge_row           rating.badge%ROWTYPE;
    param           rating.popularity_parameter%ROWTYPE;
BEGIN
    SET LOCAL client_min_messages = error;

    -- Find what we're doing    
    SELECT * INTO badge_row FROM rating.badge WHERE id = badge_id;
    SELECT * INTO param FROM rating.popularity_parameter WHERE id = badge_row.popularity_parameter;

    -- Calculate the filtered bib set, or all bibs if none
    PERFORM rating.precalc_attr_filter(badge_row.attr_filter);
    PERFORM rating.precalc_src_filter(badge_row.src_filter);
    PERFORM rating.precalc_circ_mod_filter(badge_row.circ_mod_filter);
    PERFORM rating.precalc_location_filter(badge_row.loc_grp_filter);

    -- Bring the bib-level filter lists together
    DROP TABLE IF EXISTS precalc_bib_filter_bib_list;
    CREATE TEMP TABLE precalc_bib_filter_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_attr_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_src_filter_bib_list;

    -- Bring the copy-level filter lists together. We're keeping this for bib_by_copy filtering later.
    DROP TABLE IF EXISTS precalc_copy_filter_bib_list;
    CREATE TEMP TABLE precalc_copy_filter_bib_list ON COMMIT DROP AS
        SELECT id, copy FROM precalc_circ_mod_filter_bib_list
            INTERSECT
        SELECT id, copy FROM precalc_location_filter_bib_list;

    -- Bring the collapsed filter lists together
    DROP TABLE IF EXISTS precalc_filter_bib_list;
    CREATE TEMP TABLE precalc_filter_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_bib_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_copy_filter_bib_list;

    CREATE INDEX precalc_filter_bib_list_idx
        ON precalc_filter_bib_list (id);

    IF setup_only THEN
        RETURN;
    END IF;

    -- If it's a fixed-rating badge, just do it ...
    IF badge_row.fixed_rating IS NOT NULL THEN
        DELETE FROM rating.record_badge_score WHERE badge = badge_id;
        EXECUTE $e$
            INSERT INTO rating.record_badge_score (record, badge, score)
                SELECT record, $1, $2 FROM $e$ || param.func || $e$($1)$e$
        USING badge_id, badge_row.fixed_rating;

        UPDATE rating.badge SET last_calc = NOW() WHERE id = badge_id;

        RETURN;
    END IF;
    -- else, calculate!

    -- Make a session-local scratchpad for calculating scores
    CREATE TEMP TABLE record_score_scratchpad (
        bib     BIGINT,
        value   NUMERIC
    ) ON COMMIT DROP;

    -- Gather raw values
    EXECUTE $e$
        INSERT INTO record_score_scratchpad (bib, value)
            SELECT * FROM $e$ || param.func || $e$($1)$e$
    USING badge_id;

    IF badge_row.discard > 0 OR badge_row.percentile IS NOT NULL THEN
        -- To speed up discard-common
        CREATE INDEX record_score_scratchpad_score_idx ON record_score_scratchpad (value);
        ANALYZE record_score_scratchpad;
    END IF;

    IF badge_row.discard > 0 THEN -- Remove common low values (trim the long tail)
        DELETE FROM record_score_scratchpad WHERE value IN (
            SELECT DISTINCT value FROM record_score_scratchpad ORDER BY value LIMIT badge_row.discard
        );
    END IF;

    IF badge_row.percentile IS NOT NULL THEN -- Cut population down to exceptional records
        DELETE FROM record_score_scratchpad WHERE value <= (
            SELECT value FROM (
                SELECT  value,
                        CUME_DIST() OVER (ORDER BY value) AS p
                  FROM  record_score_scratchpad
            ) x WHERE p < badge_row.percentile / 100.0 ORDER BY p DESC LIMIT 1
        );
    END IF;


    -- And, finally, push new data in
    DELETE FROM rating.record_badge_score WHERE badge = badge_id;
    INSERT INTO rating.record_badge_score (badge, record, score)
        SELECT  badge_id,
                bib,
                GREATEST(ROUND((CUME_DIST() OVER (ORDER BY value)) * 5), 1) AS value
          FROM  record_score_scratchpad;

    DROP TABLE record_score_scratchpad;

    -- Now, finally-finally, mark the badge as recalculated
    UPDATE rating.badge SET last_calc = NOW() WHERE id = badge_id;

    RETURN;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION rating.holds_filled_over_time(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
    iage    INT     := 1;
    iint    INT     := NULL;
    iscale  NUMERIC := NULL;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    IF badge.horizon_age IS NULL THEN
        RAISE EXCEPTION 'Badge "%" with id % requires a horizon age but has none.',
            badge.name,
            badge.id;
    END IF;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bib_list;
    CREATE TEMP TABLE precalc_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list;

    iint := EXTRACT(EPOCH FROM badge.importance_interval);
    IF badge.importance_age IS NOT NULL THEN
        iage := (EXTRACT(EPOCH FROM badge.importance_age) / iint)::INT;
    END IF;

    -- if iscale is smaller than 1, scaling slope will be shallow ... BEWARE!
    iscale := COALESCE(badge.importance_scale, 1.0);

    RETURN QUERY
     SELECT bib,
            SUM( holds * GREATEST( iscale * (iage - hage), 1.0 ))
      FROM (
         SELECT f.id AS bib,
                (1 + EXTRACT(EPOCH FROM AGE(h.fulfillment_time)) / iint)::INT AS hage,
                COUNT(h.id)::INT AS holds
          FROM  action.hold_request h
                JOIN reporter.hold_request_record rhrr ON (rhrr.id = h.id)
                JOIN precalc_bib_list f ON (f.id = rhrr.bib_record)
          WHERE h.fulfillment_time >= NOW() - badge.horizon_age
                AND h.request_lib = ANY (badge.orgs)
          GROUP BY 1, 2
      ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.holds_placed_over_time(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
    iage    INT     := 1;
    iint    INT     := NULL;
    iscale  NUMERIC := NULL;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    IF badge.horizon_age IS NULL THEN
        RAISE EXCEPTION 'Badge "%" with id % requires a horizon age but has none.',
            badge.name,
            badge.id;
    END IF;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bib_list;
    CREATE TEMP TABLE precalc_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list;

    iint := EXTRACT(EPOCH FROM badge.importance_interval);
    IF badge.importance_age IS NOT NULL THEN
        iage := (EXTRACT(EPOCH FROM badge.importance_age) / iint)::INT;
    END IF;

    -- if iscale is smaller than 1, scaling slope will be shallow ... BEWARE!
    iscale := COALESCE(badge.importance_scale, 1.0);

    RETURN QUERY
     SELECT bib,
            SUM( holds * GREATEST( iscale * (iage - hage), 1.0 ))
      FROM (
         SELECT f.id AS bib,
                (1 + EXTRACT(EPOCH FROM AGE(h.request_time)) / iint)::INT AS hage,
                COUNT(h.id)::INT AS holds
          FROM  action.hold_request h
                JOIN reporter.hold_request_record rhrr ON (rhrr.id = h.id)
                JOIN precalc_bib_list f ON (f.id = rhrr.bib_record)
          WHERE h.request_time >= NOW() - badge.horizon_age
                AND h.request_lib = ANY (badge.orgs)
          GROUP BY 1, 2
      ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.current_hold_count(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT rhrr.bib_record AS bib,
            COUNT(DISTINCT h.id)::NUMERIC AS holds
      FROM  action.hold_request h
            JOIN reporter.hold_request_record rhrr ON (rhrr.id = h.id)
            JOIN action.hold_copy_map m ON (m.hold = h.id)
            JOIN precalc_copy_filter_bib_list cf ON (rhrr.bib_record = cf.id AND m.target_copy = cf.copy)
      WHERE h.fulfillment_time IS NULL
            AND h.request_lib = ANY (badge.orgs)
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.circs_over_time(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
    iage    INT     := 1;
    iint    INT     := NULL;
    iscale  NUMERIC := NULL;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    IF badge.horizon_age IS NULL THEN
        RAISE EXCEPTION 'Badge "%" with id % requires a horizon age but has none.',
            badge.name,
            badge.id;
    END IF;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    iint := EXTRACT(EPOCH FROM badge.importance_interval);
    IF badge.importance_age IS NOT NULL THEN
        iage := (EXTRACT(EPOCH FROM badge.importance_age) / iint)::INT;
    END IF;

    -- if iscale is smaller than 1, scaling slope will be shallow ... BEWARE!
    iscale := COALESCE(badge.importance_scale, 1.0);

    RETURN QUERY
     SELECT bib,
            SUM( circs * GREATEST( iscale * (iage - cage), 1.0 ))
      FROM (
         SELECT cn.record AS bib,
                (1 + EXTRACT(EPOCH FROM AGE(c.xact_start)) / iint)::INT AS cage,
                COUNT(c.id)::INT AS circs
          FROM  action.circulation c
                JOIN precalc_copy_filter_bib_list cf ON (c.target_copy = cf.copy)
                JOIN asset.copy cp ON (cp.id = c.target_copy)
                JOIN asset.call_number cn ON (cn.id = cp.call_number)
          WHERE c.xact_start >= NOW() - badge.horizon_age
                AND cn.owning_lib = ANY (badge.orgs)
                AND c.phone_renewal IS FALSE  -- we don't count renewals
                AND c.desk_renewal IS FALSE
                AND c.opac_renewal IS FALSE
          GROUP BY 1, 2
      ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.current_circ_count(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT cn.record AS bib,
            COUNT(c.id)::NUMERIC AS circs
      FROM  action.circulation c
            JOIN precalc_copy_filter_bib_list cf ON (c.target_copy = cf.copy)
            JOIN asset.copy cp ON (cp.id = c.target_copy)
            JOIN asset.call_number cn ON (cn.id = cp.call_number)
      WHERE c.checkin_time IS NULL
            AND cn.owning_lib = ANY (badge.orgs)
      GROUP BY 1;

END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.checked_out_total_ratio(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT bib,
            SUM(checked_out)::NUMERIC / SUM(total)::NUMERIC
      FROM  (SELECT cn.record AS bib,
                    (cp.status = 1)::INT AS checked_out,
                    1 AS total
              FROM  asset.copy cp
                    JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
                    JOIN asset.call_number cn ON (cn.id = cp.call_number)
              WHERE cn.owning_lib = ANY (badge.orgs)
            ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.holds_total_ratio(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT cn.record AS bib,
            COUNT(DISTINCT m.hold)::NUMERIC / COUNT(DISTINCT cp.id)::NUMERIC
      FROM  asset.copy cp
            JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
            JOIN asset.call_number cn ON (cn.id = cp.call_number)
            JOIN action.hold_copy_map m ON (m.target_copy = cp.id)
      WHERE cn.owning_lib = ANY (badge.orgs)
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.holds_holdable_ratio(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT cn.record AS bib,
            COUNT(DISTINCT m.hold)::NUMERIC / COUNT(DISTINCT cp.id)::NUMERIC
      FROM  asset.copy cp
            JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
            JOIN asset.copy_location cl ON (cl.id = cp.location)
            JOIN config.copy_status cs ON (cs.id = cp.status)
            JOIN asset.call_number cn ON (cn.id = cp.call_number)
            JOIN action.hold_copy_map m ON (m.target_copy = cp.id)
      WHERE cn.owning_lib = ANY (badge.orgs)
            AND cp.holdable IS TRUE
            AND cl.holdable IS TRUE
            AND cs.holdable IS TRUE
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.bib_record_age(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy_or_uri(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bib_list;
    CREATE TEMP TABLE precalc_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_or_uri_list;

    RETURN QUERY
     SELECT b.id,
            1.0 / EXTRACT(EPOCH FROM AGE(b.create_date))::NUMERIC + 1.0
      FROM  precalc_bib_list pop
            JOIN biblio.record_entry b ON (b.id = pop.id);
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.bib_pub_age(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy_or_uri(badge_id);

    SET LOCAL client_min_messages = error;
    DROP TABLE IF EXISTS precalc_bib_list;
    CREATE TEMP TABLE precalc_bib_list ON COMMIT DROP AS
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_or_uri_list;

    RETURN QUERY
     SELECT pop.id AS bib,
            s.value::NUMERIC
      FROM  precalc_bib_list pop
            JOIN metabib.record_sorter s ON (
                s.source = pop.id
                AND s.attr = 'pubdate'
                AND s.value ~ '^\d+$'
            )
      WHERE s.value::INT <= EXTRACT(YEAR FROM NOW())::INT;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.percent_time_circulating(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );

    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT bib,
            SUM(COALESCE(circ_time,0))::NUMERIC / SUM(age)::NUMERIC
      FROM  (SELECT cn.record AS bib,
                    cp.id,
                    EXTRACT( EPOCH FROM AGE(cp.active_date) ) + 1 AS age,
                    SUM(  -- time copy spent circulating
                        EXTRACT(
                            EPOCH FROM
                            AGE(
                                COALESCE(circ.checkin_time, circ.stop_fines_time, NOW()),
                                circ.xact_start
                            )
                        )
                    )::NUMERIC AS circ_time
              FROM  asset.copy cp
                    JOIN precalc_copy_filter_bib_list c ON (cp.id = c.copy)
                    JOIN asset.call_number cn ON (cn.id = cp.call_number)
                    LEFT JOIN action.all_circulation circ ON (
                        circ.target_copy = cp.id
                        AND stop_fines NOT IN (
                            'LOST',
                            'LONGOVERDUE',
                            'CLAIMSRETURNED',
                            'LONGOVERDUE'
                        )
                        AND NOT (
                            checkin_time IS NULL AND
                            stop_fines = 'MAXFINES'
                        )
                    )
              WHERE cn.owning_lib = ANY (badge.orgs)
                    AND cp.active_date IS NOT NULL
                    -- Next line requires that copies with no circs (circ.id IS NULL) also not be deleted
                    AND ((circ.id IS NULL AND NOT cp.deleted) OR circ.id IS NOT NULL)
              GROUP BY 1,2,3
            ) x
      GROUP BY 1;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.generic_fixed_rating_by_copy(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
BEGIN
    PERFORM rating.precalc_bibs_by_copy(badge_id);
    RETURN QUERY
        SELECT id, 1.0 FROM precalc_filter_bib_list
            INTERSECT
        SELECT id, 1.0 FROM precalc_bibs_by_copy_list;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.generic_fixed_rating_by_uri(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
BEGIN
    PERFORM rating.precalc_bibs_by_uri(badge_id);
    RETURN QUERY
        SELECT id, 1.0 FROM precalc_bib_filter_bib_list
            INTERSECT
        SELECT id, 1.0 FROM precalc_bibs_by_uri_list;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.generic_fixed_rating_by_copy_or_uri(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
BEGIN
    PERFORM rating.precalc_bibs_by_copy_or_uri(badge_id);
    RETURN QUERY
        (SELECT id, 1.0 FROM precalc_filter_bib_list
            INTERSECT
        SELECT id, 1.0 FROM precalc_bibs_by_copy_list)
            UNION
        (SELECT id, 1.0 FROM precalc_bib_filter_bib_list
            INTERSECT
        SELECT id, 1.0 FROM precalc_bibs_by_uri_list);
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE OR REPLACE FUNCTION rating.generic_fixed_rating_global(badge_id INT)
    RETURNS TABLE (record BIGINT, value NUMERIC) AS $f$
BEGIN
    RETURN QUERY
        SELECT id, 1.0 FROM precalc_bib_filter_bib_list;
END;
$f$ LANGUAGE PLPGSQL STRICT;

CREATE INDEX hold_fulfillment_time_idx ON action.hold_request (fulfillment_time) WHERE fulfillment_time IS NOT NULL;
CREATE INDEX hold_request_time_idx ON action.hold_request (request_time);


/*
 * Copyright (C) 2016 Equinox Software, Inc.
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



SELECT evergreen.upgrade_deps_block_check('0984', :eg_version);

ALTER TYPE search.search_result ADD ATTRIBUTE badges TEXT, ADD ATTRIBUTE popularity NUMERIC;

CREATE OR REPLACE FUNCTION search.query_parser_fts (

    param_search_ou INT,
    param_depth     INT,
    param_query     TEXT,
    param_statuses  INT[],
    param_locations INT[],
    param_offset    INT,
    param_check     INT,
    param_limit     INT,
    metarecord      BOOL,
    staff           BOOL,
    deleted_search  BOOL,
    param_pref_ou   INT DEFAULT NULL
) RETURNS SETOF search.search_result AS $func$
DECLARE

    current_res         search.search_result%ROWTYPE;
    search_org_list     INT[];
    luri_org_list       INT[];
    tmp_int_list        INT[];

    check_limit         INT;
    core_limit          INT;
    core_offset         INT;
    tmp_int             INT;

    core_result         RECORD;
    core_cursor         REFCURSOR;
    core_rel_query      TEXT;

    total_count         INT := 0;
    check_count         INT := 0;
    deleted_count       INT := 0;
    visible_count       INT := 0;
    excluded_count      INT := 0;

    luri_as_copy        BOOL;
BEGIN

    check_limit := COALESCE( param_check, 1000 );
    core_limit  := COALESCE( param_limit, 25000 );
    core_offset := COALESCE( param_offset, 0 );

    SELECT COALESCE( enabled, FALSE ) INTO luri_as_copy FROM config.global_flag WHERE name = 'opac.located_uri.act_as_copy';

    -- core_skip_chk := COALESCE( param_skip_chk, 1 );

    IF param_search_ou > 0 THEN
        IF param_depth IS NOT NULL THEN
            SELECT ARRAY_AGG(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou, param_depth );
        ELSE
            SELECT ARRAY_AGG(distinct id) INTO search_org_list FROM actor.org_unit_descendants( param_search_ou );
        END IF;

        IF luri_as_copy THEN
            SELECT ARRAY_AGG(distinct id) INTO luri_org_list FROM actor.org_unit_full_path( param_search_ou );
        ELSE
            SELECT ARRAY_AGG(distinct id) INTO luri_org_list FROM actor.org_unit_ancestors( param_search_ou );
        END IF;

    ELSIF param_search_ou < 0 THEN
        SELECT ARRAY_AGG(distinct org_unit) INTO search_org_list FROM actor.org_lasso_map WHERE lasso = -param_search_ou;

        FOR tmp_int IN SELECT * FROM UNNEST(search_org_list) LOOP

            IF luri_as_copy THEN
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_full_path( tmp_int );
            ELSE
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( tmp_int );
            END IF;

            luri_org_list := luri_org_list || tmp_int_list;
        END LOOP;

        SELECT ARRAY_AGG(DISTINCT x.id) INTO luri_org_list FROM UNNEST(luri_org_list) x(id);

    ELSIF param_search_ou = 0 THEN
        -- reserved for user lassos (ou_buckets/type='lasso') with ID passed in depth ... hack? sure.
    END IF;

    IF param_pref_ou IS NOT NULL THEN
            IF luri_as_copy THEN
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_full_path( param_pref_ou );
            ELSE
                SELECT ARRAY_AGG(distinct id) INTO tmp_int_list FROM actor.org_unit_ancestors( param_pref_ou );
            END IF;

        luri_org_list := luri_org_list || tmp_int_list;
    END IF;

    OPEN core_cursor FOR EXECUTE param_query;

    LOOP

        FETCH core_cursor INTO core_result;
        EXIT WHEN NOT FOUND;
        EXIT WHEN total_count >= core_limit;

        total_count := total_count + 1;

        CONTINUE WHEN total_count NOT BETWEEN  core_offset + 1 AND check_limit + core_offset;

        check_count := check_count + 1;

        IF NOT deleted_search THEN

            PERFORM 1 FROM biblio.record_entry b WHERE NOT b.deleted AND b.id IN ( SELECT * FROM unnest( core_result.records ) );
            IF NOT FOUND THEN
                -- RAISE NOTICE ' % were all deleted ... ', core_result.records;
                deleted_count := deleted_count + 1;
                CONTINUE;
            END IF;

            PERFORM 1
              FROM  biblio.record_entry b
                    JOIN config.bib_source s ON (b.source = s.id)
              WHERE s.transcendant
                    AND b.id IN ( SELECT * FROM unnest( core_result.records ) );

            IF FOUND THEN
                -- RAISE NOTICE ' % were all transcendant ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;
                current_res.badges = core_result.badges;
                current_res.popularity = core_result.popularity;

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

            PERFORM 1
              FROM  asset.call_number cn
                    JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                    JOIN asset.uri uri ON (map.uri = uri.id)
              WHERE NOT cn.deleted
                    AND cn.label = '##URI##'
                    AND uri.active
                    AND ( param_locations IS NULL OR array_upper(param_locations, 1) IS NULL )
                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                    AND cn.owning_lib IN ( SELECT * FROM unnest( luri_org_list ) )
              LIMIT 1;

            IF FOUND THEN
                -- RAISE NOTICE ' % have at least one URI ... ', core_result.records;
                visible_count := visible_count + 1;

                current_res.id = core_result.id;
                current_res.rel = core_result.rel;
                current_res.badges = core_result.badges;
                current_res.popularity = core_result.popularity;

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
                        AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.status IN ( SELECT * FROM unnest( param_statuses ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                    -- RAISE NOTICE ' % and multi-home linked records were all status-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF param_locations IS NOT NULL AND array_upper(param_locations, 1) > 0 THEN

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.location IN ( SELECT * FROM unnest( param_locations ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                      LIMIT 1;

                    IF NOT FOUND THEN
                        -- RAISE NOTICE ' % and multi-home linked records were all copy_location-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            END IF;

            IF staff IS NULL OR NOT staff THEN

                PERFORM 1
                  FROM  asset.opac_visible_copies
                  WHERE circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN
                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                      WHERE cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                        excluded_count := excluded_count + 1;
                        CONTINUE;
                    END IF;
                END IF;

            ELSE

                PERFORM 1
                  FROM  asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                  WHERE NOT cn.deleted
                        AND NOT cp.deleted
                        AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                        AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                  LIMIT 1;

                IF NOT FOUND THEN

                    PERFORM 1
                      FROM  biblio.peer_bib_copy_map pr
                            JOIN asset.copy cp ON (cp.id = pr.target_copy)
                      WHERE NOT cp.deleted
                            AND cp.circ_lib IN ( SELECT * FROM unnest( search_org_list ) )
                            AND pr.peer_record IN ( SELECT * FROM unnest( core_result.records ) )
                      LIMIT 1;

                    IF NOT FOUND THEN

                        PERFORM 1
                          FROM  asset.call_number cn
                                JOIN asset.copy cp ON (cp.call_number = cn.id)
                          WHERE cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                                AND NOT cp.deleted
                          LIMIT 1;

                        IF NOT FOUND THEN
                            -- Recheck Located URI visibility in the case of no "foreign" copies
                            PERFORM 1
                              FROM  asset.call_number cn
                                    JOIN asset.uri_call_number_map map ON (map.call_number = cn.id)
                                    JOIN asset.uri uri ON (map.uri = uri.id)
                              WHERE NOT cn.deleted
                                    AND cn.label = '##URI##'
                                    AND uri.active
                                    AND cn.record IN ( SELECT * FROM unnest( core_result.records ) )
                                    AND cn.owning_lib NOT IN ( SELECT * FROM unnest( luri_org_list ) )
                              LIMIT 1;

                            IF FOUND THEN
                                -- RAISE NOTICE ' % were excluded for foreign located URIs... ', core_result.records;
                                excluded_count := excluded_count + 1;
                                CONTINUE;
                            END IF;
                        ELSE
                            -- RAISE NOTICE ' % and multi-home linked records were all visibility-excluded ... ', core_result.records;
                            excluded_count := excluded_count + 1;
                            CONTINUE;
                        END IF;
                    END IF;

                END IF;

            END IF;

        END IF;

        visible_count := visible_count + 1;

        current_res.id = core_result.id;
        current_res.rel = core_result.rel;
        current_res.badges = core_result.badges;
        current_res.popularity = core_result.popularity;

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
    current_res.badges = NULL;
    current_res.popularity = NULL;
    current_res.total = total_count;
    current_res.checked = check_count;
    current_res.deleted = deleted_count;
    current_res.visible = visible_count;
    current_res.excluded = excluded_count;

    CLOSE core_cursor;

    RETURN NEXT current_res;

END;
$func$ LANGUAGE PLPGSQL;
 
CREATE OR REPLACE FUNCTION metabib.staged_browse(
    query                   TEXT,
    fields                  INT[],
    context_org             INT,
    context_locations       INT[],
    staff                   BOOL,
    browse_superpage_size   INT,
    count_up_from_zero      BOOL,   -- if false, count down from -1
    result_limit            INT,
    next_pivot_pos          INT
) RETURNS SETOF metabib.flat_browse_entry_appearance AS $p$
DECLARE
    curs                    REFCURSOR;
    rec                     RECORD;
    qpfts_query             TEXT;
    aqpfts_query            TEXT;
    afields                 INT[];
    bfields                 INT[];
    result_row              metabib.flat_browse_entry_appearance%ROWTYPE;
    results_skipped         INT := 0;
    row_counter             INT := 0;
    row_number              INT;
    slice_start             INT;
    slice_end               INT;
    full_end                INT;
    all_records             BIGINT[];
    all_brecords             BIGINT[];
    all_arecords            BIGINT[];
    superpage_of_records    BIGINT[];
    superpage_size          INT;
BEGIN
    IF count_up_from_zero THEN
        row_number := 0;
    ELSE
        row_number := -1;
    END IF;

    OPEN curs FOR EXECUTE query;

    LOOP
        FETCH curs INTO rec;
        IF NOT FOUND THEN
            IF result_row.pivot_point IS NOT NULL THEN
                RETURN NEXT result_row;
            END IF;
            RETURN;
        END IF;


        -- Gather aggregate data based on the MBE row we're looking at now, authority axis
        SELECT INTO all_arecords, result_row.sees, afields
                ARRAY_AGG(DISTINCT abl.bib), -- bibs to check for visibility
                STRING_AGG(DISTINCT aal.source::TEXT, $$,$$), -- authority record ids
                ARRAY_AGG(DISTINCT map.metabib_field) -- authority-tag-linked CMF rows

          FROM  metabib.browse_entry_simple_heading_map mbeshm
                JOIN authority.simple_heading ash ON ( mbeshm.simple_heading = ash.id )
                JOIN authority.authority_linking aal ON ( ash.record = aal.source )
                JOIN authority.bib_linking abl ON ( aal.target = abl.authority )
                JOIN authority.control_set_auth_field_metabib_field_map_refs map ON (
                    ash.atag = map.authority_field
                    AND map.metabib_field = ANY(fields)
                )
          WHERE mbeshm.entry = rec.id;


        -- Gather aggregate data based on the MBE row we're looking at now, bib axis
        SELECT INTO all_brecords, result_row.authorities, bfields
                ARRAY_AGG(DISTINCT source),
                STRING_AGG(DISTINCT authority::TEXT, $$,$$),
                ARRAY_AGG(DISTINCT def)
          FROM  metabib.browse_entry_def_map
          WHERE entry = rec.id
                AND def = ANY(fields);

        SELECT INTO result_row.fields STRING_AGG(DISTINCT x::TEXT, $$,$$) FROM UNNEST(afields || bfields) x;

        result_row.sources := 0;
        result_row.asources := 0;

        -- Bib-linked vis checking
        IF ARRAY_UPPER(all_brecords,1) IS NOT NULL THEN

            full_end := ARRAY_LENGTH(all_brecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.sources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_brecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    'NULL AS badges, NULL::NUMERIC AS popularity, ' ||
                    '1::NUMERIC AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, until we've
                -- either exhausted that set of records or found at least 1
                -- visible record.

                SELECT INTO result_row.sources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;

            -- Accurate?  Well, probably.
            result_row.accurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

        END IF;

        -- Authority-linked vis checking
        IF ARRAY_UPPER(all_arecords,1) IS NOT NULL THEN

            full_end := ARRAY_LENGTH(all_arecords, 1);
            superpage_size := COALESCE(browse_superpage_size, full_end);
            slice_start := 1;
            slice_end := superpage_size;

            WHILE result_row.asources = 0 AND slice_start <= full_end LOOP
                superpage_of_records := all_arecords[slice_start:slice_end];
                qpfts_query :=
                    'SELECT NULL::BIGINT AS id, ARRAY[r] AS records, ' ||
                    'NULL AS badges, NULL::NUMERIC AS popularity, ' ||
                    '1::NUMERIC AS rel FROM (SELECT UNNEST(' ||
                    quote_literal(superpage_of_records) || '::BIGINT[]) AS r) rr';

                -- We use search.query_parser_fts() for visibility testing.
                -- We're calling it once per browse-superpage worth of records
                -- out of the set of records related to a given mbe, via
                -- authority until we've either exhausted that set of records
                -- or found at least 1 visible record.

                SELECT INTO result_row.asources visible
                    FROM search.query_parser_fts(
                        context_org, NULL, qpfts_query, NULL,
                        context_locations, 0, NULL, NULL, FALSE, staff, FALSE
                    ) qpfts
                    WHERE qpfts.rel IS NULL;

                slice_start := slice_start + superpage_size;
                slice_end := slice_end + superpage_size;
            END LOOP;


            -- Accurate?  Well, probably.
            result_row.aaccurate := browse_superpage_size IS NULL OR
                browse_superpage_size >= full_end;

        END IF;

        IF result_row.sources > 0 OR result_row.asources > 0 THEN

            -- The function that calls this function needs row_number in order
            -- to correctly order results from two different runs of this
            -- functions.
            result_row.row_number := row_number;

            -- Now, if row_counter is still less than limit, return a row.  If
            -- not, but it is less than next_pivot_pos, continue on without
            -- returning actual result rows until we find
            -- that next pivot, and return it.

            IF row_counter < result_limit THEN
                result_row.browse_entry := rec.id;
                result_row.value := rec.value;

                RETURN NEXT result_row;
            ELSE
                result_row.browse_entry := NULL;
                result_row.authorities := NULL;
                result_row.fields := NULL;
                result_row.value := NULL;
                result_row.sources := NULL;
                result_row.sees := NULL;
                result_row.accurate := NULL;
                result_row.aaccurate := NULL;
                result_row.pivot_point := rec.id;

                IF row_counter >= next_pivot_pos THEN
                    RETURN NEXT result_row;
                    RETURN;
                END IF;
            END IF;

            IF count_up_from_zero THEN
                row_number := row_number + 1;
            ELSE
                row_number := row_number - 1;
            END IF;

            -- row_counter is different from row_number.
            -- It simply counts up from zero so that we know when
            -- we've reached our limit.
            row_counter := row_counter + 1;
        END IF;
    END LOOP;
END;
$p$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('0985', :eg_version);

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
    tmp_xml         TEXT;
    attr_def        config.record_attr_definition%ROWTYPE;
    ccvm_row        config.coded_value_map%ROWTYPE;
BEGIN

    IF attr_list IS NULL OR rdeleted THEN -- need to do the full dance on INSERT or undelete
        SELECT ARRAY_AGG(name) INTO attr_list FROM config.record_attr_definition
        WHERE (
            tag IS NOT NULL OR
            fixed_field IS NOT NULL OR
            xpath IS NOT NULL OR
            phys_char_sf IS NOT NULL OR
            composite
        ) AND (
            filter OR sorter
        );
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

            FOR tmp_xml IN SELECT UNNEST(oils_xpath(attr_def.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]])) LOOP
                tmp_val := oils_xpath_string(
                                '//*',
                                tmp_xml,
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
            IF tmp_val IS NOT NULL AND tmp_val <> '' THEN
                -- note that a string that contains only blanks
                -- is a valid value for some attributes
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

        IF attr_def.sorter THEN
            DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
            IF norm_attr_value[1] IS NOT NULL THEN
                INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, norm_attr_value[1]);
            END IF;
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

CREATE INDEX config_coded_value_map_ctype_idx ON config.coded_value_map (ctype);


SELECT evergreen.upgrade_deps_block_check('0986', :eg_version);

CREATE EXTENSION IF NOT EXISTS unaccent SCHEMA public;

CREATE OR REPLACE FUNCTION evergreen.unaccent_and_squash ( IN arg text) RETURNS text
    IMMUTABLE STRICT AS $$
	BEGIN
	RETURN evergreen.lowercase(unaccent(regexp_replace(arg, '\s','','g')));
	END;
$$ LANGUAGE PLPGSQL;

-- The unaccented indices for patron name fields
CREATE INDEX actor_usr_first_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(first_given_name));
CREATE INDEX actor_usr_second_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(second_given_name));
CREATE INDEX actor_usr_family_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(family_name));

-- DB setting to control behavior; true by default
INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
('circ.patron_search.diacritic_insensitive',
 'circ',
 oils_i18n_gettext('circ.patron_search.diacritic_insensitive',
     'Patron search diacritic insensitive',
     'coust', 'label'),
 oils_i18n_gettext('circ.patron_search.diacritic_insensitive',
     'Match patron last, first, and middle names irrespective of usage of diacritical marks or spaces. (e.g., Ines will match Inés; de la Cruz will match Delacruz)',
     'coust', 'description'),
  'bool');

INSERT INTO actor.org_unit_setting (
    org_unit, name, value
) VALUES (
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    'circ.patron_search.diacritic_insensitive',
    'true'
);




SELECT evergreen.upgrade_deps_block_check('0987', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype )
    VALUES (
        'ui.circ.billing.amount_limit', 'gui',
        oils_i18n_gettext(
            'ui.circ.billing.amount_limit',
            'Maximum payment amount allowed.',
            'coust', 'label'),
        oils_i18n_gettext(
            'ui.circ.billing.amount_limit',
            'The payment amount in the Patron Bills interface may not exceed the value of this setting.',
            'coust', 'description'),
        'currency'
    );

INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype )
    VALUES (
        'ui.circ.billing.amount_warn', 'gui',
        oils_i18n_gettext(
            'ui.circ.billing.amount_warn',
            'Payment amount threshold for Are You Sure? dialog.',
            'coust', 'label'),
        oils_i18n_gettext(
            'ui.circ.billing.amount_warn',
            'In the Patron Bills interface, a payment attempt will warn if the amount exceeds the value of this setting.',
            'coust', 'description'),
        'currency'
    );


SELECT evergreen.upgrade_deps_block_check('0988', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.maintain_901 () RETURNS TRIGGER AS $func$
use strict;
use MARC::Record;
use MARC::File::XML (BinaryEncoding => 'UTF-8');
use MARC::Charset;
use Encode;
use Unicode::Normalize;

MARC::Charset->assume_unicode(1);

my $schema = $_TD->{table_schema};
my $marc = MARC::Record->new_from_xml($_TD->{new}{marc});

my @old901s = $marc->field('901');
$marc->delete_fields(@old901s);

if ($schema eq 'biblio') {
    my $tcn_value = $_TD->{new}{tcn_value};

    # Set TCN value to record ID?
    my $id_as_tcn = spi_exec_query("
        SELECT enabled
        FROM config.global_flag
        WHERE name = 'cat.bib.use_id_for_tcn'
    ");
    if (($id_as_tcn->{processed}) && $id_as_tcn->{rows}[0]->{enabled} eq 't') {
        $tcn_value = $_TD->{new}{id}; 
        $_TD->{new}{tcn_value} = $tcn_value;
    }

    my $new_901 = MARC::Field->new("901", " ", " ",
        "a" => $tcn_value,
        "b" => $_TD->{new}{tcn_source},
        "c" => $_TD->{new}{id},
        "t" => $schema
    );

    if ($_TD->{new}{owner}) {
        $new_901->add_subfields("o" => $_TD->{new}{owner});
    }

    if ($_TD->{new}{share_depth}) {
        $new_901->add_subfields("d" => $_TD->{new}{share_depth});
    }

    if ($_TD->{new}{source}) {
        my $plan = spi_prepare('
            SELECT source
            FROM config.bib_source
            WHERE id = $1
        ', 'INTEGER');
        my $source_name =
            spi_exec_prepared($plan, {limit => 1}, $_TD->{new}{source})->{rows}[0]{source};
        spi_freeplan($plan);
        $new_901->add_subfields("s" => $source_name) if $source_name;
    }

    $marc->append_fields($new_901);
} elsif ($schema eq 'authority') {
    my $new_901 = MARC::Field->new("901", " ", " ",
        "c" => $_TD->{new}{id},
        "t" => $schema,
    );
    $marc->append_fields($new_901);
} elsif ($schema eq 'serial') {
    my $new_901 = MARC::Field->new("901", " ", " ",
        "c" => $_TD->{new}{id},
        "t" => $schema,
        "o" => $_TD->{new}{owning_lib},
    );

    if ($_TD->{new}{record}) {
        $new_901->add_subfields("r" => $_TD->{new}{record});
    }

    $marc->append_fields($new_901);
} else {
    my $new_901 = MARC::Field->new("901", " ", " ",
        "c" => $_TD->{new}{id},
        "t" => $schema,
    );
    $marc->append_fields($new_901);
}

my $xml = $marc->as_xml_record();
$xml =~ s/\n//sgo;
$xml =~ s/^<\?xml.+\?\s*>//go;
$xml =~ s/>\s+</></go;
$xml =~ s/\p{Cc}//go;

# Embed a version of OpenILS::Application::AppUtils->entityize()
# to avoid having to set PERL5LIB for PostgreSQL as well

$xml = NFC($xml);

# Convert raw ampersands to entities
$xml =~ s/&(?!\S+;)/&amp;/gso;

# Convert Unicode characters to entities
$xml =~ s/([\x{0080}-\x{fffd}])/sprintf('&#x%X;',ord($1))/sgoe;

$xml =~ s/[\x00-\x1f]//go;
$_TD->{new}{marc} = $xml;

return "MODIFY";
$func$ LANGUAGE PLPERLU;


SELECT evergreen.upgrade_deps_block_check('0989', :eg_version); -- berick/miker/gmcharlt

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




SELECT evergreen.upgrade_deps_block_check('0990', :eg_version);

CREATE OR REPLACE FUNCTION rating.copy_count(badge_id INT)
    RETURNS TABLE (record INT, value NUMERIC) AS $f$
DECLARE
    badge   rating.badge_with_orgs%ROWTYPE;
BEGIN

    SELECT * INTO badge FROM rating.badge_with_orgs WHERE id = badge_id;

    PERFORM rating.precalc_bibs_by_copy(badge_id);

    DELETE FROM precalc_copy_filter_bib_list WHERE id NOT IN (
        SELECT id FROM precalc_filter_bib_list
            INTERSECT
        SELECT id FROM precalc_bibs_by_copy_list
    );
    ANALYZE precalc_copy_filter_bib_list;

    RETURN QUERY
     SELECT f.id::INT AS bib,
            COUNT(f.copy)::NUMERIC
      FROM  precalc_copy_filter_bib_list f
            JOIN asset.copy cp ON (f.copy = cp.id)
            JOIN asset.call_number cn ON (cn.id = cp.call_number)
      WHERE cn.owning_lib = ANY (badge.orgs) GROUP BY 1;

END;
$f$ LANGUAGE PLPGSQL STRICT;

INSERT INTO rating.popularity_parameter (id, name, func, require_percentile) VALUES (16, 'Copy Count', 'rating.copy_count', TRUE);



SELECT evergreen.upgrade_deps_block_check('0991', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes(
    bibid BIGINT[], 
    ouid INT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[]
) RETURNS TABLE(id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT) AS $$
    WITH RECURSIVE ou_depth AS (
        SELECT COALESCE(
            $3,
            (
                SELECT depth
                FROM actor.org_unit_type aout
                    INNER JOIN actor.org_unit ou ON ou_type = aout.id
                WHERE ou.id = $2
            )
        ) AS depth
    ), descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ad ON (ad.id = ou.id),
                ou_depth
        WHERE ad.depth = ou_depth.depth
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
        WHERE ou.id = $2
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ), descendants as (
        SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id)
    )

    SELECT ua.id, ua.name, ua.label_sortkey, MIN(ua.rank) AS rank FROM (
        SELECT acn.id, owning_lib.name, acn.label_sortkey,
            evergreen.rank_cp(acp),
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN descendants AS aou ON (acp.circ_lib = aou.id)
            JOIN actor.org_unit AS owning_lib ON (acn.owning_lib = owning_lib.id)
        WHERE acn.record = ANY ($1)
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
            AND CASE WHEN ('exclude_invisible_acn' = ANY($7)) THEN 
                EXISTS (
                    SELECT 1 
                    FROM asset.opac_visible_copies 
                    WHERE copy_id = acp.id AND record = acn.record
                ) ELSE TRUE END
        GROUP BY acn.id, evergreen.rank_cp(acp), owning_lib.name, acn.label_sortkey, aou.id
        WINDOW w AS (
            ORDER BY 
                COALESCE(
                    CASE WHEN aou.id = $2 THEN -20000 END,
                    CASE WHEN aou.id = $6 THEN -10000 END,
                    (SELECT distance - 5000
                        FROM actor.org_unit_descendants_distance($6) as x
                        WHERE x.id = aou.id AND $6 IN (
                            SELECT q.id FROM actor.org_unit_descendants($2) as q)),
                    (SELECT e.distance FROM actor.org_unit_descendants_distance($2) as e WHERE e.id = aou.id),
                    1000
                ),
                evergreen.rank_cp(acp)
        )
    ) AS ua
    GROUP BY ua.id, ua.name, ua.label_sortkey
    ORDER BY rank, ua.name, ua.label_sortkey
    LIMIT ($4 -> 'acn')::INT
    OFFSET ($5 -> 'acn')::INT;
$$ LANGUAGE SQL STABLE ROWS 10;



SELECT evergreen.upgrade_deps_block_check('0992', :eg_version);

ALTER TABLE config.copy_status
    ADD COLUMN is_available BOOL NOT NULL DEFAULT FALSE;

UPDATE config.copy_status SET is_available = TRUE
    WHERE id IN (0, 7); -- available, reshelving.

CREATE OR REPLACE FUNCTION action.item_user_circ_test( circ_ou INT, match_item BIGINT, match_user INT, renewal BOOL ) RETURNS SETOF action.circ_matrix_test_result AS $func$
DECLARE
    user_object             actor.usr%ROWTYPE;
    standing_penalty        config.standing_penalty%ROWTYPE;
    item_object             asset.copy%ROWTYPE;
    item_status_object      config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    result                  action.circ_matrix_test_result;
    circ_test               action.found_circ_matrix_matchpoint;
    circ_matchpoint         config.circ_matrix_matchpoint%ROWTYPE;
    circ_limit_set          config.circ_limit_set%ROWTYPE;
    hold_ratio              action.hold_stats%ROWTYPE;
    penalty_type            TEXT;
    items_out               INT;
    context_org_list        INT[];
    done                    BOOL := FALSE;
BEGIN
    -- Assume success unless we hit a failure condition
    result.success := TRUE;

    -- Need user info to look up matchpoints
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user AND NOT deleted;

    -- (Insta)Fail if we couldn't find the user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Need item info to look up matchpoints
    SELECT INTO item_object * FROM asset.copy WHERE id = match_item AND NOT deleted;

    -- (Insta)Fail if we couldn't find the item 
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO circ_test * FROM action.find_circ_matrix_matchpoint(circ_ou, item_object, user_object, renewal);

    circ_matchpoint             := circ_test.matchpoint;
    result.matchpoint           := circ_matchpoint.id;
    result.circulate            := circ_matchpoint.circulate;
    result.duration_rule        := circ_matchpoint.duration_rule;
    result.recurring_fine_rule  := circ_matchpoint.recurring_fine_rule;
    result.max_fine_rule        := circ_matchpoint.max_fine_rule;
    result.hard_due_date        := circ_matchpoint.hard_due_date;
    result.renewals             := circ_matchpoint.renewals;
    result.grace_period         := circ_matchpoint.grace_period;
    result.buildrows            := circ_test.buildrows;

    -- (Insta)Fail if we couldn't find a matchpoint
    IF circ_test.success = false THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- All failures before this point are non-recoverable
    -- Below this point are possibly overridable failures

    -- Fail if the user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item can't circulate
    IF item_object.circulate IS FALSE THEN
        result.fail_part := 'asset.copy.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the item isn't in a circulateable status on a non-renewal
    IF NOT renewal AND item_object.status <> 8 AND item_object.status NOT IN (
        (SELECT id FROM config.copy_status WHERE is_available) ) THEN 
        result.fail_part := 'asset.copy.status';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    -- Alternately, fail if the item isn't checked out on a renewal
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

    -- Use Circ OU for penalties and such
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( circ_ou );

    IF renewal THEN
        penalty_type = '%RENEW%';
    ELSE
        penalty_type = '%CIRC%';
    END IF;

    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND csp.block_list LIKE penalty_type LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    -- Fail if the test is set to hard non-circulating
    IF circ_matchpoint.circulate IS FALSE THEN
        result.fail_part := 'config.circ_matrix_test.circulate';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    -- Fail if the total copy-hold ratio is too low
    IF circ_matchpoint.total_copy_hold_ratio IS NOT NULL THEN
        SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        IF hold_ratio.total_copy_ratio IS NOT NULL AND hold_ratio.total_copy_ratio < circ_matchpoint.total_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.total_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the available copy-hold ratio is too low
    IF circ_matchpoint.available_copy_hold_ratio IS NOT NULL THEN
        IF hold_ratio.hold_count IS NULL THEN
            SELECT INTO hold_ratio * FROM action.copy_related_hold_stats(match_item);
        END IF;
        IF hold_ratio.available_copy_ratio IS NOT NULL AND hold_ratio.available_copy_ratio < circ_matchpoint.available_copy_hold_ratio THEN
            result.fail_part := 'config.circ_matrix_test.available_copy_hold_ratio';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Fail if the user has too many items out by defined limit sets
    FOR circ_limit_set IN SELECT ccls.* FROM config.circ_limit_set ccls
      JOIN config.circ_matrix_limit_set_map ccmlsm ON ccmlsm.limit_set = ccls.id
      WHERE ccmlsm.active AND ( ccmlsm.matchpoint = circ_matchpoint.id OR
        ( ccmlsm.matchpoint IN (SELECT * FROM unnest(result.buildrows)) AND ccmlsm.fallthrough )
        ) LOOP
            IF circ_limit_set.items_out > 0 AND NOT renewal THEN
                SELECT INTO context_org_list ARRAY_AGG(aou.id)
                  FROM actor.org_unit_full_path( circ_ou ) aou
                    JOIN actor.org_unit_type aout ON aou.ou_type = aout.id
                  WHERE aout.depth >= circ_limit_set.depth;
                IF circ_limit_set.global THEN
                    WITH RECURSIVE descendant_depth AS (
                        SELECT  ou.id,
                            ou.parent_ou
                        FROM  actor.org_unit ou
                        WHERE ou.id IN (SELECT * FROM unnest(context_org_list))
                            UNION
                        SELECT  ou.id,
                            ou.parent_ou
                        FROM  actor.org_unit ou
                            JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
                    ) SELECT INTO context_org_list ARRAY_AGG(ou.id) FROM actor.org_unit ou JOIN descendant_depth USING (id);
                END IF;
                SELECT INTO items_out COUNT(DISTINCT circ.id)
                  FROM action.circulation circ
                    JOIN asset.copy copy ON (copy.id = circ.target_copy)
                    LEFT JOIN action.circulation_limit_group_map aclgm ON (circ.id = aclgm.circ)
                  WHERE circ.usr = match_user
                    AND circ.circ_lib IN (SELECT * FROM unnest(context_org_list))
                    AND circ.checkin_time IS NULL
                    AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL)
                    AND (copy.circ_modifier IN (SELECT circ_mod FROM config.circ_limit_set_circ_mod_map WHERE limit_set = circ_limit_set.id)
                        OR copy.location IN (SELECT copy_loc FROM config.circ_limit_set_copy_loc_map WHERE limit_set = circ_limit_set.id)
                        OR aclgm.limit_group IN (SELECT limit_group FROM config.circ_limit_set_group_map WHERE limit_set = circ_limit_set.id)
                    );
                IF items_out >= circ_limit_set.items_out THEN
                    result.fail_part := 'config.circ_matrix_circ_mod_test';
                    result.success := FALSE;
                    done := TRUE;
                    RETURN NEXT result;
                END IF;
            END IF;
            SELECT INTO result.limit_groups result.limit_groups || ARRAY_AGG(limit_group) FROM config.circ_limit_set_group_map WHERE limit_set = circ_limit_set.id AND NOT check_only;
    END LOOP;

    -- If we passed everything, return the successful matchpoint
    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;



SELECT evergreen.upgrade_deps_block_check('0993', :eg_version);

ALTER TABLE config.usr_activity_type 
    ALTER COLUMN transient SET DEFAULT TRUE;

-- Utility function for removing all activity entries by activity type,
-- except for the most recent entry per user.  This is primarily useful
-- when cleaning up rows prior to setting the transient flag on an
-- activity type to true.  It allows for immediate cleanup of data (e.g.
-- for patron privacy) and lets admins control when the data is deleted,
-- which could be useful for huge activity tables.

CREATE OR REPLACE FUNCTION 
    actor.purge_usr_activity_by_type(act_type INTEGER) 
    RETURNS VOID AS $$
DECLARE
    cur_usr INTEGER;
BEGIN
    FOR cur_usr IN SELECT DISTINCT(usr) 
        FROM actor.usr_activity WHERE etype = act_type LOOP
        DELETE FROM actor.usr_activity WHERE id IN (
            SELECT id 
            FROM actor.usr_activity 
            WHERE usr = cur_usr AND etype = act_type
            ORDER BY event_time DESC OFFSET 1
        );

    END LOOP;
END $$ LANGUAGE PLPGSQL;




SELECT evergreen.upgrade_deps_block_check('0994', :eg_version);

CREATE OR REPLACE FUNCTION authority.propagate_changes 
    (aid BIGINT, bid BIGINT) RETURNS BIGINT AS $func$
DECLARE
    bib_rec biblio.record_entry%ROWTYPE;
    new_marc TEXT;
BEGIN

    SELECT INTO bib_rec * FROM biblio.record_entry WHERE id = bid;

    new_marc := vandelay.merge_record_xml(
        bib_rec.marc, authority.generate_overlay_template(aid));

    IF new_marc = bib_rec.marc THEN
        -- Authority record change had no impact on this bib record.
        -- Nothing left to do.
        RETURN aid;
    END IF;

    PERFORM 1 FROM config.global_flag 
        WHERE name = 'ingest.disable_authority_auto_update_bib_meta' 
            AND enabled;

    IF NOT FOUND THEN 
        -- update the bib record editor and edit_date
        bib_rec.editor := (
            SELECT editor FROM authority.record_entry WHERE id = aid);
        bib_rec.edit_date = NOW();
    END IF;

    UPDATE biblio.record_entry SET
        marc = new_marc,
        editor = bib_rec.editor,
        edit_date = bib_rec.edit_date
    WHERE id = bid;

    RETURN aid;

END;
$func$ LANGUAGE PLPGSQL;


-- DATA
-- Disabled by default
INSERT INTO config.global_flag (name, enabled, label) VALUES (
    'ingest.disable_authority_auto_update_bib_meta',  FALSE, 
    oils_i18n_gettext(
        'ingest.disable_authority_auto_update_bib_meta',
        'Authority Automation: Disable automatic authority updates ' ||
            'from modifying bib record editor and edit_date',
        'cgf',
        'label'
    )
);


CREATE OR REPLACE FUNCTION authority.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    ashs    authority.simple_heading%ROWTYPE;
    mbe_row metabib.browse_entry%ROWTYPE;
    mbe_id  BIGINT;
    ash_id  BIGINT;
BEGIN

    IF NEW.deleted IS TRUE THEN -- If this authority is deleted
        DELETE FROM authority.bib_linking WHERE authority = NEW.id; -- Avoid updating fields in bibs that are no longer visible
        DELETE FROM authority.full_rec WHERE record = NEW.id; -- Avoid validating fields against deleted authority records
        DELETE FROM authority.simple_heading WHERE record = NEW.id;
          -- Should remove matching $0 from controlled fields at the same time?

        -- XXX What do we about the actual linking subfields present in
        -- authority records that target this one when this happens?
        DELETE FROM authority.authority_linking
            WHERE source = NEW.id OR target = NEW.id;

        RETURN NEW; -- and we're done
    END IF;

    IF TG_OP = 'UPDATE' THEN -- re-ingest?
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

        IF NOT FOUND AND OLD.marc = NEW.marc THEN -- don't do anything if the MARC didn't change
            RETURN NEW;
        END IF;

        -- Unless there's a setting stopping us, propagate these updates to any linked bib records when the heading changes
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_auto_update' AND enabled;

        IF NOT FOUND AND NEW.heading <> OLD.heading THEN
            PERFORM authority.propagate_changes(NEW.id);
        END IF;
	
        DELETE FROM authority.simple_heading WHERE record = NEW.id;
        DELETE FROM authority.authority_linking WHERE source = NEW.id;
    END IF;

    INSERT INTO authority.authority_linking (source, target, field)
        SELECT source, target, field FROM authority.calculate_authority_linking(
            NEW.id, NEW.control_set, NEW.marc::XML
        );

    FOR ashs IN SELECT * FROM authority.simple_heading_set(NEW.marc) LOOP

        INSERT INTO authority.simple_heading (record,atag,value,sort_value,thesaurus)
            VALUES (ashs.record, ashs.atag, ashs.value, ashs.sort_value, ashs.thesaurus);
            ash_id := CURRVAL('authority.simple_heading_id_seq'::REGCLASS);

        SELECT INTO mbe_row * FROM metabib.browse_entry
            WHERE value = ashs.value AND sort_value = ashs.sort_value;

        IF FOUND THEN
            mbe_id := mbe_row.id;
        ELSE
            INSERT INTO metabib.browse_entry
                ( value, sort_value ) VALUES
                ( ashs.value, ashs.sort_value );

            mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
        END IF;

        INSERT INTO metabib.browse_entry_simple_heading_map (entry,simple_heading) VALUES (mbe_id,ash_id);

    END LOOP;

    -- Flatten and insert the afr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.reingest_authority_full_rec(NEW.id);
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM authority.reingest_authority_rec_descriptor(NEW.id);
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('0995', :eg_version);

INSERT INTO rating.badge (name, description, scope, weight, horizon_age, importance_age, importance_interval, importance_scale, recalc_interval, popularity_parameter, percentile)
   VALUES('Top Holds Over Last 5 Years', 'The top 97th percentile for holds requested over the past five years on all materials. More weight is given to holds requested over the last year, with importance decreasing for every year after that.', 1, 3, '5 years', '5 years', '1 year', 2, '1 day', 2, 97);


SELECT evergreen.upgrade_deps_block_check('0996', :eg_version);

INSERT INTO config.usr_setting_type (
    name,
    opac_visible,
    label,
    description,
    datatype
) VALUES (
    'circ.send_email_checkout_receipts',
    TRUE,
    oils_i18n_gettext('circ.send_email_checkout_receipts', 'Email checkout receipts by default?', 'cust', 'label'),
    oils_i18n_gettext('circ.send_email_checkout_receipts', 'Email checkout receipts by default?', 'cust', 'description'),
    'bool'
);

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'circ.checkout.batch_notify',
    'circ',
    oils_i18n_gettext(
        'circ.checkout.batch_notify',
        'Notification of a group of circs',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'circ.checkout.batch_notify.session',
    'circ',
    oils_i18n_gettext(
        'circ.checkout.batch_notify.session',
        'Notification of a group of circs at the end of a checkout session',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    usr_field,
    opt_in_setting,
    group_field,
    template
) VALUES (
    TRUE,
    1,
    'Email Checkout Receipt',
    'circ.checkout.batch_notify.session',
    'NOOP_True',
    'SendEmail',
    'usr',
    'circ.send_email_checkout_receipts',
    'usr',
    $$[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- helpers.get_org_setting(target.0.circ_lib.id, 'org.bounced_emails') || params.sender_email || default_sender %]
Subject: Checkout Receipt
Auto-Submitted: auto-generated

You checked out the following items:

[% FOR circ IN target %]
    [%- copy_details = helpers.get_copy_bib_basics(circ.target_copy.id) -%]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    Call Number: [% circ.target_copy.call_number.label %]
    Barcode: [% circ.target_copy.barcode %]
    Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Library: [% circ.circ_lib.name %]

[% END %]
$$);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'target_copy.call_number'
), (
    currval('action_trigger.event_definition_id_seq'),
    'target_copy.location'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
), (
    currval('action_trigger.event_definition_id_seq'),
    'circ_lib'
);



SELECT evergreen.upgrade_deps_block_check('0997', :eg_version);

INSERT INTO config.copy_status (id, name, holdable, opac_visible) VALUES (18,oils_i18n_gettext(18, 'Canceled Transit', 'ccs', 'name'), 't', 't');



SELECT evergreen.upgrade_deps_block_check('0998', :eg_version);

DROP VIEW IF EXISTS action.all_circulation;
CREATE VIEW action.all_circulation AS
     SELECT aged_circulation.id, aged_circulation.usr_post_code,
        aged_circulation.usr_home_ou, aged_circulation.usr_profile,
        aged_circulation.usr_birth_year, aged_circulation.copy_call_number,
        aged_circulation.copy_location, aged_circulation.copy_owning_lib,
        aged_circulation.copy_circ_lib, aged_circulation.copy_bib_record,
        aged_circulation.xact_start, aged_circulation.xact_finish,
        aged_circulation.target_copy, aged_circulation.circ_lib,
        aged_circulation.circ_staff, aged_circulation.checkin_staff,
        aged_circulation.checkin_lib, aged_circulation.renewal_remaining,
        aged_circulation.grace_period, aged_circulation.due_date,
        aged_circulation.stop_fines_time, aged_circulation.checkin_time,
        aged_circulation.create_time, aged_circulation.duration,
        aged_circulation.fine_interval, aged_circulation.recurring_fine,
        aged_circulation.max_fine, aged_circulation.phone_renewal,
        aged_circulation.desk_renewal, aged_circulation.opac_renewal,
        aged_circulation.duration_rule,
        aged_circulation.recurring_fine_rule,
        aged_circulation.max_fine_rule, aged_circulation.stop_fines,
        aged_circulation.workstation, aged_circulation.checkin_workstation,
        aged_circulation.checkin_scan_time, aged_circulation.parent_circ,
        NULL AS usr
       FROM action.aged_circulation
UNION ALL
     SELECT DISTINCT circ.id,
        COALESCE(a.post_code, b.post_code) AS usr_post_code,
        p.home_ou AS usr_home_ou, p.profile AS usr_profile,
        date_part('year'::text, p.dob)::integer AS usr_birth_year,
        cp.call_number AS copy_call_number, circ.copy_location,
        cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish,
        circ.target_copy, circ.circ_lib, circ.circ_staff,
        circ.checkin_staff, circ.checkin_lib, circ.renewal_remaining,
        circ.grace_period, circ.due_date, circ.stop_fines_time,
        circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine,
        circ.phone_renewal, circ.desk_renewal, circ.opac_renewal,
        circ.duration_rule, circ.recurring_fine_rule, circ.max_fine_rule,
        circ.stop_fines, circ.workstation, circ.checkin_workstation,
        circ.checkin_scan_time, circ.parent_circ, circ.usr
       FROM action.circulation circ
  JOIN asset.copy cp ON circ.target_copy = cp.id
JOIN asset.call_number cn ON cp.call_number = cn.id
JOIN actor.usr p ON circ.usr = p.id
LEFT JOIN actor.usr_address a ON p.mailing_address = a.id
LEFT JOIN actor.usr_address b ON p.billing_address = b.id;


CREATE OR REPLACE FUNCTION action.all_circ_chain (ctx_circ_id INTEGER) 
    RETURNS SETOF action.all_circulation AS $$
DECLARE
    tmp_circ action.all_circulation%ROWTYPE;
    circ_0 action.all_circulation%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.all_circulation WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.all_circulation 
            WHERE id = tmp_circ.parent_circ;
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        circ_0 := tmp_circ;
    END LOOP;

    -- now send the circs to the caller, oldest to newest
    tmp_circ := circ_0;
    WHILE TRUE LOOP
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        RETURN NEXT tmp_circ;
        SELECT INTO tmp_circ * FROM action.all_circulation 
            WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.summarize_all_circ_chain 
    (ctx_circ_id INTEGER) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.all_circulation%ROWTYPE;

    -- last circ in the chain
    circ_n action.all_circulation%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.all_circulation%ROWTYPE;

BEGIN
    
    chain.num_circs := 0;
    FOR tmp_circ IN SELECT * FROM action.all_circ_chain(ctx_circ_id) LOOP

        IF chain.num_circs = 0 THEN
            circ_0 := tmp_circ;
        END IF;

        chain.num_circs := chain.num_circs + 1;
        circ_n := tmp_circ;
    END LOOP;

    chain.start_time := circ_0.xact_start;
    chain.last_stop_fines := circ_n.stop_fines;
    chain.last_stop_fines_time := circ_n.stop_fines_time;
    chain.last_checkin_time := circ_n.checkin_time;
    chain.last_checkin_scan_time := circ_n.checkin_scan_time;
    SELECT INTO chain.checkout_workstation name FROM actor.workstation WHERE id = circ_0.workstation;
    SELECT INTO chain.last_checkin_workstation name FROM actor.workstation WHERE id = circ_n.checkin_workstation;

    IF chain.num_circs > 1 THEN
        chain.last_renewal_time := circ_n.xact_start;
        SELECT INTO chain.last_renewal_workstation name FROM actor.workstation WHERE id = circ_n.workstation;
    END IF;

    RETURN chain;

END;
$$ LANGUAGE 'plpgsql';




SELECT evergreen.upgrade_deps_block_check('0999', :eg_version);

CREATE TABLE staging.setting_stage (
        row_id          BIGSERIAL PRIMARY KEY,
        row_date        TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        usrname         TEXT NOT NULL,
        setting         TEXT NOT NULL,
        value           TEXT NOT NULL,
        complete        BOOL DEFAULT FALSE
);

-- Add Spanish to config.i18n_locale table


SELECT evergreen.upgrade_deps_block_check('1000', :eg_version);

INSERT INTO config.i18n_locale (code,marc_code,name,description)
    SELECT 'es-ES', 'spa', oils_i18n_gettext('es-ES', 'Spanish', 'i18n_l', 'name'),
        oils_i18n_gettext('es-ES', 'Spanish', 'i18n_l', 'description')
    WHERE NOT EXISTS (SELECT 1 FROM config.i18n_locale WHERE code = 'es-ES');

COMMIT;

\qecho
\qecho
\qecho Now running an update to set the 901$s for bibliographic
\qecho records that have a source set. This may take a while.
\qecho
\qecho The update can be cancelled now and run later
\qecho using the following SQL statement:
\qecho
\qecho UPDATE biblio.record_entry SET id = id WHERE source IS NOT NULL;
\qecho
UPDATE biblio.record_entry SET id = id WHERE source IS NOT NULL;
