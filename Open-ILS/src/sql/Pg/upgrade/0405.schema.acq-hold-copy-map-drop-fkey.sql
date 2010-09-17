-- Drop a foreign key.  It is commented out in 090.schema.action.sql
-- but was never dropped via an upgrade script.

-- No transaction, in case the fkey has already been dropped by
-- other means.

INSERT INTO config.upgrade_log (version) VALUES ('0405'); -- Scott McKellar

\qecho If the following ALTER TABLE fails because the constraint
\qecho being dropped doesn't exist, that's okay.  Ignore the failure.

ALTER TABLE action.hold_copy_map DROP CONSTRAINT hold_copy_map_target_copy_fkey;
