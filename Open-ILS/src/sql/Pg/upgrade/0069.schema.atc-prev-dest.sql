BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0069');

ALTER TABLE action.transit_copy
ADD COLUMN prev_dest INTEGER REFERENCES actor.org_unit( id )
							 DEFERRABLE INITIALLY DEFERRED;

COMMIT;
