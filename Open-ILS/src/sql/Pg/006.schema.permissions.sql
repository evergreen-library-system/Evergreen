/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
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


DROP SCHEMA permission CASCADE;

BEGIN;
CREATE SCHEMA permission;

CREATE TABLE permission.perm_list (
	id		SERIAL	PRIMARY KEY,
	code		TEXT	NOT NULL UNIQUE,
	description	TEXT
);
CREATE INDEX perm_list_code_idx ON permission.perm_list (code);

CREATE TABLE permission.grp_tree (
	id			SERIAL	PRIMARY KEY,
	name			TEXT	NOT NULL UNIQUE,
	parent			INT	REFERENCES permission.grp_tree (id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
	usergroup		BOOL	NOT NULL DEFAULT TRUE,
	perm_interval		INTERVAL DEFAULT '3 years'::interval NOT NULL,
	description		TEXT,
	application_perm	TEXT
);
CREATE INDEX grp_tree_parent_idx ON permission.grp_tree (parent);

CREATE TABLE permission.grp_penalty_threshold (
    id          SERIAL          PRIMARY KEY,
    grp         INT             NOT NULL REFERENCES permission.grp_tree (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    org_unit    INT             NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    penalty     INT             NOT NULL REFERENCES config.standing_penalty (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    threshold   NUMERIC(8,2)    NOT NULL,
    CONSTRAINT penalty_grp_once UNIQUE (grp,penalty,org_unit)
);

CREATE TABLE permission.grp_perm_map (
	id		SERIAL	PRIMARY KEY,
	grp		INT	NOT NULL REFERENCES permission.grp_tree (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	perm		INT	NOT NULL REFERENCES permission.perm_list (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	depth		INT	NOT NULL,
	grantable	BOOL	NOT NULL DEFAULT FALSE,
		CONSTRAINT perm_grp_once UNIQUE (grp,perm)
);

CREATE TABLE permission.usr_perm_map (
	id		SERIAL	PRIMARY KEY,
	usr		INT	NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	perm		INT	NOT NULL REFERENCES permission.perm_list (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	depth		INT	NOT NULL,
	grantable	BOOL	NOT NULL DEFAULT FALSE,
		CONSTRAINT perm_usr_once UNIQUE (usr,perm)
);

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

CREATE TABLE permission.usr_grp_map (
	id	SERIAL	PRIMARY KEY,
	usr	INT	NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	grp     INT     NOT NULL REFERENCES permission.grp_tree (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
		CONSTRAINT usr_grp_once UNIQUE (usr,grp)
);

CREATE OR REPLACE FUNCTION permission.grp_ancestors ( INT ) RETURNS SETOF permission.grp_tree AS $$
	SELECT	a.*
	FROM	connectby('permission.grp_tree'::text,'parent'::text,'id'::text,'name'::text,$1::text,100,'.'::text)
			AS t(keyid text, parent_keyid text, level int, branch text,pos int)
		JOIN permission.grp_tree a ON a.id::text = t.keyid::text
	ORDER BY
		CASE WHEN a.parent IS NULL
			THEN 0
			ELSE 1
		END, a.name;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION permission.usr_perms ( INT ) RETURNS SETOF permission.usr_perm_map AS $$
	SELECT	DISTINCT ON (usr,perm) *
	  FROM	(
			(SELECT * FROM permission.usr_perm_map WHERE usr = $1)
        				UNION ALL
			(SELECT	-p.id, $1 AS usr, p.perm, p.depth, p.grantable
			  FROM	permission.grp_perm_map p
			  WHERE	p.grp IN (
			  	SELECT	(permission.grp_ancestors(
						(SELECT profile FROM actor.usr WHERE id = $1)
					)).id
				)
			)
        				UNION ALL
			(SELECT	-p.id, $1 AS usr, p.perm, p.depth, p.grantable
			  FROM	permission.grp_perm_map p 
			  WHERE	p.grp IN (SELECT (permission.grp_ancestors(m.grp)).id FROM permission.usr_grp_map m WHERE usr = $1))
		) AS x
	  ORDER BY 2, 3, 1 DESC, 5 DESC ;
$$ LANGUAGE SQL STABLE;

CREATE TABLE permission.usr_work_ou_map (
	id	SERIAL	PRIMARY KEY,
	usr	INT	NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	work_ou INT     NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
		CONSTRAINT usr_work_ou_once UNIQUE (usr,work_ou)
);

CREATE OR REPLACE FUNCTION permission.usr_can_grant_perm ( iuser INT, tperm TEXT, target_ou INT ) RETURNS BOOL AS $$
DECLARE
	r_usr	actor.usr%ROWTYPE;
	r_perm	permission.usr_perm_map%ROWTYPE;
BEGIN

	SELECT * INTO r_usr FROM actor.usr WHERE id = iuser;

	IF r_usr.active = FALSE THEN
		RETURN FALSE;
	END IF;

	IF r_usr.super_user = TRUE THEN
		RETURN TRUE;
	END IF;

	FOR r_perm IN	SELECT	*
			  FROM	permission.usr_perms(iuser) p
				JOIN permission.perm_list l
					ON (l.id = p.perm)
			  WHERE	(l.code = tperm AND p.grantable IS TRUE)
		LOOP

		PERFORM	*
		  FROM	actor.org_unit_descendants(target_ou,r_perm.depth)
		  WHERE	id = r_usr.home_ou;

		IF FOUND THEN
			RETURN TRUE;
		ELSE
			RETURN FALSE;
		END IF;
	END LOOP;

	RETURN FALSE;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION permission.usr_has_home_perm ( iuser INT, tperm TEXT, target_ou INT ) RETURNS BOOL AS $$
DECLARE
	r_usr	actor.usr%ROWTYPE;
	r_perm	permission.usr_perm_map%ROWTYPE;
BEGIN

	SELECT * INTO r_usr FROM actor.usr WHERE id = iuser;

	IF r_usr.active = FALSE THEN
		RETURN FALSE;
	END IF;

	IF r_usr.super_user = TRUE THEN
		RETURN TRUE;
	END IF;

	FOR r_perm IN	SELECT	*
			  FROM	permission.usr_perms(iuser) p
				JOIN permission.perm_list l
					ON (l.id = p.perm)
			  WHERE	l.code = tperm
			  	OR p.perm = -1 LOOP

		PERFORM	*
		  FROM	actor.org_unit_descendants(target_ou,r_perm.depth)
		  WHERE	id = r_usr.home_ou;

		IF FOUND THEN
			RETURN TRUE;
		ELSE
			RETURN FALSE;
		END IF;
	END LOOP;

	RETURN FALSE;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION permission.usr_has_work_perm ( iuser INT, tperm TEXT, target_ou INT ) RETURNS BOOL AS $$
DECLARE
	r_woum	permission.usr_work_ou_map%ROWTYPE;
	r_usr	actor.usr%ROWTYPE;
	r_perm	permission.usr_perm_map%ROWTYPE;
BEGIN

	SELECT * INTO r_usr FROM actor.usr WHERE id = iuser;

	IF r_usr.active = FALSE THEN
		RETURN FALSE;
	END IF;

	IF r_usr.super_user = TRUE THEN
		RETURN TRUE;
	END IF;

	FOR r_perm IN	SELECT	*
			  FROM	permission.usr_perms(iuser) p
				JOIN permission.perm_list l
					ON (l.id = p.perm)
			  WHERE	l.code = tperm
			  	OR p.perm = -1
		LOOP

		FOR r_woum IN	SELECT	*
				  FROM	permission.usr_work_ou_map
				  WHERE	usr = iuser
			LOOP

			PERFORM	*
			  FROM	actor.org_unit_descendants(target_ou,r_perm.depth)
			  WHERE	id = r_woum.work_ou;

			IF FOUND THEN
				RETURN TRUE;
			END IF;

		END LOOP;

	END LOOP;

	RETURN FALSE;
END;
$$ LANGUAGE PLPGSQL;

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

CREATE OR REPLACE FUNCTION permission.usr_has_perm ( INT, TEXT, INT ) RETURNS BOOL AS $$
	SELECT	CASE
			WHEN permission.usr_has_home_perm( $1, $2, $3 ) THEN TRUE
			WHEN permission.usr_has_work_perm( $1, $2, $3 ) THEN TRUE
			ELSE FALSE
		END;
$$ LANGUAGE SQL;


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
		   AND upm.perm = n_perm
       				UNION
		SELECT	gpm.depth
		  FROM	permission.grp_perm_map gpm
		  WHERE	gpm.perm = n_perm 
	        AND gpm.grp IN (
	 		   SELECT	(permission.grp_ancestors(
					(SELECT profile FROM actor.usr WHERE id = user_id)
				)).id
			)
       				UNION
		SELECT	p.depth
		  FROM	permission.grp_perm_map p 
		  WHERE p.perm = n_perm
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
				SELECT ou::INTEGER
				FROM connectby( 
						'actor.org_unit',         -- table name
						'id',                     -- key column
						'parent_ou',              -- recursive foreign key
						n_work_ou::TEXT,          -- id of starting point
						(n_min_depth - n_depth)   -- max depth to search, relative
					)                             --   to starting point
					AS t(
						ou text,            -- dependent org unit
						parent_ou text,     -- (ignore)
						level int           -- depth relative to starting point
					)
				WHERE
					level = n_min_depth - n_depth
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
$$ LANGUAGE 'plpgsql';


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
		-- Use connectby() to find all dependent org units at the specified depth.
		--
		FOR n_child_ou IN
			SELECT ou::INTEGER
			FROM connectby( 
					'actor.org_unit',   -- table name
					'id',               -- key column
					'parent_ou',        -- recursive foreign key
					n_head_ou::TEXT,    -- id of starting point
					0                   -- no limit on search depth
				)
				AS t(
					ou text,            -- dependent org unit
					parent_ou text,     -- (ignore)
					level int           -- (ignore)
				)
		LOOP
			RETURN NEXT n_child_ou;
		END LOOP;
	END LOOP;
	--
	RETURN;
	--
END;
$$ LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION permission.usr_has_perm_at(
	user_id    IN INTEGER,
	perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
SELECT DISTINCT * FROM permission.usr_has_perm_at_nd( $1, $2 );
$$ LANGUAGE 'sql';


CREATE OR REPLACE FUNCTION permission.usr_has_perm_at_all(
	user_id    IN INTEGER,
	perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
SELECT DISTINCT * FROM permission.usr_has_perm_at_all_nd( $1, $2 );
$$ LANGUAGE 'sql';


COMMIT;

