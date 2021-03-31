BEGIN;

SELECT evergreen.upgrade_deps_block_check('1258', :eg_version);

UPDATE config.metabib_field 
SET xpath =  '//*[@tag=''260'' or @tag=''264''][1]'
WHERE id = 52 AND xpath = '//*[@tag=''260'']';

COMMIT;
