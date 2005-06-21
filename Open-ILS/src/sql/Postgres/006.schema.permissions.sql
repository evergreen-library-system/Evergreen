DROP SCHEMA permission CASCADE;

BEGIN;
CREATE SCHEMA permission;

CREATE TABLE permission.perm_list (
	id	SERIAL	PRIMARY KEY,
	code	TEXT	NOT NULL UNIQUE
);
CREATE INDEX perm_list_code_idx ON permission.perm_list (code);
INSERT INTO permission.perm_list VALUES (DEFAULT,'EVERYTHING');
INSERT INTO permission.perm_list VALUES (DEFAULT,'OPAC_LOGIN');

CREATE TABLE permission.grp_tree (
	id	SERIAL	PRIMARY KEY,
	name	TEXT	NOT NULL UNIQUE,
	parent	INT	REFERENCES permission.grp_tree (id) ON DELETE RESTRICT
);
CREATE INDEX grp_tree_parent ON permission.grp_tree (parent);
INSERT INTO permission.grp_tree VALUES (DEFAULT,'Users');
INSERT INTO permission.grp_tree VALUES (DEFAULT,'Admin',1);

CREATE TABLE permission.grp_perm_map (
	id	SERIAL	PRIMARY KEY,
	grp	INT	NOT NULL REFERENCES permission.grp_tree (id),
	perm	INT	NOT NULL REFERENCES permission.perm_list (id),
	depth	INT	NOT NULL,
		CONSTRAINT perm_grp_once UNIQUE (grp,perm)
);
INSERT INTO permission.grp_perm_map VALUES (DEFAULT,1,2,0);
INSERT INTO permission.grp_perm_map VALUES (DEFAULT,2,1,0);

CREATE TABLE permission.usr_perm_map (
	id	SERIAL	PRIMARY KEY,
	usr	INT	NOT NULL REFERENCES actor.usr (id),
	perm	INT	NOT NULL REFERENCES permission.perm_list (id),
	depth	INT	NOT NULL,
		CONSTRAINT perm_usr_once UNIQUE (usr,perm)
);

CREATE TABLE permission.usr_grp_map (
	id	SERIAL	PRIMARY KEY,
	usr	INT	NOT NULL REFERENCES actor.usr (id),
	grp     INT     NOT NULL REFERENCES permission.grp_tree (id),
		CONSTRAINT usr_grp_once UNIQUE (usr,grp)
);

INSERT INTO permission.usr_grp_map (usr,grp)
	SELECT id, (SELECT id FROM permission.grp_tree WHERE parent IS NULL LIMIT 1) FROM actor.usr;

INSERT INTO permission.usr_grp_map (usr,grp)
	SELECT 1, id FROM permission.grp_tree WHERE name = 'Admin';

CREATE OR REPLACE RULE add_usr_to_group AS
	ON INSERT TO actor.usr DO ALSO
		INSERT	INTO permission.usr_grp_map (usr, grp) VALUES (
			NEW.id,
			(SELECT id FROM permission.grp_tree WHERE parent IS NULL LIMIT 1)
		);


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

CREATE OR REPLACE FUNCTION permission.usr_perms ( iuser INT ) RETURNS SETOF permission.usr_perm_map AS $$
DECLARE
	u_perm	permission.usr_perm_map%ROWTYPE;
	grp	permission.usr_grp_map%ROWTYPE;
	g_list	permission.grp_tree%ROWTYPE;
BEGIN
	FOR u_perm IN SELECT * FROM permission.usr_perm_map WHERE usr = iuser LOOP
		RETURN NEXT u_perm;
	END LOOP;
	
	FOR grp IN	SELECT	*
			  FROM	permission.usr_grp_map
			  WHERE	usr = iuser LOOP

		FOR g_list IN	SELECT	*
				  FROM	permission.grp_ancestors( grp.grp ) LOOP

			FOR u_perm IN	SELECT	DISTINCT -p.id, iuser AS usr, p.perm, p.depth
					  FROM	permission.grp_perm_map p
						JOIN permission.usr_grp_map m ON (m.grp = p.grp)
					  WHERE	m.grp = g_list.id LOOP

				RETURN NEXT u_perm;

			END LOOP;
		END LOOP;
	END LOOP;

	RETURN;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION permission.usr_has_perm ( iuser INT, tperm TEXT, target INT ) RETURNS BOOL AS $$
DECLARE
	r_usr	actor.usr%ROWTYPE;
	r_perm	permission.usr_perm_map%ROWTYPE;
BEGIN

	SELECT * INTO r_usr FROM actor.usr WHERE id = iuser;

	FOR r_perm IN	SELECT	*
			  FROM	permission.usr_perms(iuser) p
				JOIN permission.perm_list l
					ON (l.id = p.perm)
			  WHERE	l.code = tperm LOOP

		PERFORM	*
		  FROM	actor.org_unit_descendants(target,r_perm.depth)
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

