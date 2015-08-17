BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('XXXX');

-- TODO: ask community if I should be warnign users that my code only fixes 100 & 110 auth tags for default (id=1) control set

UPDATE authority.control_set_authority_field SET sf_list = REGEXP_REPLACE( sf_list, 'e', '', 'i') WHERE tag = '100' AND control_set = 1 AND  sf_list ILIKE '%e%';

UPDATE authority.control_set_authority_field SET sf_list = REGEXP_REPLACE( sf_list, 'e', '', 'i') WHERE tag = '110' AND control_set = 1 AND  sf_list ILIKE '%e%';

COMMIT;
