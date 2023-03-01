BEGIN;

SELECT evergreen.upgrade_deps_block_check('1356', :eg_version);

UPDATE config.global_flag
SET label = 'Age billings and payments when circulations are aged.'
WHERE name = 'history.money.age_with_circs'
  AND label = 'Age billings and payments when cirulcations are aged.';

COMMIT;
