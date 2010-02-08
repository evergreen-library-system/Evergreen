
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0155'); -- miker

CREATE OR REPLACE FUNCTION public.remove_commas( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace($1, ',', '', 'g');
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION public.remove_whitespace( TEXT ) RETURNS TEXT AS $$
    SELECT regexp_replace(normalize_space($1), E'\\s+', '', 'g');
$$ LANGUAGE SQL;

COMMIT;
