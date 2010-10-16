/*
 * Copyright (C) 2010 Laurentian University
 * Dan Scott <dscott@laurentian.ca>
 * Copyright (C) 2010  Equinox Software, Inc.
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

CREATE TABLE actor.usr_password_reset (
  id SERIAL PRIMARY KEY,
  uuid TEXT NOT NULL, 
  usr BIGINT NOT NULL REFERENCES actor.usr(id) DEFERRABLE INITIALLY DEFERRED, 
  request_time TIMESTAMP NOT NULL DEFAULT NOW(), 
  has_been_reset BOOL NOT NULL DEFAULT false
);
COMMENT ON TABLE actor.usr_password_reset IS $$
/*
 * Copyright (C) 2010 Laurentian University
 * Dan Scott <dscott@laurentian.ca>
 *
 * Self-serve password reset requests
 *
 * ****
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
 */
$$;
CREATE UNIQUE INDEX actor_usr_password_reset_uuid_idx ON actor.usr_password_reset (uuid);
CREATE INDEX actor_usr_password_reset_usr_idx ON actor.usr_password_reset (usr);
CREATE INDEX actor_usr_password_reset_request_time_idx ON actor.usr_password_reset (request_time);
CREATE INDEX actor_usr_password_reset_has_been_reset_idx ON actor.usr_password_reset (has_been_reset);

INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('password.reset_request','aupr','Patron has requested a self-serve password reset');
INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, template) 
    VALUES (NEXTVAL('action_trigger.event_definition_id_seq'), 'f', 1, 'Password reset request notification', 'password.reset_request', 'NOOP_True', 'SendEmail', '00:00:01',
$$
[%- USE date -%]
[%- user = target.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || user.home_ou.email || default_sender %]
Subject: [% user.home_ou.name %]: library account password reset request

You have received this message because you, or somebody else, requested a reset
of your library system password. If you did not request a reset of your library
system password, just ignore this message and your current password will
continue to work.

If you did request a reset of your library system password, please perform
the following steps to continue the process of resetting your password:

1. Open the following link in a web browser: https://[% params.hostname %]/opac/password/[% params.locale || 'en-US' %]/[% target.uuid %]
The browser displays a password reset form.

2. Enter your new password in the password reset form in the browser. You must
enter the password twice to ensure that you do not make a mistake. If the
passwords match, you will then be able to log in to your library system account
with the new password.

$$);
INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( CURRVAL('action_trigger.event_definition_id_seq'), 'usr' );
INSERT INTO action_trigger.environment ( event_def, path) VALUES
    ( CURRVAL('action_trigger.event_definition_id_seq'), 'usr.home_ou' );

-- Column telling us when the item hit the holds shelf
ALTER TABLE action.hold_request ADD COLUMN shelf_time TIMESTAMP WITH TIME ZONE;

-- Booking schema
CREATE SCHEMA booking;

CREATE TABLE booking.resource_type (
	id             SERIAL          PRIMARY KEY,
	name           TEXT            NOT NULL,
	elbow_room     INTERVAL,
	fine_interval  INTERVAL,
	fine_amount    DECIMAL(8,2)    NOT NULL DEFAULT 0,
	max_fine       DECIMAL(8,2),
	owner          INT             NOT NULL
	                               REFERENCES actor.org_unit( id )
	                               DEFERRABLE INITIALLY DEFERRED,
	catalog_item   BOOLEAN         NOT NULL DEFAULT FALSE,
	transferable   BOOLEAN         NOT NULL DEFAULT FALSE,
    record         INT             REFERENCES biblio.record_entry (id)
                                   DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT brt_name_once_per_owner UNIQUE(owner, name, record)
);

