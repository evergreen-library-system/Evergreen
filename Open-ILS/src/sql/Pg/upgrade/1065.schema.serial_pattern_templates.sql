BEGIN;

SELECT evergreen.upgrade_deps_block_check('1065', :eg_version);

CREATE TABLE serial.pattern_template (
    id            SERIAL PRIMARY KEY,
    name          TEXT NOT NULL,
    pattern_code  TEXT NOT NULL,
    owning_lib    INTEGER REFERENCES actor.org_unit(id) DEFERRABLE INITIALLY DEFERRED,
    share_depth   INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX serial_pattern_template_name_idx ON serial.pattern_template (evergreen.lowercase(name));

CREATE OR REPLACE FUNCTION serial.pattern_templates_visible_to(org_unit INT) RETURNS SETOF serial.pattern_template AS $func$
BEGIN
    RETURN QUERY SELECT *
           FROM serial.pattern_template spt
           WHERE (
             SELECT ARRAY_AGG(id)
             FROM actor.org_unit_descendants(spt.owning_lib, spt.share_depth)
           ) @@ org_unit::TEXT::QUERY_INT;
END;
$func$ LANGUAGE PLPGSQL;

COMMIT;
