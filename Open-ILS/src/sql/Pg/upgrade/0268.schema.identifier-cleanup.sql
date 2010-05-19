BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0268'); -- miker

CREATE OR REPLACE FUNCTION public.first_word ( TEXT ) RETURNS TEXT AS $$
        SELECT COALESCE(SUBSTRING( $1 FROM $_$^\S+$_$), '');
$$ LANGUAGE SQL STRICT IMMUTABLE;

DELETE FROM config.metabib_field_index_norm_map WHERE norm IN (1,2) and field > 16;

COMMIT;

