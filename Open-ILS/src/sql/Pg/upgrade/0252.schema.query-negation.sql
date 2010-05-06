BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0252'); -- Scott McKellar

ALTER TABLE query.expression
	ADD COLUMN negate BOOL NOT NULL DEFAULT FALSE;

COMMIT;

-- The following DROPs will fail if the views being dropped don't exist,
-- and that's okay.  That's why they're outside of the BEGIN/COMMIT.

DROP VIEW query.expr_xnbet;

DROP VIEW query.expr_xnex;

DROP VIEW query.expr_xnin;

