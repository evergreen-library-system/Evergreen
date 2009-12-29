
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0126'); -- miker

CREATE OR REPLACE VIEW money.billable_xact_summary_location_view AS
    SELECT  m.*, COALESCE(c.circ_lib, g.billing_location, r.pickup_lib) AS billing_location
      FROM  money.materialized_billable_xact_summary m
            LEFT JOIN action.circulation c ON (c.id = m.id)
            LEFT JOIN money.grocery g ON (g.id = m.id)
            LEFT JOIN booking.reservation r ON (r.id = m.id);

COMMIT;

