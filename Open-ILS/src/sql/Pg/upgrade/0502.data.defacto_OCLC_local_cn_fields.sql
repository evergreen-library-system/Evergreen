BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0502'); -- dbwells

-- Dewey fields
UPDATE asset.call_number_class
    SET field = '080ab,082ab,092abef'
    WHERE id = 2
;

-- LC fields
UPDATE asset.call_number_class
    SET field = '050ab,055ab,090abef'
    WHERE id = 3
;

COMMIT;
