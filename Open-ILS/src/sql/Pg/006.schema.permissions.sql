DROP SCHEMA permission CASCADE;

BEGIN;
CREATE SCHEMA permission;

CREATE TABLE permission.perm_list (
	id		SERIAL	PRIMARY KEY,
	code		TEXT	NOT NULL UNIQUE,
	description	TEXT
);
CREATE INDEX perm_list_code_idx ON permission.perm_list (code);

INSERT INTO permission.perm_list VALUES (-1,'EVERYTHING');
INSERT INTO permission.perm_list VALUES (2, 'OPAC_LOGIN');
INSERT INTO permission.perm_list VALUES (4, 'STAFF_LOGIN');
INSERT INTO permission.perm_list VALUES (5, 'MR_HOLDS');
INSERT INTO permission.perm_list VALUES (6, 'TITLE_HOLDS');
INSERT INTO permission.perm_list VALUES (7, 'VOLUME_HOLDS');
INSERT INTO permission.perm_list VALUES (8, 'COPY_HOLDS');
INSERT INTO permission.perm_list VALUES (9, 'REQUEST_HOLDS');
INSERT INTO permission.perm_list VALUES (10, 'REQUEST_HOLDS_OVERRIDE');
INSERT INTO permission.perm_list VALUES (11, 'VIEW_HOLDS');
INSERT INTO permission.perm_list VALUES (13, 'DELETE_HOLDS');
INSERT INTO permission.perm_list VALUES (14, 'UPDATE_HOLDS');
INSERT INTO permission.perm_list VALUES (15, 'RENEW_CIRC');
INSERT INTO permission.perm_list VALUES (16, 'VIEW_USER_FINES_SUMMARY');
INSERT INTO permission.perm_list VALUES (17, 'VIEW_USER_TRANSACTIONS');
INSERT INTO permission.perm_list VALUES (18, 'UPDATE_MARC');
INSERT INTO permission.perm_list VALUES (19, 'CREATE_ORIGINAL_MARC');
INSERT INTO permission.perm_list VALUES (20, 'IMPORT_MARC');
INSERT INTO permission.perm_list VALUES (21, 'CREATE_VOLUME');
INSERT INTO permission.perm_list VALUES (22, 'UPDATE_VOLUME');
INSERT INTO permission.perm_list VALUES (23, 'DELETE_VOLUME');
INSERT INTO permission.perm_list VALUES (24, 'CREATE_COPY');
INSERT INTO permission.perm_list VALUES (25, 'UPDATE_COPY');
INSERT INTO permission.perm_list VALUES (26, 'DELETE_COPY');
INSERT INTO permission.perm_list VALUES (27, 'RENEW_HOLD_OVERRIDE');
INSERT INTO permission.perm_list VALUES (28, 'CREATE_USER');
INSERT INTO permission.perm_list VALUES (29, 'UPDATE_USER');
INSERT INTO permission.perm_list VALUES (30, 'DELETE_USER');
INSERT INTO permission.perm_list VALUES (31, 'VIEW_USER');
INSERT INTO permission.perm_list VALUES (32, 'COPY_CHECKIN');
INSERT INTO permission.perm_list VALUES (33, 'CREATE_TRANSIT');
INSERT INTO permission.perm_list VALUES (34, 'VIEW_PERMISSION');
INSERT INTO permission.perm_list VALUES (35, 'CHECKIN_BYPASS_HOLD_FULFILL');
INSERT INTO permission.perm_list VALUES (36, 'CREATE_PAYMENT');
INSERT INTO permission.perm_list VALUES (37, 'SET_CIRC_LOST');
INSERT INTO permission.perm_list VALUES (38, 'SET_CIRC_MISSING');
INSERT INTO permission.perm_list VALUES (39, 'SET_CIRC_CLAIMS_RETURNED');

SELECT SETVAL('permission.perm_list_id_seq'::TEXT, 40);

CREATE TABLE permission.grp_tree (
	id		SERIAL	PRIMARY KEY,
	name		TEXT	NOT NULL UNIQUE,
	parent		INT	REFERENCES permission.grp_tree (id) ON DELETE RESTRICT,
	description	TEXT
);
CREATE INDEX grp_tree_parent ON permission.grp_tree (parent);

INSERT INTO permission.grp_tree VALUES (1, 'Users', NULL);
INSERT INTO permission.grp_tree VALUES (2, 'Patrons', 1);
INSERT INTO permission.grp_tree VALUES (3, 'Staff', 1);
INSERT INTO permission.grp_tree VALUES (4, 'Catalogers', 3);
INSERT INTO permission.grp_tree VALUES (5, 'Circulators', 3);

SELECT SETVAL('permission.grp_tree_id_seq'::TEXT, 6);

