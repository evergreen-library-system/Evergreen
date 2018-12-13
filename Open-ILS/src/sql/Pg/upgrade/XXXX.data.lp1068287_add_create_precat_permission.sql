-- Evergreen DB patch XXXX.data.lp1068287_add_create_precat_perm.sql
--
-- Add a permission to prevent untrained/non-authorized staff from
-- adding pre-cat copies/items due to barcode misscans.
--
--BEGIN;

-- check whether patch can be applied
--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO permission.perm_list(id, code, description)
    VALUES (618, 'CREATE_PRECAT', 'Allows user to create a pre-catalogued copy');

-- Add this new permission to any group with Staff login perm.
-- Manually remove if needed
insert into permission.grp_perm_map(perm, grp, depth) select 618, map.grp, 0 from permission.grp_perm_map as map where map.perm = 2;

-- COMMIT;
