-- Evergreen DB patch XXXX.data.fix_inheritied_typo.sql
--
-- Fixes a typo in the name of a global flag

UPDATE config.global_flag
SET name = 'opac.org_unit.non_inherited_visibility'
WHERE name = 'opac.org_unit.non_inheritied_visibility';
