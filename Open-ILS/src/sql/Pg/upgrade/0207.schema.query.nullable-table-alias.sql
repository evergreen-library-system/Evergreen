BEGIN;

-- Allow table_alias to be nullable, but don't require it
-- to be null for core tables.

INSERT INTO config.upgrade_log (version) VALUES ('0207'); -- Scott McKellar

ALTER TABLE query.from_relation
	ALTER COLUMN table_alias DROP NOT NULL;

ALTER TABLE query.from_relation
	DROP CONSTRAINT join_or_core;

ALTER TABLE query.from_relation
	ADD CONSTRAINT join_or_core CHECK (
        ( parent_relation IS NULL AND join_type IS NULL
          AND on_clause IS NULL )
        OR
        ( parent_relation IS NOT NULL AND join_type IS NOT NULL
          AND on_clause IS NOT NULL )
    );

COMMIT;
