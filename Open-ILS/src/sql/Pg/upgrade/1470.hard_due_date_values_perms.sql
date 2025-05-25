BEGIN;

SELECT evergreen.upgrade_deps_block_check('1470', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 688, 'UPDATE_HARD_DUE_DATE', oils_i18n_gettext(688,
     'Allow update hard due dates', 'ppl', 'description')),
 ( 689, 'CREATE_HARD_DUE_DATE', oils_i18n_gettext(689,
     'Allow create hard due dates', 'ppl', 'description')),
 ( 690, 'DELETE_HARD_DUE_DATE', oils_i18n_gettext(690,
     'Allow delete hard due dates', 'ppl', 'description')),
 ( 691, 'UPDATE_HARD_DUE_DATE_VALUE', oils_i18n_gettext(691,
     'Allow update hard due date values', 'ppl', 'description')),
 ( 692, 'CREATE_HARD_DUE_DATE_VALUE', oils_i18n_gettext(692,
     'Allow create hard due date values', 'ppl', 'description')),
 ( 693, 'DELETE_HARD_DUE_DATE_VALUE', oils_i18n_gettext(693,
     'Allow delete hard due date values', 'ppl', 'description'));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Circulation Administrator' AND
		aout.name = 'System' AND
		perm.code IN (
			'CREATE_HARD_DUE_DATE',
			'DELETE_HARD_DUE_DATE',
			'UPDATE_HARD_DUE_DATE',
			'CREATE_HARD_DUE_DATE_VALUE',
			'DELETE_HARD_DUE_DATE_VALUE',
			'UPDATE_HARD_DUE_DATE_VALUE'
		);

COMMIT;
