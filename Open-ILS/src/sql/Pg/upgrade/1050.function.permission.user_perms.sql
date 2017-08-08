BEGIN;

SELECT evergreen.upgrade_deps_block_check('1050', :eg_version); -- mmorgan/cesardv/gmcharlt

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
	  ORDER BY 2, 3, 4 ASC, 5 DESC ;
$$ LANGUAGE SQL STABLE ROWS 10;

COMMIT;

