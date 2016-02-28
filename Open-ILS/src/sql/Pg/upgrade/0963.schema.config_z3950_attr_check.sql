BEGIN;

SELECT evergreen.upgrade_deps_block_check('0963', :eg_version);

ALTER TABLE config.z3950_index_field_map DROP CONSTRAINT "valid_z3950_attr_type";

DROP FUNCTION evergreen.z3950_attr_name_is_valid(text);

CREATE OR REPLACE FUNCTION evergreen.z3950_attr_name_is_valid() RETURNS TRIGGER AS $func$
BEGIN

  PERFORM * FROM config.z3950_attr WHERE name = NEW.z3950_attr_type;

  IF FOUND THEN
    RETURN NULL;
  END IF;

  RAISE EXCEPTION '% is not a valid Z39.50 attribute type', NEW.z3950_attr_type;

END;
$func$ LANGUAGE PLPGSQL STABLE;

COMMENT ON FUNCTION evergreen.z3950_attr_name_is_valid() IS $$
Used by a config.z3950_index_field_map constraint trigger
to verify z3950_attr_type maps.
$$;

CREATE CONSTRAINT TRIGGER valid_z3950_attr_type AFTER INSERT OR UPDATE ON config.z3950_index_field_map
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN (NEW.z3950_attr_type IS NOT NULL)
  EXECUTE PROCEDURE evergreen.z3950_attr_name_is_valid();

COMMIT;

