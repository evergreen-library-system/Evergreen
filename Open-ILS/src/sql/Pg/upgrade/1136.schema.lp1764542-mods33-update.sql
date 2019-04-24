BEGIN;

SELECT evergreen.upgrade_deps_block_check('1136', :eg_version);

-- update mods33 data entered by 1100 with a format of 'mods32'
-- harmless if you have not run 1100 yet
UPDATE config.metabib_field SET format = 'mods33' WHERE format = 'mods32' and id in (38, 39, 40, 41, 42, 43, 44, 46, 47, 48, 49, 50);

-- change the default format to 'mods33'
ALTER TABLE config.metabib_field ALTER COLUMN format SET DEFAULT 'mods33'::text;

COMMIT;
