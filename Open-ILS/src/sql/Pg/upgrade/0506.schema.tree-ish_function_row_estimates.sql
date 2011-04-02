BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0506'); -- miker

ALTER FUNCTION actor.org_unit_descendants( INT, INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_descendants( INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_descendants_distance( INT )  ROWS 1;
ALTER FUNCTION actor.org_unit_ancestors( INT )  ROWS 1;
ALTER FUNCTION actor.org_unit_ancestors_distance( INT )  ROWS 1;
ALTER FUNCTION actor.org_unit_full_path ( INT )  ROWS 2;
ALTER FUNCTION actor.org_unit_full_path ( INT, INT ) ROWS 2;
ALTER FUNCTION actor.org_unit_combined_ancestors ( INT, INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_common_ancestors ( INT, INT ) ROWS 1;
ALTER FUNCTION actor.org_unit_ancestor_setting( TEXT, INT ) ROWS 1;
ALTER FUNCTION permission.grp_ancestors ( INT ) ROWS 1;
ALTER FUNCTION permission.grp_ancestors_distance( INT ) ROWS 1;
ALTER FUNCTION permission.grp_descendants_distance( INT ) ROWS 1;
ALTER FUNCTION permission.usr_perms ( INT ) ROWS 10;
ALTER FUNCTION permission.usr_has_perm_at_nd ( INT, TEXT) ROWS 1;
ALTER FUNCTION permission.usr_has_perm_at_all_nd ( INT, TEXT ) ROWS 1;
ALTER FUNCTION permission.usr_has_perm_at ( INT, TEXT ) ROWS 1;
ALTER FUNCTION permission.usr_has_perm_at_all ( INT, TEXT ) ROWS 1;

COMMIT;

