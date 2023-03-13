BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

UPDATE action.hold_request 
SET selection_ou = request_lib
WHERE id IN (
    SELECT ahr.id FROM action.hold_request ahr
    LEFT JOIN actor.org_unit aou ON aou.id = ahr.selection_ou
    WHERE aou.id IS NULL
);

ALTER TABLE action.hold_request ADD CONSTRAINT hold_request_selection_ou_fkey FOREIGN KEY (selection_ou) REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED;

COMMIT;
