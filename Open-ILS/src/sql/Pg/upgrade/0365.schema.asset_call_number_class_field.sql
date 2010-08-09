BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0365'); -- dbs

ALTER TABLE asset.call_number_class ADD COLUMN field TEXT NOT NULL DEFAULT '050ab,055ab,060ab,070ab,080ab,082ab,086ab,088ab,090,092,096,098,099';

COMMENT ON TABLE asset.call_number_class IS $$
Defines the call number normalization database functions in the "normalizer"
column and the tag/subfield combinations to use to lookup the call number in
the "field" column for a given classification scheme. Tag/subfield combinations
are delimited by commas.
$$;

-- Generic fields
UPDATE asset.call_number_class
    SET field = '050ab,055ab,060ab,070ab,080ab,082ab,086ab,088ab,090,092,096,098,099'
    WHERE id = 1
;

-- Dewey fields
UPDATE asset.call_number_class
    SET field = '080ab,082ab'
    WHERE id = 2
;

-- LC fields
UPDATE asset.call_number_class
    SET field = '050ab,055ab'
    WHERE id = 3
;

COMMIT;
