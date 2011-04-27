BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0526'); --miker

CREATE TABLE config.db_patch_dependencies (
  db_patch      TEXT PRIMARY KEY,
  supersedes    TEXT[],
  deprecates    TEXT[]
);

CREATE OR REPLACE FUNCTION evergreen.array_overlap_check (/* field */) RETURNS TRIGGER AS $$
DECLARE
    fld     TEXT;
    cnt     INT;
BEGIN
    fld := TG_ARGV[1];
    EXECUTE 'SELECT COUNT(*) FROM '|| TG_TABLE_SCHEMA ||'.'|| TG_TABLE_NAME ||' WHERE '|| fld ||' && ($1).'|| fld INTO cnt USING NEW;
    IF cnt > 0 THEN
        RAISE EXCEPTION 'Cannot insert duplicate array into field % of table %', fld, TG_TABLE_SCHEMA ||'.'|| TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER no_overlapping_sups
    BEFORE INSERT OR UPDATE ON config.db_patch_dependencies
    FOR EACH ROW EXECUTE PROCEDURE evergreen.array_overlap_check ('supersedes');

CREATE TRIGGER no_overlapping_deps
    BEFORE INSERT OR UPDATE ON config.db_patch_dependencies
    FOR EACH ROW EXECUTE PROCEDURE evergreen.array_overlap_check ('deprecates');

ALTER TABLE config.upgrade_log
    ADD COLUMN applied_to TEXT;

-- List applied db patches that are deprecated by (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_deprecates ( my_db_patch TEXT ) RETURNS SETOF TEXT AS $$
    SELECT  DISTINCT l.version
      FROM  config.upgrade_log l
            JOIN config.db_patch_dependencies d ON (l.version::TEXT[] && d.deprecates)
      WHERE d.db_patch = $1
$$ LANGUAGE SQL;

-- List applied db patches that are superseded by (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_supersedes ( my_db_patch TEXT ) RETURNS SETOF TEXT AS $$
    SELECT  DISTINCT l.version
      FROM  config.upgrade_log l
            JOIN config.db_patch_dependencies d ON (l.version::TEXT[] && d.supersedes)
      WHERE d.db_patch = $1
$$ LANGUAGE SQL;

-- List applied db patches that deprecates (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_deprecated ( my_db_patch TEXT ) RETURNS TEXT AS $$
    SELECT  db_patch
      FROM  config.db_patch_dependencies
      WHERE ARRAY[$1]::TEXT[] && deprecates
$$ LANGUAGE SQL;

-- List applied db patches that supersedes (and block the application of) my_db_patch
CREATE OR REPLACE FUNCTION evergreen.upgrade_list_applied_superseded ( my_db_patch TEXT ) RETURNS TEXT AS $$
    SELECT  db_patch
      FROM  config.db_patch_dependencies
      WHERE ARRAY[$1]::TEXT[] && supersedes
$$ LANGUAGE SQL;

-- Make sure that no deprecated or superseded db patches are currently applied
CREATE OR REPLACE FUNCTION evergreen.upgrade_verify_no_dep_conflicts ( my_db_patch TEXT ) RETURNS BOOL AS $$
    SELECT  COUNT(*) = 0
      FROM  (SELECT * FROM evergreen.upgrade_list_applied_deprecates( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_supersedes( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_deprecated( $1 )
                UNION
             SELECT * FROM evergreen.upgrade_list_applied_superseded( $1 ))x
$$ LANGUAGE SQL;

-- Raise an exception if there are, in fact, dep/sup confilct
CREATE OR REPLACE FUNCTION evergreen.upgrade_deps_block_check ( my_db_patch TEXT, my_applied_to TEXT ) RETURNS BOOL AS $$
BEGIN
    IF NOT evergreen.upgrade_verify_no_dep_conflicts( my_db_patch ) THEN
        RAISE EXCEPTION '
Upgrade script % can not be applied:
  applied deprecated scripts %
  applied superseded scripts %
  deprecated by %
  superseded by %',
            my_db_patch,
            ARRAY_ACUM(evergreen.upgrade_list_applied_deprecates(my_db_patch)),
            ARRAY_ACUM(evergreen.upgrade_list_applied_supersedes(my_db_patch)),
            evergreen.upgrade_list_applied_deprecated(my_db_patch),
            evergreen.upgrade_list_applied_superseded(my_db_patch);
    END IF;

    INSERT INTO config.upgrade_log (version, applied_to) VALUES (my_db_patch, my_applied_to);
    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;

COMMIT;
