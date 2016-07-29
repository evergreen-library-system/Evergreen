--Upgrade Script for 2.10.5 to 2.11.alpha
\set eg_version '''2.11.alpha'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.11.alpha', :eg_version);

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
COMMIT;
