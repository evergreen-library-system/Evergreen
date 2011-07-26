BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0586', :eg_version);

INSERT INTO permission.perm_list (id, code, description) VALUES (
    511,
    'PERSISTENT_LOGIN',
    oils_i18n_gettext(
        511,
        'Allows a user to authenticate and get a long-lived session (length configured in opensrf.xml)',
        'ppl',
        'description'
    )
);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT
        pgt.id, perm.id, aout.depth, FALSE
    FROM
        permission.grp_tree pgt,
        permission.perm_list perm,
        actor.org_unit_type aout
    WHERE
        pgt.name = 'Users' AND
        aout.name = 'Consortium' AND
        perm.code = 'PERSISTENT_LOGIN';

\qecho 
\qecho If this transaction succeeded, your users (staff and patrons) now have
\qecho the PERSISTENT_LOGIN permission by default.
\qecho 

COMMIT;

