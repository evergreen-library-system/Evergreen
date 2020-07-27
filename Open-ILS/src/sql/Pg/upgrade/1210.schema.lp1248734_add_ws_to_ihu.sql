BEGIN;

SELECT evergreen.upgrade_deps_block_check('1210', :eg_version); -- csharp/rhamby/sandbergja/gmcharlt

ALTER TABLE action.in_house_use ADD COLUMN workstation INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE action.non_cat_in_house_use ADD COLUMN workstation INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX action_in_house_use_ws_idx ON action.in_house_use ( workstation );
CREATE INDEX non_cat_in_house_use_ws_idx ON action.non_cat_in_house_use ( workstation );

COMMIT;
