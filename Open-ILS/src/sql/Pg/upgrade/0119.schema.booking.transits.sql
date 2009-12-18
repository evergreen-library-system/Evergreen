BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0119'); -- miker

CREATE TABLE action.reservation_transit_copy (
    reservation    INT REFERENCES booking.reservation (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
) INHERITS (action.transit_copy);
ALTER TABLE action.reservation_transit_copy ADD PRIMARY KEY (id);
ALTER TABLE action.reservation_transit_copy ADD CONSTRAINT artc_tc_fkey FOREIGN KEY (target_copy) REFERENCES booking.resource (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
CREATE INDEX active_reservation_transit_dest_idx ON "action".reservation_transit_copy (dest);
CREATE INDEX active_reservation_transit_source_idx ON "action".reservation_transit_copy (source);
CREATE INDEX active_reservation_transit_cp_idx ON "action".reservation_transit_copy (target_copy);

COMMIT;

