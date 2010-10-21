BEGIN;

CREATE OR REPLACE FUNCTION oils_text_as_bytea (TEXT) RETURNS BYTEA AS $_$
    SELECT CAST(REGEXP_REPLACE(UPPER($1), $$\\$$, $$\\\\$$, 'g') AS BYTEA);
$_$ LANGUAGE SQL IMMUTABLE;

DROP INDEX asset.asset_call_number_upper_label_id_owning_lib_idx;
CREATE INDEX asset_call_number_upper_label_id_owning_lib_idx ON asset.call_number (oils_text_as_bytea(label),id,owning_lib);

COMMIT;

