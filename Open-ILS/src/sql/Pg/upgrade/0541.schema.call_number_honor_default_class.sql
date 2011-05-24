BEGIN;

SELECT evergreen.upgrade_deps_block_check('0541', :eg_version); -- dbwells

ALTER TABLE asset.call_number ALTER COLUMN label_class DROP DEFAULT;

CREATE OR REPLACE FUNCTION asset.label_normalizer() RETURNS TRIGGER AS $func$
DECLARE
    sortkey        TEXT := '';
BEGIN
    sortkey := NEW.label_sortkey;

    IF NEW.label_class IS NULL THEN
        NEW.label_class := COALESCE( (SELECT substring(value from E'\\d+')::integer from actor.org_unit_setting WHERE name = 'cat.default_classification_scheme' AND org_unit = NEW.owning_lib), 1);
    END IF;

    EXECUTE 'SELECT ' || acnc.normalizer || '(' ||
       quote_literal( NEW.label ) || ')'
       FROM asset.call_number_class acnc
       WHERE acnc.id = NEW.label_class
       INTO sortkey;
    NEW.label_sortkey = sortkey;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
