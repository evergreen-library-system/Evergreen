BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0301'); -- gmc

CREATE TEMPORARY TABLE eg_0301_check_if_has_contents (
    flag INTEGER PRIMARY KEY
) ON COMMIT DROP;
INSERT INTO eg_0301_check_if_has_contents VALUES (1);

-- cause failure if either of the tables we want to drop have rows
INSERT INTO eg_0301_check_if_has_contents SELECT 1 FROM asset.copy_transparency LIMIT 1;
INSERT INTO eg_0301_check_if_has_contents SELECT 1 FROM asset.copy_transparency_map LIMIT 1;

DROP TABLE asset.copy_transparency_map;
DROP TABLE asset.copy_transparency;

COMMIT;
