BEGIN;

SELECT evergreen.upgrade_deps_block_check('1321', :eg_version);

CREATE TABLE asset.copy_inventory (
    id                          SERIAL                      PRIMARY KEY,
    inventory_workstation       INTEGER                     REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,
    inventory_date              TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    copy                        BIGINT                      NOT NULL
);
CREATE INDEX copy_inventory_copy_idx ON asset.copy_inventory (copy);
CREATE UNIQUE INDEX asset_copy_inventory_date_once_per_copy ON asset.copy_inventory (inventory_date, copy);

CREATE OR REPLACE FUNCTION evergreen.asset_copy_inventory_copy_inh_fkey() RETURNS TRIGGER AS $f$
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

CREATE CONSTRAINT TRIGGER inherit_asset_copy_inventory_copy_fkey
        AFTER UPDATE OR INSERT ON asset.copy_inventory
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_copy_inventory_copy_inh_fkey();

CREATE OR REPLACE FUNCTION asset.copy_may_float_to_inventory_workstation() RETURNS TRIGGER AS $func$
DECLARE
    copy asset.copy%ROWTYPE;
    workstation actor.workstation%ROWTYPE;
BEGIN
    SELECT * INTO copy FROM asset.copy WHERE id = NEW.copy;
    IF FOUND THEN
        SELECT * INTO workstation FROM actor.workstation WHERE id = NEW.inventory_workstation;
        IF FOUND THEN
           IF copy.floating IS NULL THEN
              IF copy.circ_lib <> workstation.owning_lib THEN
                 RAISE EXCEPTION 'Inventory workstation owning lib (%) does not match copy circ lib (%).',
                       workstation.owning_lib, copy.circ_lib;
              END IF;
           ELSE
              IF NOT evergreen.can_float(copy.floating, copy.circ_lib, workstation.owning_lib) THEN
                 RAISE EXCEPTION 'Copy (%) cannot float to inventory workstation owning lib (%).',
                       copy.id, workstation.owning_lib;
              END IF;
           END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL VOLATILE COST 50;

CREATE CONSTRAINT TRIGGER asset_copy_inventory_allowed_trig
        AFTER UPDATE OR INSERT ON asset.copy_inventory
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE asset.copy_may_float_to_inventory_workstation();

INSERT INTO asset.copy_inventory
(inventory_workstation, inventory_date, copy)
SELECT DISTINCT ON (inventory_date, copy) inventory_workstation, inventory_date, copy
FROM asset.latest_inventory
JOIN asset.copy acp ON acp.id = latest_inventory.copy
JOIN actor.workstation ON workstation.id = latest_inventory.inventory_workstation
WHERE acp.circ_lib = workstation.owning_lib
UNION
SELECT DISTINCT ON (inventory_date, copy) inventory_workstation, inventory_date, copy
FROM asset.latest_inventory
JOIN asset.copy acp ON acp.id = latest_inventory.copy
JOIN actor.workstation ON workstation.id = latest_inventory.inventory_workstation
WHERE acp.circ_lib <> workstation.owning_lib
AND acp.floating IS NOT NULL
AND evergreen.can_float(acp.floating, acp.circ_lib, workstation.owning_lib)
ORDER by inventory_date;

DROP TABLE asset.latest_inventory;

CREATE VIEW asset.latest_inventory (id, inventory_workstation, inventory_date, copy) AS
SELECT DISTINCT ON (copy) id, inventory_workstation, inventory_date, copy
FROM asset.copy_inventory
ORDER BY copy, inventory_date DESC;

DROP FUNCTION evergreen.asset_latest_inventory_copy_inh_fkey();

COMMIT;
