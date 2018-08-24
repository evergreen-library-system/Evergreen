BEGIN;

SELECT evergreen.upgrade_deps_block_check('1120', :eg_version);

--Only insert if the attributes are not already present

INSERT INTO config.z3950_attr (source, name, label, code, format, truncation)
SELECT 'oclc','upc','UPC','1007','6','0'
WHERE NOT EXISTS (SELECT name FROM config.z3950_attr WHERE source = 'oclc' AND name = 'upc');

INSERT INTO config.z3950_attr (source, name, label, code, format, truncation)
SELECT 'loc','upc','UPC','1007','1','1'
WHERE NOT EXISTS (SELECT name FROM config.z3950_attr WHERE source = 'loc' AND name = 'upc');

COMMIT;
