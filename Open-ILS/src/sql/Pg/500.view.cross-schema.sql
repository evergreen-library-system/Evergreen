/*
 * Copyright (C) 2004-2008  Georgia Public Library Service
 * Copyright (C) 2007-2008  Equinox Software, Inc.
 * Mike Rylander <miker@esilibrary.com> 
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

BEGIN;


CREATE OR REPLACE VIEW money.billable_xact_summary_location_view AS
    SELECT  m.*, COALESCE(c.circ_lib, g.billing_location, r.pickup_lib) AS billing_location
      FROM  money.materialized_billable_xact_summary m
            LEFT JOIN action.circulation c ON (c.id = m.id)
            LEFT JOIN money.grocery g ON (g.id = m.id)
            LEFT JOIN booking.reservation r ON (r.id = m.id);

CREATE OR REPLACE VIEW money.open_billable_xact_summary AS 
    SELECT * FROM money.billable_xact_summary_location_view
    WHERE xact_finish IS NULL;

CREATE OR REPLACE VIEW money.open_usr_summary AS
    SELECT 
        usr, 
        sum(total_paid) AS total_paid, 
        sum(total_owed) AS total_owed, 
        sum(balance_owed) AS balance_owed
    FROM money.materialized_billable_xact_summary
    WHERE xact_finish IS NULL
    GROUP BY usr;

CREATE OR REPLACE VIEW money.open_usr_circulation_summary AS
    SELECT 
        usr,
        SUM(total_paid) AS total_paid,
        SUM(total_owed) AS total_owed,
        SUM(balance_owed) AS balance_owed
    FROM  money.materialized_billable_xact_summary
    WHERE xact_type = 'circulation' AND xact_finish IS NULL
    GROUP BY usr;


-- Not a view, but it's cross-schema..
CREATE TABLE config.idl_field_doc (
    id              BIGSERIAL   PRIMARY KEY,
    fm_class        TEXT        NOT NULL,
    field           TEXT        NOT NULL,
    owner           INT         NOT NULL    REFERENCES actor.org_unit (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    string          TEXT        NOT NULL
);
CREATE UNIQUE INDEX idl_field_doc_identity ON config.idl_field_doc (fm_class,field,owner);


COMMIT;

