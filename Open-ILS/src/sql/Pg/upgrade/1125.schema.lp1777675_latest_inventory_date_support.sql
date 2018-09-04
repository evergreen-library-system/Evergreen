BEGIN;

SELECT evergreen.upgrade_deps_block_check('1125', :eg_version);

CREATE TABLE asset.latest_inventory (
    id                          SERIAL                      PRIMARY KEY,
    inventory_workstation       INTEGER                     REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,
    inventory_date              TIMESTAMP WITH TIME ZONE    DEFAULT NOW(),
    copy                        BIGINT                      NOT NULL
);
CREATE INDEX latest_inventory_copy_idx ON asset.latest_inventory (copy);

CREATE OR REPLACE FUNCTION evergreen.asset_latest_inventory_copy_inh_fkey() RETURNS TRIGGER AS $f$
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

CREATE CONSTRAINT TRIGGER inherit_asset_latest_inventory_copy_fkey
        AFTER UPDATE OR INSERT ON asset.latest_inventory
        DEFERRABLE FOR EACH ROW EXECUTE PROCEDURE evergreen.asset_latest_inventory_copy_inh_fkey();

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.circ.checkin.do_inventory_update', 'circ', 'bool',
    oils_i18n_gettext (
             'eg.circ.checkin.do_inventory_update',
             'Checkin: Update Inventory',
             'cwst', 'label'
    )
);

COMMIT;
