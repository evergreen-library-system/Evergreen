/*
 * Copyright (C) 2009  Equinox Software, Inc.
 * Scott McKellar <scott@esilibrary.com>
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

DROP SCHEMA IF EXISTS booking CASCADE;

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
    record         BIGINT          REFERENCES biblio.record_entry (id)
                                   DEFERRABLE INITIALLY DEFERRED,
	CONSTRAINT brt_name_and_record_once_per_owner UNIQUE(owner, name, record)
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
	                                DEFERRABLE INITIALLY DEFERRED,
	email_notify     BOOLEAN        NOT NULL DEFAULT FALSE,
	note             TEXT
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

CREATE CONSTRAINT TRIGGER reservation_transit_copy_is_unique_check
    AFTER INSERT ON action.reservation_transit_copy
    FOR EACH ROW EXECUTE PROCEDURE action.copy_transit_is_unique();

COMMIT;
