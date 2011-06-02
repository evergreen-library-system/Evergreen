BEGIN;

SELECT evergreen.upgrade_deps_block_check('0545', :eg_version);

INSERT INTO permission.perm_list VALUES
 (507, 'ABORT_TRANSIT_ON_LOST', oils_i18n_gettext(507, 'Allows a user to abort a transit on a copy with status of LOST', 'ppl', 'description')),
 (508, 'ABORT_TRANSIT_ON_MISSING', oils_i18n_gettext(508, 'Allows a user to abort a transit on a copy with status of MISSING', 'ppl', 'description'));

--- stock Circulation Administrator group

INSERT INTO permission.grp_perm_map ( grp, perm, depth, grantable )
    SELECT
        4,
        id,
        0,
        't'
    FROM permission.perm_list
    WHERE code in ('ABORT_TRANSIT_ON_LOST', 'ABORT_TRANSIT_ON_MISSING');

COMMIT;
