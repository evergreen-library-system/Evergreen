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

DROP SCHEMA IF EXISTS action CASCADE;

BEGIN;

CREATE SCHEMA action;

CREATE TABLE action.in_house_use (
	id		SERIAL				PRIMARY KEY,
	item		BIGINT				NOT NULL, -- REFERENCES asset.copy (id) DEFERRABLE INITIALLY DEFERRED, -- XXX could be an serial.issuance
	staff		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	org_unit	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	use_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX action_in_house_use_staff_idx      ON action.in_house_use ( staff );

CREATE TABLE action.non_cataloged_circulation (
	id		SERIAL				PRIMARY KEY,
	patron		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	staff		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	circ_lib	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	item_type	INT				NOT NULL REFERENCES config.non_cataloged_type (id) DEFERRABLE INITIALLY DEFERRED,
	circ_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX action_non_cat_circ_patron_idx ON action.non_cataloged_circulation ( patron );
CREATE INDEX action_non_cat_circ_staff_idx  ON action.non_cataloged_circulation ( staff );

CREATE TABLE action.non_cat_in_house_use (
	id		SERIAL				PRIMARY KEY,
	item_type	BIGINT				NOT NULL REFERENCES config.non_cataloged_type(id) DEFERRABLE INITIALLY DEFERRED,
	staff		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	org_unit	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	use_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX non_cat_in_house_use_staff_idx ON action.non_cat_in_house_use ( staff );

CREATE TABLE action.survey (
	id		SERIAL				PRIMARY KEY,
	owner		INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	start_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	end_date	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW() + '10 years'::INTERVAL,
	usr_summary	BOOL				NOT NULL DEFAULT FALSE,
	opac		BOOL				NOT NULL DEFAULT FALSE,
	poll		BOOL				NOT NULL DEFAULT FALSE,
	required	BOOL				NOT NULL DEFAULT FALSE,
	name		TEXT				NOT NULL,
	description	TEXT				NOT NULL
);
CREATE UNIQUE INDEX asv_once_per_owner_idx ON action.survey (owner,name);

CREATE TABLE action.survey_question (
	id		SERIAL	PRIMARY KEY,
	survey		INT	NOT NULL REFERENCES action.survey DEFERRABLE INITIALLY DEFERRED,
	question	TEXT	NOT NULL
);

CREATE TABLE action.survey_answer (
	id		SERIAL	PRIMARY KEY,
	question	INT	NOT NULL REFERENCES action.survey_question DEFERRABLE INITIALLY DEFERRED,
	answer		TEXT	NOT NULL
);

CREATE SEQUENCE action.survey_response_group_id_seq;

CREATE TABLE action.survey_response (
	id			BIGSERIAL			PRIMARY KEY,
	response_group_id	INT,
	usr			INT, -- REFERENCES actor.usr
	survey			INT				NOT NULL REFERENCES action.survey DEFERRABLE INITIALLY DEFERRED,
	question		INT				NOT NULL REFERENCES action.survey_question DEFERRABLE INITIALLY DEFERRED,
	answer			INT				NOT NULL REFERENCES action.survey_answer DEFERRABLE INITIALLY DEFERRED,
	answer_date		TIMESTAMP WITH TIME ZONE,
	effective_date		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX action_survey_response_usr_idx ON action.survey_response ( usr );

CREATE OR REPLACE FUNCTION action.survey_response_answer_date_fixup () RETURNS TRIGGER AS '
BEGIN
	NEW.answer_date := NOW();
	RETURN NEW;
END;
' LANGUAGE 'plpgsql';
CREATE TRIGGER action_survey_response_answer_date_fixup_tgr
	BEFORE INSERT ON action.survey_response
	FOR EACH ROW
	EXECUTE PROCEDURE action.survey_response_answer_date_fixup ();

CREATE TABLE action.archive_actor_stat_cat (
    id          BIGSERIAL   PRIMARY KEY,
    xact        BIGINT      NOT NULL, -- action.circulation (+aged/all)
    stat_cat    INT         NOT NULL,
    value       TEXT        NOT NULL
);

CREATE TABLE action.archive_asset_stat_cat (
    id          BIGSERIAL   PRIMARY KEY,
    xact        BIGINT      NOT NULL, -- action.circulation (+aged/all)
    stat_cat    INT         NOT NULL,
    value       TEXT        NOT NULL
);


CREATE TABLE action.circulation (
	target_copy		BIGINT				NOT NULL, -- asset.copy.id
	circ_lib		INT				NOT NULL, -- actor.org_unit.id
	circ_staff		INT				NOT NULL, -- actor.usr.id
	checkin_staff		INT,					  -- actor.usr.id
	checkin_lib		INT,					  -- actor.org_unit.id
	renewal_remaining	INT				NOT NULL, -- derived from "circ duration" rule
    grace_period           INTERVAL             NOT NULL, -- derived from "circ fine" rule
	due_date		TIMESTAMP WITH TIME ZONE,
	stop_fines_time		TIMESTAMP WITH TIME ZONE,
	checkin_time		TIMESTAMP WITH TIME ZONE,
	create_time		TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
	duration		INTERVAL,				  -- derived from "circ duration" rule
	fine_interval		INTERVAL			NOT NULL DEFAULT '1 day'::INTERVAL, -- derived from "circ fine" rule
	recurring_fine		NUMERIC(6,2),				  -- derived from "circ fine" rule
	max_fine		NUMERIC(6,2),				  -- derived from "max fine" rule
	phone_renewal		BOOL				NOT NULL DEFAULT FALSE,
	desk_renewal		BOOL				NOT NULL DEFAULT FALSE,
	opac_renewal		BOOL				NOT NULL DEFAULT FALSE,
	duration_rule		TEXT				NOT NULL, -- name of "circ duration" rule
	recurring_fine_rule	TEXT				NOT NULL, -- name of "circ fine" rule
	max_fine_rule		TEXT				NOT NULL, -- name of "max fine" rule
	stop_fines		TEXT				CHECK (stop_fines IN (
	                                       'CHECKIN','CLAIMSRETURNED','LOST','MAXFINES','RENEW','LONGOVERDUE','CLAIMSNEVERCHECKEDOUT')),
	workstation         INT        REFERENCES actor.workstation(id)
	                               ON DELETE SET NULL
								   DEFERRABLE INITIALLY DEFERRED,
	checkin_workstation INT        REFERENCES actor.workstation(id)
	                               ON DELETE SET NULL
								   DEFERRABLE INITIALLY DEFERRED,
	copy_location	INT				NOT NULL DEFAULT 1 REFERENCES asset.copy_location (id) DEFERRABLE INITIALLY DEFERRED,
	checkin_scan_time   TIMESTAMP WITH TIME ZONE
) INHERITS (money.billable_xact);
ALTER TABLE action.circulation ADD PRIMARY KEY (id);
ALTER TABLE action.circulation
	ADD COLUMN parent_circ BIGINT
	REFERENCES action.circulation( id )
	DEFERRABLE INITIALLY DEFERRED;
CREATE INDEX circ_open_xacts_idx ON action.circulation (usr) WHERE xact_finish IS NULL;
CREATE INDEX circ_outstanding_idx ON action.circulation (usr) WHERE checkin_time IS NULL;
CREATE INDEX circ_checkin_time ON "action".circulation (checkin_time) WHERE checkin_time IS NOT NULL;
CREATE INDEX circ_circ_lib_idx ON "action".circulation (circ_lib);
CREATE INDEX circ_open_date_idx ON "action".circulation (xact_start) WHERE xact_finish IS NULL;
CREATE INDEX circ_all_usr_idx       ON action.circulation ( usr );
CREATE INDEX circ_circ_staff_idx    ON action.circulation ( circ_staff );
CREATE INDEX circ_checkin_staff_idx ON action.circulation ( checkin_staff );
CREATE INDEX action_circulation_target_copy_idx ON action.circulation (target_copy);
CREATE UNIQUE INDEX circ_parent_idx ON action.circulation ( parent_circ ) WHERE parent_circ IS NOT NULL;
CREATE UNIQUE INDEX only_one_concurrent_checkout_per_copy ON action.circulation(target_copy) WHERE checkin_time IS NULL;

CREATE TRIGGER action_circulation_target_copy_trig AFTER INSERT OR UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE evergreen.fake_fkey_tgr('target_copy');

CREATE TRIGGER mat_summary_create_tgr AFTER INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_create ('circulation');
CREATE TRIGGER mat_summary_change_tgr AFTER UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_update ();
CREATE TRIGGER mat_summary_remove_tgr AFTER DELETE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE money.mat_summary_delete ();

CREATE OR REPLACE FUNCTION action.push_circ_due_time () RETURNS TRIGGER AS $$
BEGIN
    IF (EXTRACT(EPOCH FROM NEW.duration)::INT % EXTRACT(EPOCH FROM '1 day'::INTERVAL)::INT) = 0 THEN
        NEW.due_date = (NEW.due_date::DATE + '1 day'::INTERVAL - '1 second'::INTERVAL)::TIMESTAMPTZ;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER push_due_date_tgr BEFORE INSERT OR UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.push_circ_due_time();

CREATE OR REPLACE FUNCTION action.fill_circ_copy_location () RETURNS TRIGGER AS $$
BEGIN
    SELECT INTO NEW.copy_location location FROM asset.copy WHERE id = NEW.target_copy;
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER fill_circ_copy_location_tgr BEFORE INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.fill_circ_copy_location();

CREATE OR REPLACE FUNCTION action.archive_stat_cats () RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO action.archive_actor_stat_cat(xact, stat_cat, value)
        SELECT NEW.id, asceum.stat_cat, asceum.stat_cat_entry
        FROM actor.stat_cat_entry_usr_map asceum
             JOIN actor.stat_cat sc ON asceum.stat_cat = sc.id
        WHERE NEW.usr = asceum.target_usr AND sc.checkout_archive;
    INSERT INTO action.archive_asset_stat_cat(xact, stat_cat, value)
        SELECT NEW.id, ascecm.stat_cat, asce.value
        FROM asset.stat_cat_entry_copy_map ascecm
             JOIN asset.stat_cat sc ON ascecm.stat_cat = sc.id
             JOIN asset.stat_cat_entry asce ON ascecm.stat_cat_entry = asce.id
        WHERE NEW.target_copy = ascecm.owning_copy AND sc.checkout_archive;
    RETURN NULL;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER archive_stat_cats_tgr AFTER INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.archive_stat_cats();

CREATE TABLE action.aged_circulation (
	usr_post_code		TEXT,
	usr_home_ou		INT	NOT NULL,
	usr_profile		INT	NOT NULL,
	usr_birth_year		INT,
	copy_call_number	INT	NOT NULL,
	copy_owning_lib		INT	NOT NULL,
	copy_circ_lib		INT	NOT NULL,
	copy_bib_record		BIGINT	NOT NULL,
	LIKE action.circulation

);
ALTER TABLE action.aged_circulation ADD PRIMARY KEY (id);
ALTER TABLE action.aged_circulation DROP COLUMN usr;
CREATE INDEX aged_circ_circ_lib_idx ON "action".aged_circulation (circ_lib);
CREATE INDEX aged_circ_start_idx ON "action".aged_circulation (xact_start);
CREATE INDEX aged_circ_copy_circ_lib_idx ON "action".aged_circulation (copy_circ_lib);
CREATE INDEX aged_circ_copy_owning_lib_idx ON "action".aged_circulation (copy_owning_lib);
CREATE INDEX aged_circ_copy_location_idx ON "action".aged_circulation (copy_location);
CREATE INDEX action_aged_circulation_target_copy_idx ON action.aged_circulation (target_copy);

CREATE OR REPLACE VIEW action.all_circulation AS
    SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
      FROM  action.aged_circulation
            UNION ALL
    SELECT  DISTINCT circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
        cp.call_number AS copy_call_number, circ.copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
        circ.checkin_lib, circ.renewal_remaining, circ.grace_period, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
        circ.recurring_fine_rule, circ.max_fine_rule, circ.stop_fines, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time,
        circ.parent_circ
      FROM  action.circulation circ
        JOIN asset.copy cp ON (circ.target_copy = cp.id)
        JOIN asset.call_number cn ON (cp.call_number = cn.id)
        JOIN actor.usr p ON (circ.usr = p.id)
        LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
        LEFT JOIN actor.usr_address b ON (p.billing_address = b.id);

CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
DECLARE
found char := 'N';
BEGIN

    -- If there are any renewals for this circulation, don't archive or delete
    -- it yet.   We'll do so later, when we archive and delete the renewals.

    SELECT 'Y' INTO found
    FROM action.circulation
    WHERE parent_circ = OLD.id
    LIMIT 1;

    IF found = 'Y' THEN
        RETURN NULL;  -- don't delete
	END IF;

    -- Archive a copy of the old row to action.aged_circulation

    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ
        FROM action.all_circulation WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER action_circulation_aging_tgr
	BEFORE DELETE ON action.circulation
	FOR EACH ROW
	EXECUTE PROCEDURE action.age_circ_on_delete ();


CREATE OR REPLACE FUNCTION action.age_parent_circ_on_delete () RETURNS TRIGGER AS $$
BEGIN

    -- Having deleted a renewal, we can delete the original circulation (or a previous
    -- renewal, if that's what parent_circ is pointing to).  That deletion will trigger
    -- deletion of any prior parents, etc. recursively.

    IF OLD.parent_circ IS NOT NULL THEN
        DELETE FROM action.circulation
        WHERE id = OLD.parent_circ;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER age_parent_circ
	AFTER DELETE ON action.circulation
	FOR EACH ROW
	EXECUTE PROCEDURE action.age_parent_circ_on_delete ();


CREATE OR REPLACE VIEW action.open_circulation AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	checkin_time IS NULL
	  ORDER BY due_date;
		

CREATE OR REPLACE VIEW action.billable_circulations AS
	SELECT	*
	  FROM	action.circulation
	  WHERE	xact_finish IS NULL;

CREATE OR REPLACE FUNCTION action.circulation_claims_returned () RETURNS TRIGGER AS $$
BEGIN
	IF OLD.stop_fines IS NULL OR OLD.stop_fines <> NEW.stop_fines THEN
		IF NEW.stop_fines = 'CLAIMSRETURNED' THEN
			UPDATE actor.usr SET claims_returned_count = claims_returned_count + 1 WHERE id = NEW.usr;
		END IF;
		IF NEW.stop_fines = 'CLAIMSNEVERCHECKEDOUT' THEN
			UPDATE actor.usr SET claims_never_checked_out_count = claims_never_checked_out_count + 1 WHERE id = NEW.usr;
		END IF;
		IF NEW.stop_fines = 'LOST' THEN
			UPDATE asset.copy SET status = 3 WHERE id = NEW.target_copy;
		END IF;
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';
CREATE TRIGGER action_circulation_stop_fines_tgr
	BEFORE UPDATE ON action.circulation
	FOR EACH ROW
	EXECUTE PROCEDURE action.circulation_claims_returned ();

CREATE TABLE action.hold_request_cancel_cause (
    id      SERIAL  PRIMARY KEY,
    label   TEXT    UNIQUE
);
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (1,'Untargeted expiration');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (2,'Hold Shelf expiration');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (3,'Patron via phone');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (4,'Patron in person');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (5,'Staff forced');
INSERT INTO action.hold_request_cancel_cause (id,label) VALUES (6,'Patron via OPAC');
SELECT SETVAL('action.hold_request_cancel_cause_id_seq', 100);

CREATE TABLE action.hold_request (
	id			SERIAL				PRIMARY KEY,
	request_time		TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	capture_time		TIMESTAMP WITH TIME ZONE,
	fulfillment_time	TIMESTAMP WITH TIME ZONE,
	checkin_time		TIMESTAMP WITH TIME ZONE,
	return_time		TIMESTAMP WITH TIME ZONE,
	prev_check_time		TIMESTAMP WITH TIME ZONE,
	expire_time		TIMESTAMP WITH TIME ZONE,
	cancel_time		TIMESTAMP WITH TIME ZONE,
	cancel_cause	INT REFERENCES action.hold_request_cancel_cause (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
	cancel_note		TEXT,
	target			BIGINT				NOT NULL, -- see hold_type
	current_copy		BIGINT,				-- REFERENCES asset.copy (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,  -- XXX could be an serial.unit now...
	fulfillment_staff	INT				REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	fulfillment_lib		INT				REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	request_lib		INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	requestor		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	usr			INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	selection_ou		INT				NOT NULL,
	selection_depth		INT				NOT NULL DEFAULT 0,
	pickup_lib		INT				NOT NULL REFERENCES actor.org_unit DEFERRABLE INITIALLY DEFERRED,
	hold_type		TEXT				NOT NULL, -- CHECK (hold_type IN ('M','T','V','C')),  -- XXX constraint too constraining...
	holdable_formats	TEXT,
	phone_notify		TEXT,
	email_notify		BOOL				NOT NULL DEFAULT FALSE,
	sms_notify		TEXT,
	sms_carrier		INT REFERENCES config.sms_carrier (id),
	frozen			BOOL				NOT NULL DEFAULT FALSE,
	thaw_date		TIMESTAMP WITH TIME ZONE,
	shelf_time		TIMESTAMP WITH TIME ZONE,
    cut_in_line     BOOL,
	mint_condition  BOOL NOT NULL DEFAULT TRUE,
	shelf_expire_time TIMESTAMPTZ,
	current_shelf_lib INT REFERENCES actor.org_unit DEFERRABLE INITIALLY DEFERRED
);
ALTER TABLE action.hold_request ADD CONSTRAINT sms_check CHECK (
    sms_notify IS NULL
    OR sms_carrier IS NOT NULL -- and implied sms_notify IS NOT NULL
);


CREATE INDEX hold_request_target_idx ON action.hold_request (target);
CREATE INDEX hold_request_usr_idx ON action.hold_request (usr);
CREATE INDEX hold_request_pickup_lib_idx ON action.hold_request (pickup_lib);
CREATE INDEX hold_request_current_copy_idx ON action.hold_request (current_copy);
CREATE INDEX hold_request_prev_check_time_idx ON action.hold_request (prev_check_time);
CREATE INDEX hold_request_fulfillment_staff_idx ON action.hold_request ( fulfillment_staff );
CREATE INDEX hold_request_requestor_idx         ON action.hold_request ( requestor );


CREATE TABLE action.hold_request_note (

    id     BIGSERIAL PRIMARY KEY,
    hold   BIGINT    NOT NULL REFERENCES action.hold_request (id)
                              ON DELETE CASCADE
                              DEFERRABLE INITIALLY DEFERRED,
    title  TEXT      NOT NULL,
    body   TEXT      NOT NULL,
    slip   BOOL      NOT NULL DEFAULT FALSE,
    pub    BOOL      NOT NULL DEFAULT FALSE,
    staff  BOOL      NOT NULL DEFAULT FALSE  -- created by staff

);
CREATE INDEX ahrn_hold_idx ON action.hold_request_note (hold);


CREATE TABLE action.hold_notification (
	id		SERIAL				PRIMARY KEY,
	hold		INT				NOT NULL REFERENCES action.hold_request (id)
									ON DELETE CASCADE
									DEFERRABLE INITIALLY DEFERRED,
	notify_staff	INT			REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	notify_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW(),
	method		TEXT				NOT NULL, -- email address or phone number
	note		TEXT
);
CREATE INDEX ahn_hold_idx ON action.hold_notification (hold);
CREATE INDEX ahn_notify_staff_idx ON action.hold_notification ( notify_staff );

CREATE TABLE action.hold_copy_map (
	id		BIGSERIAL	PRIMARY KEY,
	hold		INT	NOT NULL REFERENCES action.hold_request (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
	target_copy	BIGINT	NOT NULL, -- REFERENCES asset.copy (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED, -- XXX could be an serial.issuance
	CONSTRAINT copy_once_per_hold UNIQUE (hold,target_copy)
);
-- CREATE INDEX acm_hold_idx ON action.hold_copy_map (hold);
CREATE INDEX acm_copy_idx ON action.hold_copy_map (target_copy);

CREATE TABLE action.transit_copy (
	id			SERIAL				PRIMARY KEY,
	source_send_time	TIMESTAMP WITH TIME ZONE,
	dest_recv_time		TIMESTAMP WITH TIME ZONE,
	target_copy		BIGINT				NOT NULL, -- REFERENCES asset.copy (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED, -- XXX could be an serial.issuance
	source			INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	dest			INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	prev_hop		INT				REFERENCES action.transit_copy (id) DEFERRABLE INITIALLY DEFERRED,
	copy_status		INT				NOT NULL REFERENCES config.copy_status (id) DEFERRABLE INITIALLY DEFERRED,
	persistant_transfer	BOOL				NOT NULL DEFAULT FALSE,
	prev_dest       INT				REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX active_transit_dest_idx ON "action".transit_copy (dest); 
CREATE INDEX active_transit_source_idx ON "action".transit_copy (source);
CREATE INDEX active_transit_cp_idx ON "action".transit_copy (target_copy);


CREATE TABLE action.hold_transit_copy (
	hold	INT	REFERENCES action.hold_request (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
) INHERITS (action.transit_copy);
ALTER TABLE action.hold_transit_copy ADD PRIMARY KEY (id);
-- ALTER TABLE action.hold_transit_copy ADD CONSTRAINT ahtc_tc_fkey FOREIGN KEY (target_copy) REFERENCES asset.copy (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED; -- XXX could be an serial.issuance
CREATE INDEX active_hold_transit_dest_idx ON "action".hold_transit_copy (dest);
CREATE INDEX active_hold_transit_source_idx ON "action".hold_transit_copy (source);
CREATE INDEX active_hold_transit_cp_idx ON "action".hold_transit_copy (target_copy);


CREATE TABLE action.unfulfilled_hold_list (
	id		BIGSERIAL			PRIMARY KEY,
	current_copy	BIGINT				NOT NULL,
	hold		INT				NOT NULL,
	circ_lib	INT				NOT NULL,
	fail_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX uhr_hold_idx ON action.unfulfilled_hold_list (hold);

CREATE OR REPLACE VIEW action.unfulfilled_hold_loops AS
    SELECT  u.hold,
            c.circ_lib,
            count(*)
      FROM  action.unfulfilled_hold_list u
            JOIN asset.copy c ON (c.id = u.current_copy)
      GROUP BY 1,2;

CREATE OR REPLACE VIEW action.unfulfilled_hold_min_loop AS
    SELECT  hold,
            min(count)
      FROM  action.unfulfilled_hold_loops
      GROUP BY 1;

CREATE OR REPLACE VIEW action.unfulfilled_hold_innermost_loop AS
    SELECT  DISTINCT l.*
      FROM  action.unfulfilled_hold_loops l
            JOIN action.unfulfilled_hold_min_loop m USING (hold)
      WHERE l.count = m.min;

CREATE VIEW action.unfulfilled_hold_max_loop AS
    SELECT  hold,
            max(count) AS max
      FROM  action.unfulfilled_hold_loops
      GROUP BY 1;


CREATE TABLE action.fieldset (
    id              SERIAL          PRIMARY KEY,
    owner           INT             NOT NULL REFERENCES actor.usr (id)
                                    DEFERRABLE INITIALLY DEFERRED,
	owning_lib      INT             NOT NULL REFERENCES actor.org_unit (id)
                                    DEFERRABLE INITIALLY DEFERRED,
	status          TEXT            NOT NULL
	                                CONSTRAINT valid_status CHECK ( status in
									( 'PENDING', 'APPLIED', 'ERROR' )),
    creation_time   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    scheduled_time  TIMESTAMPTZ,
    applied_time    TIMESTAMPTZ,
    classname       TEXT            NOT NULL, -- an IDL class name
    name            TEXT            NOT NULL,
    stored_query    INT             REFERENCES query.stored_query (id)
                                    DEFERRABLE INITIALLY DEFERRED,
    pkey_value      TEXT,
	CONSTRAINT lib_name_unique UNIQUE (owning_lib, name),
    CONSTRAINT fieldset_one_or_the_other CHECK (
        (stored_query IS NOT NULL AND pkey_value IS NULL) OR
        (pkey_value IS NOT NULL AND stored_query IS NULL)
    )
	-- the CHECK constraint means we can update the fields for a single
	-- row without all the extra overhead involved in a query
);

CREATE INDEX action_fieldset_sched_time_idx ON action.fieldset( scheduled_time );
CREATE INDEX action_owner_idx               ON action.fieldset( owner );


CREATE TABLE action.fieldset_col_val (
    id              SERIAL  PRIMARY KEY,
    fieldset        INT     NOT NULL REFERENCES action.fieldset
                                         ON DELETE CASCADE
                                         DEFERRABLE INITIALLY DEFERRED,
    col             TEXT    NOT NULL,  -- "field" from the idl ... the column on the table
    val             TEXT,              -- value for the column ... NULL means, well, NULL
    CONSTRAINT fieldset_col_once_per_set UNIQUE (fieldset, col)
);


-- represents a circ chain summary
CREATE TYPE action.circ_chain_summary AS (
    num_circs INTEGER,
    start_time TIMESTAMP WITH TIME ZONE,
    checkout_workstation TEXT,
    last_renewal_time TIMESTAMP WITH TIME ZONE, -- NULL if no renewals
    last_stop_fines TEXT,
    last_stop_fines_time TIMESTAMP WITH TIME ZONE,
    last_renewal_workstation TEXT, -- NULL if no renewals
    last_checkin_workstation TEXT,
    last_checkin_time TIMESTAMP WITH TIME ZONE,
    last_checkin_scan_time TIMESTAMP WITH TIME ZONE
);


CREATE OR REPLACE FUNCTION action.circ_chain ( ctx_circ_id INTEGER ) RETURNS SETOF action.circulation AS $$
DECLARE
    tmp_circ action.circulation%ROWTYPE;
    circ_0 action.circulation%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.circulation WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.circulation WHERE id = tmp_circ.parent_circ;
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        circ_0 := tmp_circ;
    END LOOP;

    -- now send the circs to the caller, oldest to newest
    tmp_circ := circ_0;
    WHILE TRUE LOOP
        IF tmp_circ IS NULL THEN
            EXIT;
        END IF;
        RETURN NEXT tmp_circ;
        SELECT INTO tmp_circ * FROM action.circulation WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION action.summarize_circ_chain ( ctx_circ_id INTEGER ) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.circulation%ROWTYPE;

    -- last circ in the chain
    circ_n action.circulation%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.circulation%ROWTYPE;

BEGIN
    
    chain.num_circs := 0;
    FOR tmp_circ IN SELECT * FROM action.circ_chain(ctx_circ_id) LOOP

        IF chain.num_circs = 0 THEN
            circ_0 := tmp_circ;
        END IF;

        chain.num_circs := chain.num_circs + 1;
        circ_n := tmp_circ;
    END LOOP;

    chain.start_time := circ_0.xact_start;
    chain.last_stop_fines := circ_n.stop_fines;
    chain.last_stop_fines_time := circ_n.stop_fines_time;
    chain.last_checkin_time := circ_n.checkin_time;
    chain.last_checkin_scan_time := circ_n.checkin_scan_time;
    SELECT INTO chain.checkout_workstation name FROM actor.workstation WHERE id = circ_0.workstation;
    SELECT INTO chain.last_checkin_workstation name FROM actor.workstation WHERE id = circ_n.checkin_workstation;

    IF chain.num_circs > 1 THEN
        chain.last_renewal_time := circ_n.xact_start;
        SELECT INTO chain.last_renewal_workstation name FROM actor.workstation WHERE id = circ_n.workstation;
    END IF;

    RETURN chain;

END;
$$ LANGUAGE 'plpgsql';

-- Return the list of circ chain heads in xact_start order that the user has chosen to "retain"
CREATE OR REPLACE FUNCTION action.usr_visible_circs (usr_id INT) RETURNS SETOF action.circulation AS $func$
DECLARE
    c               action.circulation%ROWTYPE;
    view_age        INTERVAL;
    usr_view_age    actor.usr_setting%ROWTYPE;
    usr_view_start  actor.usr_setting%ROWTYPE;
BEGIN
    SELECT * INTO usr_view_age FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.circ.retention_age';
    SELECT * INTO usr_view_start FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.circ.retention_start';

    IF usr_view_age.value IS NOT NULL AND usr_view_start.value IS NOT NULL THEN
        -- User opted in and supplied a retention age
        IF oils_json_to_text(usr_view_age.value)::INTERVAL > AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ) THEN
            view_age := AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ);
        ELSE
            view_age := oils_json_to_text(usr_view_age.value)::INTERVAL;
        END IF;
    ELSIF usr_view_start.value IS NOT NULL THEN
        -- User opted in
        view_age := AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ);
    ELSE
        -- User did not opt in
        RETURN;
    END IF;

    FOR c IN
        SELECT  *
          FROM  action.circulation
          WHERE usr = usr_id
                AND parent_circ IS NULL
                AND xact_start > NOW() - view_age
          ORDER BY xact_start DESC
    LOOP
        RETURN NEXT c;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.usr_visible_circ_copies( INTEGER ) RETURNS SETOF BIGINT AS $$
    SELECT DISTINCT(target_copy) FROM action.usr_visible_circs($1)
$$ LANGUAGE SQL ROWS 10;

CREATE OR REPLACE FUNCTION action.usr_visible_holds (usr_id INT) RETURNS SETOF action.hold_request AS $func$
DECLARE
    h               action.hold_request%ROWTYPE;
    view_age        INTERVAL;
    view_count      INT;
    usr_view_count  actor.usr_setting%ROWTYPE;
    usr_view_age    actor.usr_setting%ROWTYPE;
    usr_view_start  actor.usr_setting%ROWTYPE;
BEGIN
    SELECT * INTO usr_view_count FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.hold.retention_count';
    SELECT * INTO usr_view_age FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.hold.retention_age';
    SELECT * INTO usr_view_start FROM actor.usr_setting WHERE usr = usr_id AND name = 'history.hold.retention_start';

    FOR h IN
        SELECT  *
          FROM  action.hold_request
          WHERE usr = usr_id
                AND fulfillment_time IS NULL
                AND cancel_time IS NULL
          ORDER BY request_time DESC
    LOOP
        RETURN NEXT h;
    END LOOP;

    IF usr_view_start.value IS NULL THEN
        RETURN;
    END IF;

    IF usr_view_age.value IS NOT NULL THEN
        -- User opted in and supplied a retention age
        IF oils_json_to_text(usr_view_age.value)::INTERVAL > AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ) THEN
            view_age := AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ);
        ELSE
            view_age := oils_json_to_text(usr_view_age.value)::INTERVAL;
        END IF;
    ELSE
        -- User opted in
        view_age := AGE(NOW(), oils_json_to_text(usr_view_start.value)::TIMESTAMPTZ);
    END IF;

    IF usr_view_count.value IS NOT NULL THEN
        view_count := oils_json_to_text(usr_view_count.value)::INT;
    ELSE
        view_count := 1000;
    END IF;

    -- show some fulfilled/canceled holds
    FOR h IN
        SELECT  *
          FROM  action.hold_request
          WHERE usr = usr_id
                AND ( fulfillment_time IS NOT NULL OR cancel_time IS NOT NULL )
                AND request_time > NOW() - view_age
          ORDER BY request_time DESC
          LIMIT view_count
    LOOP
        RETURN NEXT h;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.purge_circulations () RETURNS INT AS $func$
DECLARE
    usr_keep_age    actor.usr_setting%ROWTYPE;
    usr_keep_start  actor.usr_setting%ROWTYPE;
    org_keep_age    INTERVAL;
    org_keep_count  INT;

    keep_age        INTERVAL;

    target_acp      RECORD;
    circ_chain_head action.circulation%ROWTYPE;
    circ_chain_tail action.circulation%ROWTYPE;

    purge_position  INT;
    count_purged    INT;
BEGIN

    count_purged := 0;

    SELECT value::INTERVAL INTO org_keep_age FROM config.global_flag WHERE name = 'history.circ.retention_age' AND enabled;

    SELECT value::INT INTO org_keep_count FROM config.global_flag WHERE name = 'history.circ.retention_count' AND enabled;
    IF org_keep_count IS NULL THEN
        RETURN count_purged; -- Gimme a count to keep, or I keep them all, forever
    END IF;

    -- First, find copies with more than keep_count non-renewal circs
    FOR target_acp IN
        SELECT  target_copy,
                COUNT(*) AS total_real_circs
          FROM  action.circulation
          WHERE parent_circ IS NULL
                AND xact_finish IS NOT NULL
          GROUP BY target_copy
          HAVING COUNT(*) > org_keep_count
    LOOP
        purge_position := 0;
        -- And, for those, select circs that are finished and older than keep_age
        FOR circ_chain_head IN
            SELECT  *
              FROM  action.circulation
              WHERE target_copy = target_acp.target_copy
                    AND parent_circ IS NULL
              ORDER BY xact_start
        LOOP

            -- Stop once we've purged enough circs to hit org_keep_count
            EXIT WHEN target_acp.total_real_circs - purge_position <= org_keep_count;

            SELECT * INTO circ_chain_tail FROM action.circ_chain(circ_chain_head.id) ORDER BY xact_start DESC LIMIT 1;
            EXIT WHEN circ_chain_tail.xact_finish IS NULL;

            -- Now get the user settings, if any, to block purging if the user wants to keep more circs
            usr_keep_age.value := NULL;
            SELECT * INTO usr_keep_age FROM actor.usr_setting WHERE usr = circ_chain_head.usr AND name = 'history.circ.retention_age';

            usr_keep_start.value := NULL;
            SELECT * INTO usr_keep_start FROM actor.usr_setting WHERE usr = circ_chain_head.usr AND name = 'history.circ.retention_start';

            IF usr_keep_age.value IS NOT NULL AND usr_keep_start.value IS NOT NULL THEN
                IF oils_json_to_text(usr_keep_age.value)::INTERVAL > AGE(NOW(), oils_json_to_text(usr_keep_start.value)::TIMESTAMPTZ) THEN
                    keep_age := AGE(NOW(), oils_json_to_text(usr_keep_start.value)::TIMESTAMPTZ);
                ELSE
                    keep_age := oils_json_to_text(usr_keep_age.value)::INTERVAL;
                END IF;
            ELSIF usr_keep_start.value IS NOT NULL THEN
                keep_age := AGE(NOW(), oils_json_to_text(usr_keep_start.value)::TIMESTAMPTZ);
            ELSE
                keep_age := COALESCE( org_keep_age::INTERVAL, '2000 years'::INTERVAL );
            END IF;

            EXIT WHEN AGE(NOW(), circ_chain_tail.xact_finish) < keep_age;

            -- We've passed the purging tests, purge the circ chain starting at the end
            DELETE FROM action.circulation WHERE id = circ_chain_tail.id;
            WHILE circ_chain_tail.parent_circ IS NOT NULL LOOP
                SELECT * INTO circ_chain_tail FROM action.circulation WHERE id = circ_chain_tail.parent_circ;
                DELETE FROM action.circulation WHERE id = circ_chain_tail.id;
            END LOOP;

            count_purged := count_purged + 1;
            purge_position := purge_position + 1;

        END LOOP;
    END LOOP;
END;
$func$ LANGUAGE PLPGSQL;


CREATE OR REPLACE FUNCTION action.apply_fieldset(
	fieldset_id IN INT,        -- id from action.fieldset
	table_name  IN TEXT,       -- table to be updated
	pkey_name   IN TEXT,       -- name of primary key column in that table
	query       IN TEXT        -- query constructed by qstore (for query-based
	                           --    fieldsets only; otherwise null
)
RETURNS TEXT AS $$
DECLARE
	statement TEXT;
	fs_status TEXT;
	fs_pkey_value TEXT;
	fs_query TEXT;
	sep CHAR;
	status_code TEXT;
	msg TEXT;
	update_count INT;
	cv RECORD;
BEGIN
	-- Sanity checks
	IF fieldset_id IS NULL THEN
		RETURN 'Fieldset ID parameter is NULL';
	END IF;
	IF table_name IS NULL THEN
		RETURN 'Table name parameter is NULL';
	END IF;
	IF pkey_name IS NULL THEN
		RETURN 'Primary key name parameter is NULL';
	END IF;
	--
	statement := 'UPDATE ' || table_name || ' SET';
	--
	SELECT
		status,
		quote_literal( pkey_value )
	INTO
		fs_status,
		fs_pkey_value
	FROM
		action.fieldset
	WHERE
		id = fieldset_id;
	--
	IF fs_status IS NULL THEN
		RETURN 'No fieldset found for id = ' || fieldset_id;
	ELSIF fs_status = 'APPLIED' THEN
		RETURN 'Fieldset ' || fieldset_id || ' has already been applied';
	END IF;
	--
	sep := '';
	FOR cv IN
		SELECT  col,
				val
		FROM    action.fieldset_col_val
		WHERE   fieldset = fieldset_id
	LOOP
		statement := statement || sep || ' ' || cv.col
					 || ' = ' || coalesce( quote_literal( cv.val ), 'NULL' );
		sep := ',';
	END LOOP;
	--
	IF sep = '' THEN
		RETURN 'Fieldset ' || fieldset_id || ' has no column values defined';
	END IF;
	--
	-- Add the WHERE clause.  This differs according to whether it's a
	-- single-row fieldset or a query-based fieldset.
	--
	IF query IS NULL        AND fs_pkey_value IS NULL THEN
		RETURN 'Incomplete fieldset: neither a primary key nor a query available';
	ELSIF query IS NOT NULL AND fs_pkey_value IS NULL THEN
	    fs_query := rtrim( query, ';' );
	    statement := statement || ' WHERE ' || pkey_name || ' IN ( '
	                 || fs_query || ' );';
	ELSIF query IS NULL     AND fs_pkey_value IS NOT NULL THEN
		statement := statement || ' WHERE ' || pkey_name || ' = '
				     || fs_pkey_value || ';';
	ELSE  -- both are not null
		RETURN 'Ambiguous fieldset: both a primary key and a query provided';
	END IF;
	--
	-- Execute the update
	--
	BEGIN
		EXECUTE statement;
		GET DIAGNOSTICS update_count = ROW_COUNT;
		--
		IF UPDATE_COUNT > 0 THEN
			status_code := 'APPLIED';
			msg := NULL;
		ELSE
			status_code := 'ERROR';
			msg := 'No eligible rows found for fieldset ' || fieldset_id;
    	END IF;
	EXCEPTION WHEN OTHERS THEN
		status_code := 'ERROR';
		msg := 'Unable to apply fieldset ' || fieldset_id
			   || ': ' || sqlerrm;
	END;
	--
	-- Update fieldset status
	--
	UPDATE action.fieldset
	SET status       = status_code,
	    applied_time = now()
	WHERE id = fieldset_id;
	--
	RETURN msg;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION action.apply_fieldset( INT, TEXT, TEXT, TEXT ) IS $$
Applies a specified fieldset, using a supplied table name and primary
key name.  The query parameter should be non-null only for
query-based fieldsets.

Returns NULL if successful, or an error message if not.
$$;


COMMIT;
