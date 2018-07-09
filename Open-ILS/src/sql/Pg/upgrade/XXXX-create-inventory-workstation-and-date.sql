BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE TABLE asset.last_copy_inventory (
    id                          SERIAL                      PRIMARY KEY,
    inventory_workstation       INTEGER                     REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,
    inventory_date              TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
    copy                        BIGINT                      NOT NULL
);
CREATE INDEX last_copy_inventory_copy_idx ON asset.last_copy_inventory (copy);

CREATE OR REPLACE FUNCTION evergreen.asset_last_copy_inventory_copy_inh_fkey() RETURNS TRIGGER AS $f$
BEGIN
        PERFORM 1 FROM asset.copy WHERE id = NEW.copy;
        IF NOT FOUND THEN
                RAISE foreign_key_violation USING MESSAGE = FORMAT(
                        $$Referenced asset.copy id not found, copy:%s$$, NEW.copy
                );
        END IF;
        RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER inherit_asset_last_copy_inventory_copy_fkey
        AFTER UPDATE OR INSERT ON asset.last_copy_inventory
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_last_copy_inventory_copy_inh_fkey();

COMMIT;