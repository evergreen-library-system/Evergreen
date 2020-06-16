BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE action.in_house_use ADD COLUMN workstation INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE action.non_cat_in_house_use ADD COLUMN workstation INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED;

COMMIT;
