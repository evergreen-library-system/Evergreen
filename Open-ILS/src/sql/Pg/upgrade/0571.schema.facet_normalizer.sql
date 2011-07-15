-- Evergreen DB patch 0571.schema.facet_normalizer.sql
--
-- Alternate implementation of a regression fix for facet normalization
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0571', :eg_version);

-- FIXME: add/check SQL statements to perform the upgrade
CREATE OR REPLACE FUNCTION metabib.facet_normalize_trigger () RETURNS TRIGGER AS $$
DECLARE
    normalizer  RECORD;
    facet_text  TEXT;
BEGIN
    facet_text := NEW.value;

    FOR normalizer IN
        SELECT  n.func AS func,
                n.param_count AS param_count,
                m.params AS params
          FROM  config.index_normalizer n
                JOIN config.metabib_field_index_norm_map m ON (m.norm = n.id)
          WHERE m.field = NEW.field AND m.pos < 0
          ORDER BY m.pos LOOP

            EXECUTE 'SELECT ' || normalizer.func || '(' ||
                quote_literal( facet_text ) ||
                CASE
                    WHEN normalizer.param_count > 0
                        THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                        ELSE ''
                    END ||
                ')' INTO facet_text;

    END LOOP;

    NEW.value = facet_text;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER facet_normalize_tgr
    BEFORE UPDATE OR INSERT ON metabib.facet_entry
    FOR EACH ROW EXECUTE PROCEDURE metabib.facet_normalize_trigger();



COMMIT;
