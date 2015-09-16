--Upgrade Script for 2.8.3 to 2.8.4
\set eg_version '''2.8.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.8.4', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0941', :eg_version);

UPDATE authority.control_set_authority_field SET sf_list = REGEXP_REPLACE( sf_list, 'e', '', 'i') WHERE tag = '100' AND control_set = 1 AND  sf_list ILIKE '%e%';

UPDATE authority.control_set_authority_field SET sf_list = REGEXP_REPLACE( sf_list, 'e', '', 'i') WHERE tag = '110' AND control_set = 1 AND  sf_list ILIKE '%e%';

COMMIT;