CREATE TABLE permission.grp_perm_map (
	id		SERIAL	PRIMARY KEY,
	grp		INT	NOT NULL REFERENCES permission.grp_tree (id) ON DELETE CASCADE,
	perm		INT	NOT NULL REFERENCES permission.perm_list (id) ON DELETE CASCADE,
	depth		INT	NOT NULL,
	grantable	BOOL	NOT NULL DEFAULT FALSE,
		CONSTRAINT perm_grp_once UNIQUE (grp,perm)
);

INSERT INTO permission.grp_perm_map VALUES (1, 1, 2, 0); 
INSERT INTO permission.grp_perm_map VALUES (12, 1, 5, 0);
INSERT INTO permission.grp_perm_map VALUES (13, 1, 6, 0);
INSERT INTO permission.grp_perm_map VALUES (15, 4, 8, 2);
INSERT INTO permission.grp_perm_map VALUES (22, 4, 18, 0);
INSERT INTO permission.grp_perm_map VALUES (23, 4, 19, 0);
INSERT INTO permission.grp_perm_map VALUES (24, 4, 20, 0);
INSERT INTO permission.grp_perm_map VALUES (38, 4, 21, 2);
INSERT INTO permission.grp_perm_map VALUES (34, 4, 22, 2);
INSERT INTO permission.grp_perm_map VALUES (39, 4, 23, 2);
INSERT INTO permission.grp_perm_map VALUES (40, 4, 24, 2);
INSERT INTO permission.grp_perm_map VALUES (35, 4, 25, 2);
INSERT INTO permission.grp_perm_map VALUES (11, 3, 4, 0);
INSERT INTO permission.grp_perm_map VALUES (14, 3, 7, 2);
INSERT INTO permission.grp_perm_map VALUES (16, 3, 9, 0);
INSERT INTO permission.grp_perm_map VALUES (17, 3, 11, 0);
INSERT INTO permission.grp_perm_map VALUES (19, 3, 15, 0);
INSERT INTO permission.grp_perm_map VALUES (20, 3, 16, 0);
INSERT INTO permission.grp_perm_map VALUES (21, 3, 17, 0);
INSERT INTO permission.grp_perm_map VALUES (26, 3, 27, 0);
INSERT INTO permission.grp_perm_map VALUES (27, 3, 28, 0);
INSERT INTO permission.grp_perm_map VALUES (28, 3, 29, 0);
INSERT INTO permission.grp_perm_map VALUES (29, 3, 30, 0);
INSERT INTO permission.grp_perm_map VALUES (44, 3, 31, 0);
INSERT INTO permission.grp_perm_map VALUES (30, 3, 32, 0);
INSERT INTO permission.grp_perm_map VALUES (31, 3, 33, 0);
INSERT INTO permission.grp_perm_map VALUES (32, 3, 34, 0);
INSERT INTO permission.grp_perm_map VALUES (33, 3, 35, 0);
INSERT INTO permission.grp_perm_map VALUES (41, 3, 36, 0);
INSERT INTO permission.grp_perm_map VALUES (45, 3, 37, 0);
INSERT INTO permission.grp_perm_map VALUES (46, 3, 38, 0);
INSERT INTO permission.grp_perm_map VALUES (47, 3, 39, 0);

SELECT SETVAL('permission.grp_perm_map_id_seq'::TEXT, 48);


CREATE TABLE permission.usr_perm_map (
	id		SERIAL	PRIMARY KEY,
	usr		INT	NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE,
	perm		INT	NOT NULL REFERENCES permission.perm_list (id) ON DELETE CASCADE,
	depth		INT	NOT NULL,
	grantable	BOOL	NOT NULL DEFAULT FALSE,
		CONSTRAINT perm_usr_once UNIQUE (usr,perm)
);

CREATE TABLE permission.usr_grp_map (
	id	SERIAL	PRIMARY KEY,
	usr	INT	NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE,
	grp     INT     NOT NULL REFERENCES permission.grp_tree (id) ON DELETE CASCADE,
		CONSTRAINT usr_grp_once UNIQUE (usr,grp)
);

-- Admin user
INSERT INTO permission.usr_perm_map (usr,perm,depth) VALUES (1,-1,0);

CREATE OR REPLACE FUNCTION permission.grp_ancestors ( INT ) RETURNS SETOF permission.grp_tree AS $$
	SELECT	a.*
	FROM	connectby('permission.grp_tree','parent','id','name',$1,'100','.')
			AS t(keyid text, parent_keyid text, level int, branch text,pos int)
		JOIN permission.grp_tree a ON a.id = t.keyid
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

CREATE OR REPLACE FUNCTION permission.usr_has_perm ( iuser INT, tperm TEXT, target_ou INT ) RETURNS BOOL AS $$
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

COMMIT;

