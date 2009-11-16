BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0086');

DROP SCHEMA IF EXISTS booking CASCADE;

CREATE SCHEMA booking;

CREATE TABLE booking.resource_type (
	id             SERIAL          PRIMARY KEY,
	name           TEXT            NOT NULL,
	fine_interval  INTERVAL,
	fine_amount    DECIMAL(8,2)    NOT NULL DEFAULT 0,
	owner          INT             NOT NULL
	                               REFERENCES actor.org_unit( id )
	                               DEFERRABLE INITIALLY DEFERRED,
	catalog_item   BOOLEAN         NOT NULL DEFAULT FALSE,
	transferable   BOOLEAN         NOT NULL DEFAULT FALSE,
	CONSTRAINT brt_name_once_per_owner UNIQUE(owner, name)
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
	CONSTRAINT br_unique UNIQUE(owner, type, barcode)
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

COMMIT;
