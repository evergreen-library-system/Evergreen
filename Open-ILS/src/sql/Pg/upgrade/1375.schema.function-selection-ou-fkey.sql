BEGIN;

SELECT evergreen.upgrade_deps_block_check('1375', :eg_version);

UPDATE action.hold_request 
SET selection_ou = request_lib
WHERE selection_ou NOT IN (
    SELECT id FROM actor.org_unit
);

ALTER TABLE action.hold_request ADD CONSTRAINT hold_request_selection_ou_fkey FOREIGN KEY (selection_ou) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED NOT VALID;
ALTER TABLE action.hold_request VALIDATE CONSTRAINT hold_request_selection_ou_fkey;

COMMIT;
