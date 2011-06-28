-- Evergreen DB patch XXXX.data.collections_exempt_perm.sql
--
-- Adds a new UPDATE_PATRON_COLLECTIONS_EXEMPT permission
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0563', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) 
    VALUES ( 510, 'UPDATE_PATRON_COLLECTIONS_EXEMPT', oils_i18n_gettext(510,
    'Allows a user to indicate that a patron is exempt from collections processing', 'ppl', 'description'));

--- stock Circulation Administrator group

INSERT INTO permission.grp_perm_map ( grp, perm, depth, grantable )
    SELECT
        4,
        id,
        0,
        't'
    FROM permission.perm_list
    WHERE code in ('UPDATE_PATRON_COLLECTIONS_EXEMPT');

COMMIT;
