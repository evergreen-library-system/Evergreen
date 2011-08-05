--Upgrade script for lp818311.

BEGIN;

SELECT evergreen.upgrade_deps_block_check('0592', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 512, 'ACQ_INVOICE_REOPEN', oils_i18n_gettext( 512,
    'Allows a user to reopen an Acquisitions invoice', 'ppl', 'description' ));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Acquisitions Administrator' AND
		aout.name = 'Consortium' AND
		perm.code = 'ACQ_INVOICE_REOPEN';

COMMIT;
