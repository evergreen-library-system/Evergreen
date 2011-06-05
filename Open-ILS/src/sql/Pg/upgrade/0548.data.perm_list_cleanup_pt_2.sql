BEGIN;

SELECT evergreen.upgrade_deps_block_check('0548', :eg_version); -- dbwells

\qecho This redoes the original part 1 of 0547 which did not apply to rel_2_1,
\qecho and is being added for the sake of clarity

-- delete errant inserts from 0545 (group 4 is NOT the circulation admin group)
DELETE FROM permission.grp_perm_map WHERE grp = 4 AND perm IN (
	SELECT id FROM permission.perm_list
	WHERE code in ('ABORT_TRANSIT_ON_LOST', 'ABORT_TRANSIT_ON_MISSING')
);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Circulation Administrator' AND
		aout.name = 'Consortium' AND
		perm.code IN (
			'ABORT_TRANSIT_ON_LOST',
			'ABORT_TRANSIT_ON_MISSING'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

COMMIT;