CREATE TABLE booking.resource (
	id             SERIAL           PRIMARY KEY,
	owner          INT              NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	type           INT              NOT NULL
	                                REFERENCES booking.resource_type(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	overbook       BOOLEAN          NOT NULL DEFAULT FALSE,
	barcode        TEXT             NOT NULL,
	deposit        BOOLEAN          NOT NULL DEFAULT FALSE,
	deposit_amount DECIMAL(8,2)     NOT NULL DEFAULT 0.00,
	user_fee       DECIMAL(8,2)     NOT NULL DEFAULT 0.00,
	CONSTRAINT br_unique UNIQUE(owner, barcode)
);

-- For non-catalog items: hijack barcode for name/description

CREATE TABLE booking.resource_attr (
	id              SERIAL          PRIMARY KEY,
	owner           INT             NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	name            TEXT            NOT NULL,
	resource_type   INT             NOT NULL
	                                REFERENCES booking.resource_type(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	required        BOOLEAN         NOT NULL DEFAULT FALSE,
	CONSTRAINT bra_name_once_per_type UNIQUE(resource_type, name)
);

CREATE TABLE booking.resource_attr_value (
	id               SERIAL         PRIMARY KEY,
	owner            INT            NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	attr             INT            NOT NULL
	                                REFERENCES booking.resource_attr(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	valid_value      TEXT           NOT NULL,
	CONSTRAINT brav_logical_key UNIQUE(owner, attr, valid_value)
);

-- Do we still need a name column?


CREATE TABLE booking.resource_attr_map (
	id               SERIAL         PRIMARY KEY,
	resource         INT            NOT NULL
	                                REFERENCES booking.resource(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	resource_attr    INT            NOT NULL
	                                REFERENCES booking.resource_attr(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	value            INT            NOT NULL
	                                REFERENCES booking.resource_attr_value(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT bram_one_value_per_attr UNIQUE(resource, resource_attr)
);

CREATE TABLE booking.reservation (
	request_time     TIMESTAMPTZ   NOT NULL DEFAULT now(),
	start_time       TIMESTAMPTZ,
	end_time         TIMESTAMPTZ,
	capture_time     TIMESTAMPTZ,
	cancel_time      TIMESTAMPTZ,
	pickup_time      TIMESTAMPTZ,
	return_time      TIMESTAMPTZ,
	booking_interval INTERVAL,
	fine_interval    INTERVAL,
	fine_amount      DECIMAL(8,2),
	max_fine         DECIMAL(8,2),
	target_resource_type  INT       NOT NULL
	                                REFERENCES booking.resource_type(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	target_resource  INT            REFERENCES booking.resource(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	current_resource INT            REFERENCES booking.resource(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	request_lib      INT            NOT NULL
	                                REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	pickup_lib       INT            REFERENCES actor.org_unit(id)
	                                DEFERRABLE INITIALLY DEFERRED,
	capture_staff    INT            REFERENCES actor.usr(id)
	                                DEFERRABLE INITIALLY DEFERRED
) INHERITS (money.billable_xact);

ALTER TABLE booking.reservation ADD PRIMARY KEY (id);

ALTER TABLE booking.reservation
	ADD CONSTRAINT booking_reservation_usr_fkey
	FOREIGN KEY (usr) REFERENCES actor.usr (id)
	DEFERRABLE INITIALLY DEFERRED;

CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON booking.reservation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('reservation');
CREATE TRIGGER mat_summary_change_tgr AFTER UPDATE ON booking.reservation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_update ();
CREATE TRIGGER mat_summary_remove_tgr AFTER DELETE ON booking.reservation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_delete ();


CREATE TABLE booking.reservation_attr_value_map (
	id               SERIAL         PRIMARY KEY,
	reservation      INT            NOT NULL
	                                REFERENCES booking.reservation(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	attr_value       INT            NOT NULL
	                                REFERENCES booking.resource_attr_value(id)
	                                ON DELETE CASCADE
	                                DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT bravm_logical_key UNIQUE(reservation, attr_value)
);

CREATE TABLE action.reservation_transit_copy (
    reservation    INT REFERENCES booking.reservation (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
) INHERITS (action.transit_copy);
ALTER TABLE action.reservation_transit_copy ADD PRIMARY KEY (id);
ALTER TABLE action.reservation_transit_copy ADD CONSTRAINT artc_tc_fkey FOREIGN KEY (target_copy) REFERENCES booking.resource (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
CREATE INDEX active_reservation_transit_dest_idx ON "action".reservation_transit_copy (dest);
CREATE INDEX active_reservation_transit_source_idx ON "action".reservation_transit_copy (source);
CREATE INDEX active_reservation_transit_cp_idx ON "action".reservation_transit_copy (target_copy);



-- Add booking to penalty calc
CREATE OR REPLACE FUNCTION actor.calculate_system_penalties( match_user INT, context_org INT ) RETURNS SETOF actor.usr_standing_penalty AS $func$
DECLARE
    user_object         actor.usr%ROWTYPE;
    new_sp_row          actor.usr_standing_penalty%ROWTYPE;
    existing_sp_row     actor.usr_standing_penalty%ROWTYPE;
    collections_fines   permission.grp_penalty_threshold%ROWTYPE;
    max_fines           permission.grp_penalty_threshold%ROWTYPE;
    max_overdue         permission.grp_penalty_threshold%ROWTYPE;
    max_items_out       permission.grp_penalty_threshold%ROWTYPE;
    tmp_grp             INT;
    items_overdue       INT;
    items_out           INT;
    context_org_list    INT[];
    current_fines        NUMERIC(8,2) := 0.0;
    tmp_fines            NUMERIC(8,2);
    tmp_groc            RECORD;
    tmp_circ            RECORD;
    tmp_org             actor.org_unit%ROWTYPE;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;

    -- Max fines
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a high fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 1 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_fines.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 1
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (r.pickup_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (g.billing_location = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (circ.circ_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 1;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max overdue
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many overdue items
    LOOP
        tmp_grp := user_object.profile;
        LOOP

            SELECT * INTO max_overdue FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 2 AND org_unit = tmp_org.id;

            IF max_overdue.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_overdue.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_overdue.threshold IS NOT NULL THEN

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_overdue.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 2
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  INTO items_overdue COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_overdue.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
            AND circ.checkin_time IS NULL
            AND circ.due_date < NOW()
            AND (circ.stop_fines = 'MAXFINES' OR circ.stop_fines IS NULL);

        IF items_overdue >= max_overdue.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_overdue.org_unit;
            new_sp_row.standing_penalty := 2;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;

    -- Start over for max out
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has too many checked out items
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_items_out FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 3 AND org_unit = tmp_org.id;

            IF max_items_out.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_items_out.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT INTO tmp_org * FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;


    -- Fail if the user has too many items checked out
    IF max_items_out.threshold IS NOT NULL THEN

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_items_out.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 3
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  INTO items_out COUNT(*)
          FROM  action.circulation circ
                JOIN  actor.org_unit_full_path( max_items_out.org_unit ) fp ON (circ.circ_lib = fp.id)
          WHERE circ.usr = match_user
                AND circ.checkin_time IS NULL
                AND (circ.stop_fines IN ('MAXFINES','LONGOVERDUE') OR circ.stop_fines IS NULL);

           IF items_out >= max_items_out.threshold::INT THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_items_out.org_unit;
            new_sp_row.standing_penalty := 3;
            RETURN NEXT new_sp_row;
           END IF;
    END IF;

    -- Start over for collections warning
    SELECT INTO tmp_org * FROM actor.org_unit WHERE id = context_org;

    -- Fail if the user has a collections-level fine balance
    LOOP
        tmp_grp := user_object.profile;
        LOOP
            SELECT * INTO max_fines FROM permission.grp_penalty_threshold WHERE grp = tmp_grp AND penalty = 4 AND org_unit = tmp_org.id;

            IF max_fines.threshold IS NULL THEN
                SELECT parent INTO tmp_grp FROM permission.grp_tree WHERE id = tmp_grp;
            ELSE
                EXIT;
            END IF;

            IF tmp_grp IS NULL THEN
                EXIT;
            END IF;
        END LOOP;

        IF max_fines.threshold IS NOT NULL OR tmp_org.parent_ou IS NULL THEN
            EXIT;
        END IF;

        SELECT * INTO tmp_org FROM actor.org_unit WHERE id = tmp_org.parent_ou;

    END LOOP;

    IF max_fines.threshold IS NOT NULL THEN

        FOR existing_sp_row IN
                SELECT  *
                  FROM  actor.usr_standing_penalty
                  WHERE usr = match_user
                        AND org_unit = max_fines.org_unit
                        AND (stop_date IS NULL or stop_date > NOW())
                        AND standing_penalty = 4
                LOOP
            RETURN NEXT existing_sp_row;
        END LOOP;

        SELECT  SUM(f.balance_owed) INTO current_fines
          FROM  money.materialized_billable_xact_summary f
                JOIN (
                    SELECT  r.id
                      FROM  booking.reservation r
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (r.pickup_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  g.id
                      FROM  money.grocery g
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (g.billing_location = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL
                                UNION ALL
                    SELECT  circ.id
                      FROM  action.circulation circ
                            JOIN  actor.org_unit_full_path( max_fines.org_unit ) fp ON (circ.circ_lib = fp.id)
                      WHERE usr = match_user
                            AND xact_finish IS NULL ) l USING (id);

        IF current_fines >= max_fines.threshold THEN
            new_sp_row.usr := match_user;
            new_sp_row.org_unit := max_fines.org_unit;
            new_sp_row.standing_penalty := 4;
            RETURN NEXT new_sp_row;
        END IF;
    END IF;


    RETURN;
END;
$func$ LANGUAGE plpgsql;

-- ACQ schema cleanup ... will probably end up being dropped entirely when 2.0 arrives, but...
ALTER TABLE acq.provider DROP CONSTRAINT provider_code_key;
ALTER TABLE acq.provider ALTER COLUMN code SET NOT NULL;
ALTER TABLE acq.provider ADD CONSTRAINT code_once_per_owner UNIQUE (code, owner);

ALTER TABLE acq.fund DROP CONSTRAINT fund_code_key;
ALTER TABLE acq.fund ADD CONSTRAINT code_once_per_org_year UNIQUE (org, code, year);

ALTER TABLE acq.purchase_order ADD COLUMN order_date TIMESTAMP WITH TIME ZONE;
ALTER TABLE acq.purchase_order ADD COLUMN name TEXT NOT NULL;

CREATE INDEX acq_po_org_name_order_date_idx ON acq.purchase_order( ordering_agency, name, order_date );

-- The name should default to the id, as text.  We can't reference a column
-- in a DEFAULT clause, so we use a trigger:

CREATE OR REPLACE FUNCTION acq.purchase_order_name_default () RETURNS TRIGGER 
AS $$
BEGIN
   IF NEW.name IS NULL THEN
       NEW.name := NEW.id::TEXT;
   END IF;

   RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER po_name_default_trg
  BEFORE INSERT OR UPDATE ON acq.purchase_order
  FOR EACH ROW EXECUTE PROCEDURE acq.purchase_order_name_default ();

-- The order name should be unique for a given ordering agency on a given order date
-- (truncated to midnight), but only where the order_date is not NULL.  Conceptually
-- this rule requires a check constraint with a subquery.  However you can't have a
-- subquery in a CHECK constraint, so we fake it with a trigger.

CREATE OR REPLACE FUNCTION acq.po_org_name_date_unique () RETURNS TRIGGER 
AS $$
DECLARE
   collision INT;
BEGIN
   --
   -- If order_date is not null, then make sure we don't have a collision
   -- on order_date (truncated to day), org, and name
   --
   IF NEW.order_date IS NULL THEN
       RETURN NEW;
   END IF;
   --
   -- In the WHERE clause, we compare the order_dates without regard to time of day.
   -- We use a pair of inequalities instead of comparing truncated dates so that the
   -- query can do an indexed range scan.
   --
   SELECT 1 INTO collision
   FROM acq.purchase_order
   WHERE
       ordering_agency = NEW.ordering_agency
       AND name = NEW.name
       AND order_date >= date_trunc( 'day', NEW.order_date )
       AND order_date <  date_trunc( 'day', NEW.order_date ) + '1 day'::INTERVAL
       AND id <> NEW.id;
   --
   IF collision IS NULL THEN
       -- okay, no collision
       RETURN NEW;
   ELSE
       -- collision; nip it in the bud
       RAISE EXCEPTION 'Colliding purchase orders: ordering_agency %, date %, name ''%''',
           NEW.ordering_agency, NEW.order_date, NEW.name;
   END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER po_org_name_date_unique_trg
  BEFORE INSERT OR UPDATE ON acq.purchase_order
  FOR EACH ROW EXECUTE PROCEDURE acq.po_org_name_date_unique ();

CREATE TABLE acq.fiscal_calendar (
   id              SERIAL         PRIMARY KEY,
   name            TEXT           NOT NULL
);

CREATE TABLE acq.fiscal_year (
   id              SERIAL         PRIMARY KEY,
   calendar        INT            NOT NULL
                                  REFERENCES acq.fiscal_calendar
                                  ON DELETE CASCADE
                                  DEFERRABLE INITIALLY DEFERRED,
   year            INT            NOT NULL,
   year_begin      TIMESTAMPTZ    NOT NULL,
   year_end        TIMESTAMPTZ    NOT NULL,
   CONSTRAINT acq_fy_logical_key  UNIQUE ( calendar, year ),
    CONSTRAINT acq_fy_physical_key UNIQUE ( calendar, year_begin )
);

CREATE OR REPLACE FUNCTION acq.find_bad_fy()
/*
   Examine the acq.fiscal_year table, comparing successive years.
   Report any inconsistencies, i.e. years that overlap, have gaps
    between them, or are out of sequence.
*/
RETURNS SETOF RECORD AS $$
DECLARE
   first_row  BOOLEAN;
   curr_year  RECORD;
   prev_year  RECORD;
   return_rec RECORD;
BEGIN
   first_row := true;
   FOR curr_year in
       SELECT
           id,
           calendar,
           year,
           year_begin,
           year_end
       FROM
           acq.fiscal_year
       ORDER BY
           calendar,
           year_begin
   LOOP
       --
       IF first_row THEN
           first_row := FALSE;
       ELSIF curr_year.calendar    = prev_year.calendar THEN
           IF curr_year.year_begin > prev_year.year_end THEN
               -- This ugly kludge works around the fact that older
               -- versions of PostgreSQL don't support RETURN QUERY SELECT
               FOR return_rec IN SELECT
                   prev_year.id,
                   prev_year.year,
                   'Gap between fiscal years'::TEXT
               LOOP
                   RETURN NEXT return_rec;
               END LOOP;
           ELSIF curr_year.year_begin < prev_year.year_end THEN
               FOR return_rec IN SELECT
                   prev_year.id,
                   prev_year.year,
                   'Overlapping fiscal years'::TEXT
               LOOP
                   RETURN NEXT return_rec;
               END LOOP;
           ELSIF curr_year.year < prev_year.year THEN
               FOR return_rec IN SELECT
                   prev_year.id,
                   prev_year.year,
                   'Fiscal years out of order'::TEXT
               LOOP
                   RETURN NEXT return_rec;
               END LOOP;
           END IF;
       END IF;
       --
       prev_year := curr_year;
   END LOOP;
   --
   RETURN;
END;
$$ LANGUAGE plpgsql;

-- More booking related updates
CREATE OR REPLACE VIEW money.open_billable_xact_summary AS
    SELECT  xact.id AS id,
        xact.usr AS usr,
        COALESCE(circ.circ_lib,groc.billing_location,res.pickup_lib) AS billing_location,
        xact.xact_start AS xact_start,
        xact.xact_finish AS xact_finish,
        SUM(credit.amount) AS total_paid,
        MAX(credit.payment_ts) AS last_payment_ts,
        LAST(credit.note) AS last_payment_note,
        LAST(credit.payment_type) AS last_payment_type,
        SUM(debit.amount) AS total_owed,
        MAX(debit.billing_ts) AS last_billing_ts,
        LAST(debit.note) AS last_billing_note,
        LAST(debit.billing_type) AS last_billing_type,
        COALESCE(SUM(debit.amount),0) - COALESCE(SUM(credit.amount),0) AS balance_owed,
        p.relname AS xact_type
      FROM  money.billable_xact xact
        JOIN pg_class p ON (xact.tableoid = p.oid)
        LEFT JOIN "action".circulation circ ON (circ.id = xact.id)
        LEFT JOIN money.grocery groc ON (groc.id = xact.id)
        LEFT JOIN booking.reservation res ON (groc.id = xact.id)
        LEFT JOIN (
            SELECT  billing.xact,
                billing.voided,
                sum(billing.amount) AS amount,
                max(billing.billing_ts) AS billing_ts,
                last(billing.note) AS note,
                last(billing.billing_type) AS billing_type
              FROM  money.billing
              WHERE billing.voided IS FALSE
              GROUP BY billing.xact, billing.voided
        ) debit ON (xact.id = debit.xact AND debit.voided IS FALSE)
        LEFT JOIN (
            SELECT  payment_view.xact,
                payment_view.voided,
                sum(payment_view.amount) AS amount,
                max(payment_view.payment_ts) AS payment_ts,
                last(payment_view.note) AS note,
                last(payment_view.payment_type) AS payment_type
              FROM  money.payment_view
              WHERE payment_view.voided IS FALSE
              GROUP BY payment_view.xact, payment_view.voided
        ) credit ON (xact.id = credit.xact AND credit.voided IS FALSE)
      WHERE xact.xact_finish IS NULL
      GROUP BY 1,2,3,4,5,15
      ORDER BY MAX(debit.billing_ts), MAX(credit.payment_ts);

COMMIT;

INSERT INTO config.copy_status (id,name) VALUES (15,oils_i18n_gettext(15, 'On reservation shelf', 'ccs', 'name'));

-- In booking, elbow room defines:
--  a) how far in the future you must make a reservation on a given item if
--      that item will have to transit somewhere to fulfill the reservation.
--  b) how soon a reservation must be starting for the reserved item to
--      be op-captured by the checkin interface.
INSERT INTO actor.org_unit_setting (org_unit, name, value) VALUES (
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    'circ.booking_reservation.default_elbow_room',
    '"1 day"'
);

-- Put the sequence back inside the protected range
SELECT SETVAL('permission.perm_list_id_seq'::TEXT, (SELECT MAX(id) FROM permission.perm_list WHERE id < 1000));

INSERT INTO permission.perm_list (code, description) VALUES ('HOLD_LOCAL_AVAIL_OVERRIDE', 'Allow a user to place a hold despite the availability of a local copy');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_BOOKING_RESOURCE', 'Enables the user to create/update/delete booking resources');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_BOOKING_RESOURCE_TYPE', 'Enables the user to create/update/delete booking resource types');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_BOOKING_RESOURCE_ATTR', 'Enables the user to create/update/delete booking resource attributes');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_BOOKING_RESOURCE_ATTR_MAP', 'Enables the user to create/update/delete booking resource attribute maps');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_BOOKING_RESOURCE_ATTR_VALUE', 'Enables the user to create/update/delete booking resource attribute values');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_BOOKING_RESERVATION', 'Enables the user to create/update/delete booking reservations');
INSERT INTO permission.perm_list (code, description) VALUES ('ADMIN_BOOKING_RESERVATION_ATTR_VALUE_MAP', 'Enables the user to create/update/delete booking reservation attribute value maps');
INSERT INTO permission.perm_list (code, description) VALUES ('HOLD_ITEM_CHECKED_OUT.override', 'Allows a user to place a hold on an item that they already have checked out');
INSERT INTO permission.perm_list (code, description) VALUES ('RETRIEVE_RESERVATION_PULL_LIST', 'Allows a user to retrieve a booking reservation pull list');
INSERT INTO permission.perm_list (code, description) VALUES ('CAPTURE_RESERVATION', 'Allows a user to capture booking reservations');

-- and now, move it back out
CREATE FUNCTION bigger (INT,INT) RETURNS INT AS $$ SELECT CASE WHEN $1 > $2 THEN $1 ELSE $2 END; $$ LANGUAGE SQL;
SELECT SETVAL('permission.perm_list_id_seq'::TEXT, bigger((SELECT MAX(id) FROM permission.perm_list),1000));
DROP FUNCTION bigger (INT,INT);

-- Pinned via 1.6.0 insert
UPDATE action_trigger.event_definition SET delay_field = 'shelf_time' WHERE id = 5;

CREATE OR REPLACE VIEW reporter.old_super_simple_record AS
SELECT  r.id,
    r.fingerprint,
    r.quality,
    r.tcn_source,
    r.tcn_value,
    FIRST(title.value) AS title,
    FIRST(author.value) AS author,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT publisher.value), ', ') AS publisher,
    ARRAY_TO_STRING(ARRAY_ACCUM( DISTINCT SUBSTRING(pubdate.value FROM $$\d+$$) ), ', ') AS pubdate,
    ARRAY_ACCUM( DISTINCT SUBSTRING(isbn.value FROM $$^\S+$$) ) AS isbn,
    ARRAY_ACCUM( DISTINCT SUBSTRING(issn.value FROM $$^\S+$$) ) AS issn
  FROM  biblio.record_entry r
    LEFT JOIN metabib.full_rec title ON (r.id = title.record AND title.tag = '245' AND title.subfield = 'a')
    LEFT JOIN metabib.full_rec author ON (r.id = author.record AND author.tag IN ('100','110','111') AND author.subfield = 'a')
    LEFT JOIN metabib.full_rec publisher ON (r.id = publisher.record AND publisher.tag = '260' AND publisher.subfield = 'b')
    LEFT JOIN metabib.full_rec pubdate ON (r.id = pubdate.record AND pubdate.tag = '260' AND pubdate.subfield = 'c')
    LEFT JOIN metabib.full_rec isbn ON (r.id = isbn.record AND isbn.tag IN ('024', '020') AND isbn.subfield IN ('a','z'))
    LEFT JOIN metabib.full_rec issn ON (r.id = issn.record AND issn.tag = '022' AND issn.subfield = 'a')
  GROUP BY 1,2,3,4,5;




