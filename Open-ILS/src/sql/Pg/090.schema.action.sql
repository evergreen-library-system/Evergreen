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
	workstation INT				REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,
	org_unit	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	use_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX action_in_house_use_staff_idx      ON action.in_house_use ( staff );
CREATE INDEX action_in_house_use_ws_idx ON action.in_house_use ( workstation );

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
	workstation INT				REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,
	org_unit	INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	use_time	TIMESTAMP WITH TIME ZONE	NOT NULL DEFAULT NOW()
);
CREATE INDEX non_cat_in_house_use_staff_idx ON action.non_cat_in_house_use ( staff );
CREATE INDEX non_cat_in_house_use_ws_idx ON action.non_cat_in_house_use ( workstation );

CREATE OR REPLACE VIEW action.open_non_cataloged_circulation AS
    SELECT ncc.* 
    FROM action.non_cataloged_circulation ncc
    JOIN config.non_cataloged_type nct ON nct.id = ncc.item_type
    WHERE ncc.circ_time + nct.circ_duration > CURRENT_TIMESTAMP
;

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
	checkin_scan_time   TIMESTAMP WITH TIME ZONE,
    auto_renewal            BOOLEAN	NOT NULL DEFAULT FALSE,
    auto_renewal_remaining  INTEGER
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
DECLARE
    proper_tz TEXT := COALESCE(
        oils_json_to_text((
            SELECT value
              FROM  actor.org_unit_ancestor_setting('lib.timezone',NEW.circ_lib)
              LIMIT 1
        )),
        CURRENT_SETTING('timezone')
    );
BEGIN

    IF (EXTRACT(EPOCH FROM NEW.duration)::INT % EXTRACT(EPOCH FROM '1 day'::INTERVAL)::INT) = 0 -- day-granular duration
        AND SUBSTRING((NEW.due_date AT TIME ZONE proper_tz)::TIME::TEXT FROM 1 FOR 8) <> '23:59:59' THEN -- has not yet been pushed
        NEW.due_date = ((NEW.due_date AT TIME ZONE proper_tz)::DATE + '1 day'::INTERVAL - '1 second'::INTERVAL) || ' ' || proper_tz;
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
CREATE INDEX action_aged_circulation_parent_circ_idx ON action.aged_circulation (parent_circ);

CREATE OR REPLACE VIEW action.all_circulation AS
    SELECT  id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining,
        NULL AS usr
      FROM  action.aged_circulation
            UNION ALL
    SELECT  DISTINCT circ.id,COALESCE(a.post_code,b.post_code) AS usr_post_code, p.home_ou AS usr_home_ou, p.profile AS usr_profile, EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
        cp.call_number AS copy_call_number, circ.copy_location, cn.owning_lib AS copy_owning_lib, cp.circ_lib AS copy_circ_lib,
        cn.record AS copy_bib_record, circ.xact_start, circ.xact_finish, circ.target_copy, circ.circ_lib, circ.circ_staff, circ.checkin_staff,
        circ.checkin_lib, circ.renewal_remaining, circ.grace_period, circ.due_date, circ.stop_fines_time, circ.checkin_time, circ.create_time, circ.duration,
        circ.fine_interval, circ.recurring_fine, circ.max_fine, circ.phone_renewal, circ.desk_renewal, circ.opac_renewal, circ.duration_rule,
        circ.recurring_fine_rule, circ.max_fine_rule, circ.stop_fines, circ.workstation, circ.checkin_workstation, circ.checkin_scan_time,
        circ.parent_circ, circ.auto_renewal, circ.auto_renewal_remaining, circ.usr
      FROM  action.circulation circ
        JOIN asset.copy cp ON (circ.target_copy = cp.id)
        JOIN asset.call_number cn ON (cp.call_number = cn.id)
        JOIN actor.usr p ON (circ.usr = p.id)
        LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
        LEFT JOIN actor.usr_address b ON (p.billing_address = b.id);

CREATE OR REPLACE VIEW action.all_circulation_slim AS
    SELECT * FROM action.circulation
UNION ALL
    SELECT
        id,
        NULL AS usr,
        xact_start,
        xact_finish,
        unrecovered,
        target_copy,
        circ_lib,
        circ_staff,
        checkin_staff,
        checkin_lib,
        renewal_remaining,
        grace_period,
        due_date,
        stop_fines_time,
        checkin_time,
        create_time,
        duration,
        fine_interval,
        recurring_fine,
        max_fine,
        phone_renewal,
        desk_renewal,
        opac_renewal,
        duration_rule,
        recurring_fine_rule,
        max_fine_rule,
        stop_fines,
        workstation,
        checkin_workstation,
        copy_location,
        checkin_scan_time,
        auto_renewal,
        auto_renewal_remaining,
        parent_circ
    FROM action.aged_circulation
;


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
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining
        FROM action.all_circulation WHERE id = OLD.id;

    -- Migrate billings and payments to aged tables

    SELECT 'Y' INTO found FROM config.global_flag 
        WHERE name = 'history.money.age_with_circs' AND enabled;

    IF found = 'Y' THEN
        PERFORM money.age_billings_and_payments_for_xact(OLD.id);
    END IF;

    -- Break the link with the user in action_trigger.event (warning: event_output may essentially have this information)
    UPDATE
        action_trigger.event e
    SET
        context_user = NULL
    FROM
        action.all_circulation c
    WHERE
            c.id = OLD.id
        AND e.context_user = c.usr
        AND e.target = c.id
        AND e.event_def IN (
            SELECT id
            FROM action_trigger.event_definition
            WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'circ')
        )
    ;

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
    label   TEXT    UNIQUE,
    manual  BOOL    NOT NULL DEFAULT FALSE
);

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
	canceled_by		INT REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    canceling_ws    INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED,   
	target			BIGINT				NOT NULL, -- see hold_type
	current_copy		BIGINT,				-- REFERENCES asset.copy (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,  -- XXX could be an serial.unit now...
	fulfillment_staff	INT				REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	fulfillment_lib		INT				REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	request_lib		INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	requestor		INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	usr			INT				NOT NULL REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
	selection_ou		INT				NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	selection_depth		INT				NOT NULL DEFAULT 0,
	pickup_lib		INT				NOT NULL REFERENCES actor.org_unit DEFERRABLE INITIALLY DEFERRED,
	hold_type		TEXT				REFERENCES config.hold_type (hold_type) DEFERRABLE INITIALLY DEFERRED,
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
	current_shelf_lib INT REFERENCES actor.org_unit DEFERRABLE INITIALLY DEFERRED,
    behind_desk BOOLEAN NOT NULL DEFAULT FALSE,
	hopeless_date		TIMESTAMP WITH TIME ZONE
);
ALTER TABLE action.hold_request ADD CONSTRAINT sms_check CHECK (
    sms_notify IS NULL
    OR sms_carrier IS NOT NULL -- and implied sms_notify IS NOT NULL
);


CREATE OR REPLACE FUNCTION action.hold_request_clear_map () RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM action.hold_copy_map WHERE hold = NEW.id;
  RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER hold_request_clear_map_tgr
    AFTER UPDATE ON action.hold_request
    FOR EACH ROW
    WHEN (
        (NEW.cancel_time IS NOT NULL AND OLD.cancel_time IS NULL)
        OR (NEW.fulfillment_time IS NOT NULL AND OLD.fulfillment_time IS NULL)
    )
    EXECUTE PROCEDURE action.hold_request_clear_map();

CREATE INDEX hold_request_target_idx ON action.hold_request (target);
CREATE INDEX hold_request_usr_idx ON action.hold_request (usr);
CREATE INDEX hold_request_pickup_lib_idx ON action.hold_request (pickup_lib);
CREATE INDEX hold_request_current_copy_idx ON action.hold_request (current_copy);
CREATE INDEX hold_request_prev_check_time_idx ON action.hold_request (prev_check_time);
CREATE INDEX hold_request_fulfillment_staff_idx ON action.hold_request ( fulfillment_staff );
CREATE INDEX hold_request_requestor_idx         ON action.hold_request ( requestor );
CREATE INDEX hold_request_open_idx ON action.hold_request (id) WHERE cancel_time IS NULL AND fulfillment_time IS NULL;
CREATE INDEX hold_request_current_copy_before_cap_idx ON action.hold_request (current_copy) WHERE capture_time IS NULL AND cancel_time IS NULL;
CREATE UNIQUE INDEX hold_request_capture_protect_idx ON action.hold_request (current_copy) WHERE current_copy IS NOT NULL AND capture_time IS NOT NULL AND cancel_time IS NULL AND fulfillment_time IS NULL;
CREATE INDEX hold_request_copy_capture_time_idx ON action.hold_request (current_copy,capture_time);
CREATE INDEX hold_request_open_captured_shelf_lib_idx ON action.hold_request (current_shelf_lib) WHERE capture_time IS NOT NULL AND fulfillment_time IS NULL AND (pickup_lib <> current_shelf_lib);
CREATE INDEX hold_fulfillment_time_idx ON action.hold_request (fulfillment_time) WHERE fulfillment_time IS NOT NULL;
CREATE INDEX hold_request_time_idx ON action.hold_request (request_time);
CREATE INDEX hold_request_hopeless_date_idx ON action.hold_request (hopeless_date);

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
	proximity	NUMERIC,
	CONSTRAINT copy_once_per_hold UNIQUE (hold,target_copy)
);
-- CREATE INDEX acm_hold_idx ON action.hold_copy_map (hold);
CREATE INDEX acm_copy_idx ON action.hold_copy_map (target_copy);

CREATE OR REPLACE FUNCTION
    action.hold_request_regen_copy_maps(
        hold_id INTEGER, copy_ids INTEGER[]) RETURNS VOID AS $$
    DELETE FROM action.hold_copy_map WHERE hold = $1;
    INSERT INTO action.hold_copy_map (hold, target_copy) SELECT DISTINCT $1, UNNEST($2);
$$ LANGUAGE SQL;

CREATE TABLE action.hold_request_reset_reason (
    id SERIAL NOT NULL PRIMARY KEY,
    manual BOOLEAN,
    name TEXT UNIQUE
);

CREATE TABLE action.hold_request_reset_reason_entry (
    id SERIAL NOT NULL PRIMARY KEY,
    hold INT REFERENCES action.hold_request (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    reset_reason INT REFERENCES action.hold_request_reset_reason (id) DEFERRABLE INITIALLY DEFERRED,
    note TEXT,
    reset_time TIMESTAMP WITH TIME ZONE,
    requestor INT REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    requestor_workstation INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED
);

CREATE TRIGGER action_hold_request_reset_reason_entry_previous_copy_trig
    AFTER INSERT OR UPDATE ON action.hold_request_reset_reason_entry
    FOR EACH ROW EXECUTE FUNCTION fake_fkey_tgr('previous_copy');

CREATE INDEX ahrrre_hold_idx ON action.hold_request_reset_reason_entry (hold);

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
	prev_dest		INT				REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
	cancel_time		TIMESTAMP WITH TIME ZONE
);
CREATE INDEX active_transit_dest_idx ON "action".transit_copy (dest); 
CREATE INDEX active_transit_source_idx ON "action".transit_copy (source);
CREATE INDEX active_transit_cp_idx ON "action".transit_copy (target_copy);
CREATE INDEX active_transit_for_copy ON action.transit_copy (target_copy)
    WHERE dest_recv_time IS NULL AND cancel_time IS NULL;

-- Check for duplicate transits across all transit types
CREATE OR REPLACE FUNCTION action.copy_transit_is_unique() 
    RETURNS TRIGGER AS $func$
BEGIN
    PERFORM * FROM action.transit_copy 
        WHERE target_copy = NEW.target_copy 
              AND dest_recv_time IS NULL 
              AND cancel_time IS NULL;

    IF FOUND THEN
        RAISE EXCEPTION 'Copy id=% is already in transit', NEW.target_copy;
    END IF;
    RETURN NULL;
END;
$func$ LANGUAGE PLPGSQL STABLE;

CREATE CONSTRAINT TRIGGER transit_copy_is_unique_check
    AFTER INSERT ON action.transit_copy
    FOR EACH ROW EXECUTE PROCEDURE action.copy_transit_is_unique();

CREATE TABLE action.hold_transit_copy (
	hold	INT	REFERENCES action.hold_request (id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
) INHERITS (action.transit_copy);
ALTER TABLE action.hold_transit_copy ADD PRIMARY KEY (id);
-- ALTER TABLE action.hold_transit_copy ADD CONSTRAINT ahtc_tc_fkey FOREIGN KEY (target_copy) REFERENCES asset.copy (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED; -- XXX could be an serial.issuance
CREATE INDEX active_hold_transit_dest_idx ON "action".hold_transit_copy (dest);
CREATE INDEX active_hold_transit_source_idx ON "action".hold_transit_copy (source);
CREATE INDEX active_hold_transit_cp_idx ON "action".hold_transit_copy (target_copy);
CREATE INDEX hold_transit_copy_hold_idx on action.hold_transit_copy (hold);

CREATE CONSTRAINT TRIGGER hold_transit_copy_is_unique_check
    AFTER INSERT ON action.hold_transit_copy
    FOR EACH ROW EXECUTE PROCEDURE action.copy_transit_is_unique();


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


CREATE TABLE action.aged_hold_request (
    usr_post_code		TEXT,
    usr_home_ou		INT	NOT NULL,
    usr_profile		INT	NOT NULL,
    usr_birth_year		INT,
    staff_placed        BOOLEAN NOT NULL,
    LIKE action.hold_request
);
ALTER TABLE action.aged_hold_request
      ADD PRIMARY KEY (id),
      DROP COLUMN usr,
      DROP COLUMN requestor,
      DROP COLUMN sms_carrier,
      ALTER COLUMN phone_notify TYPE BOOLEAN
            USING CASE WHEN phone_notify IS NULL OR phone_notify = '' THEN FALSE ELSE TRUE END,
      ALTER COLUMN sms_notify TYPE BOOLEAN
            USING CASE WHEN sms_notify IS NULL OR sms_notify = '' THEN FALSE ELSE TRUE END,
      ALTER COLUMN phone_notify SET NOT NULL,
      ALTER COLUMN sms_notify SET NOT NULL;
CREATE INDEX aged_hold_request_target_idx ON action.aged_hold_request (target);
CREATE INDEX aged_hold_request_pickup_lib_idx ON action.aged_hold_request (pickup_lib);
CREATE INDEX aged_hold_request_current_copy_idx ON action.aged_hold_request (current_copy);
CREATE INDEX aged_hold_request_fulfillment_staff_idx ON action.aged_hold_request ( fulfillment_staff );

CREATE OR REPLACE VIEW action.all_hold_request AS
    SELECT DISTINCT
           COALESCE(a.post_code, b.post_code) AS usr_post_code,
           p.home_ou AS usr_home_ou,
           p.profile AS usr_profile,
           EXTRACT(YEAR FROM p.dob)::INT AS usr_birth_year,
           CAST(ahr.requestor <> ahr.usr AS BOOLEAN) AS staff_placed,
           ahr.id,
           ahr.request_time,
           ahr.capture_time,
           ahr.fulfillment_time,
           ahr.checkin_time,
           ahr.return_time,
           ahr.prev_check_time,
           ahr.expire_time,
           ahr.cancel_time,
           ahr.cancel_cause,
           ahr.cancel_note,
           ahr.target,
           ahr.current_copy,
           ahr.fulfillment_staff,
           ahr.fulfillment_lib,
           ahr.request_lib,
           ahr.selection_ou,
           ahr.selection_depth,
           ahr.pickup_lib,
           ahr.hold_type,
           ahr.holdable_formats,
           CASE
           WHEN ahr.phone_notify IS NULL THEN FALSE
           WHEN ahr.phone_notify = '' THEN FALSE
           ELSE TRUE
           END AS phone_notify,
           ahr.email_notify,
           CASE
           WHEN ahr.sms_notify IS NULL THEN FALSE
           WHEN ahr.sms_notify = '' THEN FALSE
           ELSE TRUE
           END AS sms_notify,
           ahr.frozen,
           ahr.thaw_date,
           ahr.shelf_time,
           ahr.cut_in_line,
           ahr.mint_condition,
           ahr.shelf_expire_time,
           ahr.current_shelf_lib,
           ahr.behind_desk
    FROM action.hold_request ahr
         JOIN actor.usr p ON (ahr.usr = p.id)
         LEFT JOIN actor.usr_address a ON (p.mailing_address = a.id)
         LEFT JOIN actor.usr_address b ON (p.billing_address = b.id)
    UNION ALL
    SELECT 
           usr_post_code,
           usr_home_ou,
           usr_profile,
           usr_birth_year,
           staff_placed,
           id,
           request_time,
           capture_time,
           fulfillment_time,
           checkin_time,
           return_time,
           prev_check_time,
           expire_time,
           cancel_time,
           cancel_cause,
           cancel_note,
           target,
           current_copy,
           fulfillment_staff,
           fulfillment_lib,
           request_lib,
           selection_ou,
           selection_depth,
           pickup_lib,
           hold_type,
           holdable_formats,
           phone_notify,
           email_notify,
           sms_notify,
           frozen,
           thaw_date,
           shelf_time,
           cut_in_line,
           mint_condition,
           shelf_expire_time,
           current_shelf_lib,
           behind_desk
    FROM action.aged_hold_request;

CREATE OR REPLACE FUNCTION action.age_hold_on_delete () RETURNS TRIGGER AS $$
DECLARE
BEGIN
    -- Archive a copy of the old row to action.aged_hold_request

    INSERT INTO action.aged_hold_request
           (usr_post_code,
            usr_home_ou,
            usr_profile,
            usr_birth_year,
            staff_placed,
            id,
            request_time,
            capture_time,
            fulfillment_time,
            checkin_time,
            return_time,
            prev_check_time,
            expire_time,
            cancel_time,
            cancel_cause,
            cancel_note,
            target,
            current_copy,
            fulfillment_staff,
            fulfillment_lib,
            request_lib,
            selection_ou,
            selection_depth,
            pickup_lib,
            hold_type,
            holdable_formats,
            phone_notify,
            email_notify,
            sms_notify,
            frozen,
            thaw_date,
            shelf_time,
            cut_in_line,
            mint_condition,
            shelf_expire_time,
            current_shelf_lib,
            behind_desk)
      SELECT 
           usr_post_code,
           usr_home_ou,
           usr_profile,
           usr_birth_year,
           staff_placed,
           id,
           request_time,
           capture_time,
           fulfillment_time,
           checkin_time,
           return_time,
           prev_check_time,
           expire_time,
           cancel_time,
           cancel_cause,
           cancel_note,
           target,
           current_copy,
           fulfillment_staff,
           fulfillment_lib,
           request_lib,
           selection_ou,
           selection_depth,
           pickup_lib,
           hold_type,
           holdable_formats,
           phone_notify,
           email_notify,
           sms_notify,
           frozen,
           thaw_date,
           shelf_time,
           cut_in_line,
           mint_condition,
           shelf_expire_time,
           current_shelf_lib,
           behind_desk
        FROM action.all_hold_request WHERE id = OLD.id;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER action_hold_request_aging_tgr
	BEFORE DELETE ON action.hold_request
	FOR EACH ROW
	EXECUTE PROCEDURE action.age_hold_on_delete ();

CREATE TABLE action.fieldset_group (
    id              SERIAL  PRIMARY KEY,
    name            TEXT        NOT NULL,
    create_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    complete_time   TIMESTAMPTZ,
    container       INT,        -- Points to a container of some type ...
    container_type  TEXT,       -- One of 'biblio_record_entry', 'user', 'call_number', 'copy'
    can_rollback    BOOL        DEFAULT TRUE,
    rollback_group  INT         REFERENCES action.fieldset_group (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    rollback_time   TIMESTAMPTZ,
    creator         INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    owning_lib      INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE action.fieldset (
    id              SERIAL          PRIMARY KEY,
    fieldset_group  INT             REFERENCES action.fieldset_group (id)
                                    ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
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
    error_msg       TEXT,
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


CREATE OR REPLACE FUNCTION action.circ_chain ( ctx_circ_id BIGINT ) RETURNS SETOF action.circulation AS $$
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

CREATE OR REPLACE FUNCTION action.summarize_circ_chain ( ctx_circ_id BIGINT ) RETURNS action.circ_chain_summary AS $$

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

-- same as action.circ_chain, but returns action.all_circulation 
-- rows which may include aged circulations.
CREATE OR REPLACE FUNCTION action.all_circ_chain (ctx_circ_id INTEGER) 
    RETURNS SETOF action.all_circulation_slim AS $$
DECLARE
    tmp_circ action.all_circulation_slim%ROWTYPE;
    circ_0 action.all_circulation_slim%ROWTYPE;
BEGIN

    SELECT INTO tmp_circ * FROM action.all_circulation_slim WHERE id = ctx_circ_id;

    IF tmp_circ IS NULL THEN
        RETURN NEXT tmp_circ;
    END IF;
    circ_0 := tmp_circ;

    -- find the front of the chain
    WHILE TRUE LOOP
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
            WHERE id = tmp_circ.parent_circ;
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
        SELECT INTO tmp_circ * FROM action.all_circulation_slim 
            WHERE parent_circ = tmp_circ.id;
    END LOOP;

END;
$$ LANGUAGE 'plpgsql';

-- same as action.summarize_circ_chain, but returns data collected
-- from action.all_circulation, which may include aged circulations.
CREATE OR REPLACE FUNCTION action.summarize_all_circ_chain 
    (ctx_circ_id INTEGER) RETURNS action.circ_chain_summary AS $$

DECLARE

    -- first circ in the chain
    circ_0 action.all_circulation_slim%ROWTYPE;

    -- last circ in the chain
    circ_n action.all_circulation_slim%ROWTYPE;

    -- circ chain under construction
    chain action.circ_chain_summary;
    tmp_circ action.all_circulation_slim%ROWTYPE;

BEGIN
    
    chain.num_circs := 0;
    FOR tmp_circ IN SELECT * FROM action.all_circ_chain(ctx_circ_id) LOOP

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
                AND COALESCE(fulfillment_time, cancel_time) > NOW() - view_age
          ORDER BY COALESCE(fulfillment_time, cancel_time) DESC
          LIMIT view_count
    LOOP
        RETURN NEXT h;
    END LOOP;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.purge_circulations () RETURNS INT AS $func$
DECLARE
    org_keep_age    INTERVAL;
    org_use_last    BOOL = false;
    org_age_is_min  BOOL = false;
    org_keep_count  INT;

    keep_age        INTERVAL;

    target_acp      RECORD;
    circ_chain_head action.circulation%ROWTYPE;
    circ_chain_tail action.circulation%ROWTYPE;

    count_purged    INT;
    num_incomplete  INT;

    last_finished   TIMESTAMP WITH TIME ZONE;
BEGIN

    count_purged := 0;

    SELECT value::INTERVAL INTO org_keep_age FROM config.global_flag WHERE name = 'history.circ.retention_age' AND enabled;

    SELECT value::INT INTO org_keep_count FROM config.global_flag WHERE name = 'history.circ.retention_count' AND enabled;
    IF org_keep_count IS NULL THEN
        RETURN count_purged; -- Gimme a count to keep, or I keep them all, forever
    END IF;

    SELECT enabled INTO org_use_last FROM config.global_flag WHERE name = 'history.circ.retention_uses_last_finished';
    SELECT enabled INTO org_age_is_min FROM config.global_flag WHERE name = 'history.circ.retention_age_is_min';

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
        -- And, for those, select circs that are finished and older than keep_age
        FOR circ_chain_head IN
            -- For reference, the subquery uses a window function to order the circs newest to oldest and number them
            -- The outer query then uses that information to skip the most recent set the library wants to keep
            -- End result is we don't care what order they come out in, as they are all potentials for deletion.
            SELECT ac.* FROM action.circulation ac JOIN (
              SELECT  rank() OVER (ORDER BY xact_start DESC), ac.id
                FROM  action.circulation ac
                WHERE ac.target_copy = target_acp.target_copy
                  AND ac.parent_circ IS NULL
                ORDER BY ac.xact_start ) ranked USING (id)
                WHERE ranked.rank > org_keep_count
        LOOP

            SELECT * INTO circ_chain_tail FROM action.circ_chain(circ_chain_head.id) ORDER BY xact_start DESC LIMIT 1;
            SELECT COUNT(CASE WHEN xact_finish IS NULL THEN 1 ELSE NULL END), MAX(xact_finish) INTO num_incomplete, last_finished FROM action.circ_chain(circ_chain_head.id);
            CONTINUE WHEN circ_chain_tail.xact_finish IS NULL OR num_incomplete > 0;

            IF NOT org_use_last THEN
                last_finished := circ_chain_tail.xact_finish;
            END IF;

            keep_age := COALESCE( org_keep_age, '2000 years'::INTERVAL );

            IF org_age_is_min THEN
                keep_age := GREATEST( keep_age, org_keep_age );
            END IF;

            CONTINUE WHEN AGE(NOW(), last_finished) < keep_age;

            -- We've passed the purging tests, purge the circ chain starting at the end
            -- A trigger should auto-purge the rest of the chain.
            DELETE FROM action.circulation WHERE id = circ_chain_tail.id;

            count_purged := count_purged + 1;

        END LOOP;
    END LOOP;

    return count_purged;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.purge_holds() RETURNS INT AS $func$
DECLARE
  current_hold RECORD;
  purged_holds INT;
  cgf_d INTERVAL;
  cgf_f INTERVAL;
  cgf_c INTERVAL;
  prev_usr INT;
  user_start TIMESTAMPTZ;
  user_age INTERVAL;
  user_count INT;
BEGIN
  purged_holds := 0;
  SELECT INTO cgf_d value::INTERVAL FROM config.global_flag WHERE name = 'history.hold.retention_age' AND enabled;
  SELECT INTO cgf_f value::INTERVAL FROM config.global_flag WHERE name = 'history.hold.retention_age_fulfilled' AND enabled;
  SELECT INTO cgf_c value::INTERVAL FROM config.global_flag WHERE name = 'history.hold.retention_age_canceled' AND enabled;
  FOR current_hold IN
    SELECT
      rank() OVER (PARTITION BY usr ORDER BY COALESCE(fulfillment_time, cancel_time) DESC),
      cgf_cs.value::INTERVAL as cgf_cs,
      ahr.*
    FROM
      action.hold_request ahr
      LEFT JOIN config.global_flag cgf_cs ON (ahr.cancel_cause IS NOT NULL AND cgf_cs.name = 'history.hold.retention_age_canceled_' || ahr.cancel_cause AND cgf_cs.enabled)
    WHERE
      (fulfillment_time IS NOT NULL OR cancel_time IS NOT NULL)
  LOOP
    IF prev_usr IS NULL OR prev_usr != current_hold.usr THEN
      prev_usr := current_hold.usr;
      SELECT INTO user_start oils_json_to_text(value)::TIMESTAMPTZ FROM actor.usr_setting WHERE usr = prev_usr AND name = 'history.hold.retention_start';
      SELECT INTO user_age oils_json_to_text(value)::INTERVAL FROM actor.usr_setting WHERE usr = prev_usr AND name = 'history.hold.retention_age';
      SELECT INTO user_count oils_json_to_text(value)::INT FROM actor.usr_setting WHERE usr = prev_usr AND name = 'history.hold.retention_count';
      IF user_start IS NOT NULL THEN
        user_age := LEAST(user_age, AGE(NOW(), user_start));
      END IF;
      IF user_count IS NULL THEN
        user_count := 1000; -- Assumption based on the user visible holds routine
      END IF;
    END IF;
    -- Library keep age trumps user keep anything, for purposes of being able to hold on to things when staff canceled and such.
    IF current_hold.fulfillment_time IS NOT NULL AND current_hold.fulfillment_time > NOW() - COALESCE(cgf_f, cgf_d) THEN
      CONTINUE;
    END IF;
    IF current_hold.cancel_time IS NOT NULL AND current_hold.cancel_time > NOW() - COALESCE(current_hold.cgf_cs, cgf_c, cgf_d) THEN
      CONTINUE;
    END IF;

    -- User keep age needs combining with count. If too old AND within the count, keep!
    IF user_start IS NOT NULL AND COALESCE(current_hold.fulfillment_time, current_hold.cancel_time) > NOW() - user_age AND current_hold.rank <= user_count THEN
      CONTINUE;
    END IF;

    -- All checks should have passed, delete!
    DELETE FROM action.hold_request WHERE id = current_hold.id;
    purged_holds := purged_holds + 1;
  END LOOP;
  RETURN purged_holds;
END;
$func$ LANGUAGE plpgsql;

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
    where_clause TEXT;
    fs_status TEXT;
    fs_pkey_value TEXT;
    fs_query TEXT;
    sep CHAR;
    status_code TEXT;
    msg TEXT;
    fs_id INT;
    fsg_id INT;
    update_count INT;
    cv RECORD;
    fs_obj action.fieldset%ROWTYPE;
    fs_group action.fieldset_group%ROWTYPE;
    rb_row RECORD;
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
    -- Build the WHERE clause.  This differs according to whether it's a
    -- single-row fieldset or a query-based fieldset.
    --
    IF query IS NULL        AND fs_pkey_value IS NULL THEN
        RETURN 'Incomplete fieldset: neither a primary key nor a query available';
    ELSIF query IS NOT NULL AND fs_pkey_value IS NULL THEN
        fs_query := rtrim( query, ';' );
        where_clause := 'WHERE ' || pkey_name || ' IN ( '
                     || fs_query || ' )';
    ELSIF query IS NULL     AND fs_pkey_value IS NOT NULL THEN
        where_clause := 'WHERE ' || pkey_name || ' = ';
        IF pkey_name = 'id' THEN
            where_clause := where_clause || fs_pkey_value;
        ELSIF pkey_name = 'code' THEN
            where_clause := where_clause || quote_literal(fs_pkey_value);
        ELSE
            RETURN 'Only know how to handle "id" and "code" pkeys currently, received ' || pkey_name;
        END IF;
    ELSE  -- both are not null
        RETURN 'Ambiguous fieldset: both a primary key and a query provided';
    END IF;

    IF fs_status IS NULL THEN
        RETURN 'No fieldset found for id = ' || fieldset_id;
    ELSIF fs_status = 'APPLIED' THEN
        RETURN 'Fieldset ' || fieldset_id || ' has already been applied';
    END IF;

    SELECT * INTO fs_obj FROM action.fieldset WHERE id = fieldset_id;
    SELECT * INTO fs_group FROM action.fieldset_group WHERE id = fs_obj.fieldset_group;

    IF fs_group.can_rollback THEN
        -- This is part of a non-rollback group.  We need to record the current values for future rollback.

        INSERT INTO action.fieldset_group (can_rollback, name, creator, owning_lib, container, container_type)
            VALUES (FALSE, 'ROLLBACK: '|| fs_group.name, fs_group.creator, fs_group.owning_lib, fs_group.container, fs_group.container_type);

        fsg_id := CURRVAL('action.fieldset_group_id_seq');

        FOR rb_row IN EXECUTE 'SELECT * FROM ' || table_name || ' ' || where_clause LOOP
            IF pkey_name = 'id' THEN
                fs_pkey_value := rb_row.id;
            ELSIF pkey_name = 'code' THEN
                fs_pkey_value := rb_row.code;
            ELSE
                RETURN 'Only know how to handle "id" and "code" pkeys currently, received ' || pkey_name;
            END IF;
            INSERT INTO action.fieldset (fieldset_group,owner,owning_lib,status,classname,name,pkey_value)
                VALUES (fsg_id, fs_obj.owner, fs_obj.owning_lib, 'PENDING', fs_obj.classname, fs_obj.name || ' ROLLBACK FOR ' || fs_pkey_value, fs_pkey_value);

            fs_id := CURRVAL('action.fieldset_id_seq');
            sep := '';
            FOR cv IN
                SELECT  DISTINCT col
                FROM    action.fieldset_col_val
                WHERE   fieldset = fieldset_id
            LOOP
                EXECUTE 'INSERT INTO action.fieldset_col_val (fieldset, col, val) ' || 
                    'SELECT '|| fs_id || ', '||quote_literal(cv.col)||', '||cv.col||' FROM '||table_name||' WHERE '||pkey_name||' = '||fs_pkey_value;
            END LOOP;
        END LOOP;
    END IF;

    statement := 'UPDATE ' || table_name || ' SET';

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

    IF sep = '' THEN
        RETURN 'Fieldset ' || fieldset_id || ' has no column values defined';
    END IF;
    statement := statement || ' ' || where_clause;

    --
    -- Execute the update
    --
    BEGIN
        EXECUTE statement;
        GET DIAGNOSTICS update_count = ROW_COUNT;

        IF update_count = 0 THEN
            RAISE data_exception;
        END IF;

        IF fsg_id IS NOT NULL THEN
            UPDATE action.fieldset_group SET rollback_group = fsg_id WHERE id = fs_group.id;
        END IF;

        IF fs_group.id IS NOT NULL THEN
            UPDATE action.fieldset_group SET complete_time = now() WHERE id = fs_group.id;
        END IF;

        UPDATE action.fieldset SET status = 'APPLIED', applied_time = now() WHERE id = fieldset_id;

    EXCEPTION WHEN data_exception THEN
        msg := 'No eligible rows found for fieldset ' || fieldset_id;
        UPDATE action.fieldset SET status = 'ERROR', applied_time = now() WHERE id = fieldset_id;
        RETURN msg;

    END;

    RETURN msg;

EXCEPTION WHEN OTHERS THEN
    msg := 'Unable to apply fieldset ' || fieldset_id || ': ' || sqlerrm;
    UPDATE action.fieldset SET status = 'ERROR', applied_time = now() WHERE id = fieldset_id;
    RETURN msg;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION action.apply_fieldset( INT, TEXT, TEXT, TEXT ) IS $$
Applies a specified fieldset, using a supplied table name and primary
key name.  The query parameter should be non-null only for
query-based fieldsets.

Returns NULL if successful, or an error message if not.
$$;

CREATE OR REPLACE FUNCTION action.copy_calculated_proximity(
    pickup  INT,
    request INT,
    vacp_cl  INT,
    vacp_cm  TEXT,
    vacn_ol  INT,
    vacl_ol  INT
) RETURNS NUMERIC AS $f$
DECLARE
    baseline_prox   NUMERIC;
    aoupa           actor.org_unit_proximity_adjustment%ROWTYPE;
BEGIN

    -- First, gather the baseline proximity of "here" to pickup lib
    SELECT prox INTO baseline_prox FROM actor.org_unit_proximity WHERE from_org = vacp_cl AND to_org = pickup;

    -- Find any absolute adjustments, and set the baseline prox to that
    SELECT  adj.* INTO aoupa
      FROM  actor.org_unit_proximity_adjustment adj
            LEFT JOIN actor.org_unit_ancestors_distance(vacp_cl) acp_cl ON (acp_cl.id = adj.item_circ_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(vacn_ol) acn_ol ON (acn_ol.id = adj.item_owning_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(vacl_ol) acl_ol ON (acl_ol.id = adj.copy_location)
            LEFT JOIN actor.org_unit_ancestors_distance(pickup) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(request) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
      WHERE (adj.circ_mod IS NULL OR adj.circ_mod = vacp_cm) AND
            (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
            (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
            (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
            (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
            (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
            absolute_adjustment AND
            COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
      ORDER BY
            COALESCE(acp_cl.distance,999)
                + COALESCE(acn_ol.distance,999)
                + COALESCE(acl_ol.distance,999)
                + COALESCE(ahr_pl.distance,999)
                + COALESCE(ahr_rl.distance,999),
            adj.pos
      LIMIT 1;

    IF FOUND THEN
        baseline_prox := aoupa.prox_adjustment;
    END IF;

    -- Now find any relative adjustments, and change the baseline prox based on them
    FOR aoupa IN
        SELECT  adj.*
          FROM  actor.org_unit_proximity_adjustment adj
                LEFT JOIN actor.org_unit_ancestors_distance(vacp_cl) acp_cl ON (acp_cl.id = adj.item_circ_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(vacn_ol) acn_ol ON (acn_ol.id = adj.item_owning_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(vacl_ol) acl_ol ON (acn_ol.id = adj.copy_location)
                LEFT JOIN actor.org_unit_ancestors_distance(pickup) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(request) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
          WHERE (adj.circ_mod IS NULL OR adj.circ_mod = vacp_cm) AND
                (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
                (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
                (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
                (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
                (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
                NOT absolute_adjustment AND
                COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
    LOOP
        baseline_prox := baseline_prox + aoupa.prox_adjustment;
    END LOOP;

    RETURN baseline_prox;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.hold_copy_calculated_proximity(
    ahr_id INT,
    acp_id BIGINT,
    copy_context_ou INT DEFAULT NULL
    -- TODO maybe? hold_context_ou INT DEFAULT NULL.  This would optionally
    -- support an "ahprox" measurement: adjust prox between copy circ lib and
    -- hold request lib, but I'm unsure whether to use this theoretical
    -- argument only in the baseline calculation or later in the other
    -- queries in this function.
) RETURNS NUMERIC AS $f$
DECLARE
    ahr  action.hold_request%ROWTYPE;
    acp  asset.copy%ROWTYPE;
    acn  asset.call_number%ROWTYPE;
    acl  asset.copy_location%ROWTYPE;

    prox NUMERIC;
BEGIN

    SELECT * INTO ahr FROM action.hold_request WHERE id = ahr_id;
    SELECT * INTO acp FROM asset.copy WHERE id = acp_id;
    SELECT * INTO acn FROM asset.call_number WHERE id = acp.call_number;
    SELECT * INTO acl FROM asset.copy_location WHERE id = acp.location;

    IF copy_context_ou IS NULL THEN
        copy_context_ou := acp.circ_lib;
    END IF;

    SELECT action.copy_calculated_proximity(
        ahr.pickup_lib,
        ahr.request_lib,
        copy_context_ou,
        acp.circ_modifier,
        acn.owning_lib,
        acl.owning_lib
    ) INTO prox;

    RETURN prox;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.hold_copy_calculated_proximity_update () RETURNS TRIGGER AS $f$
BEGIN
    NEW.proximity := action.hold_copy_calculated_proximity(NEW.hold,NEW.target_copy);
    RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER hold_copy_proximity_update_tgr BEFORE INSERT OR UPDATE ON action.hold_copy_map FOR EACH ROW EXECUTE PROCEDURE action.hold_copy_calculated_proximity_update ();

CREATE TABLE action.usr_circ_history (
    id           BIGSERIAL PRIMARY KEY,
    usr          INTEGER NOT NULL REFERENCES actor.usr(id)
                 DEFERRABLE INITIALLY DEFERRED,
    xact_start   TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    target_copy  BIGINT NOT NULL, -- asset.copy.id / serial.unit.id
    due_date     TIMESTAMP WITH TIME ZONE NOT NULL,
    checkin_time TIMESTAMP WITH TIME ZONE,
    source_circ  BIGINT REFERENCES action.circulation(id)
                 ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX action_usr_circ_history_usr_idx ON action.usr_circ_history ( usr );
CREATE INDEX action_usr_circ_history_source_circ_idx ON action.usr_circ_history ( source_circ );

CREATE TRIGGER action_usr_circ_history_target_copy_trig 
    AFTER INSERT OR UPDATE ON action.usr_circ_history 
    FOR EACH ROW EXECUTE PROCEDURE evergreen.fake_fkey_tgr('target_copy');

CREATE OR REPLACE FUNCTION action.maintain_usr_circ_history() 
    RETURNS TRIGGER AS $FUNK$
DECLARE
    cur_circ  BIGINT;
    first_circ BIGINT;
BEGIN                                                                          

    -- Any retention value signifies history is enabled.
    -- This assumes that clearing these values via external 
    -- process deletes the action.usr_circ_history rows.
    -- TODO: replace these settings w/ a single bool setting?
    PERFORM 1 FROM actor.usr_setting 
        WHERE usr = NEW.usr AND value IS NOT NULL AND name IN (
            'history.circ.retention_age', 
            'history.circ.retention_start'
        );

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' AND NEW.parent_circ IS NULL THEN
        -- Starting a new circulation.  Insert the history row.
        INSERT INTO action.usr_circ_history 
            (usr, xact_start, target_copy, due_date, source_circ)
        VALUES (
            NEW.usr, 
            NEW.xact_start, 
            NEW.target_copy, 
            NEW.due_date, 
            NEW.id
        );

        RETURN NEW;
    END IF;

    -- find the first and last circs in the circ chain 
    -- for the currently modified circ.
    FOR cur_circ IN SELECT id FROM action.circ_chain(NEW.id) LOOP
        IF first_circ IS NULL THEN
            first_circ := cur_circ;
            CONTINUE;
        END IF;
        -- Allow the loop to continue so that at as the loop
        -- completes cur_circ points to the final circulation.
    END LOOP;

    IF NEW.id <> cur_circ THEN
        -- Modifying an intermediate circ.  Ignore it.
        RETURN NEW;
    END IF;

    -- Update the due_date/checkin_time on the history row if the current 
    -- circ is the last circ in the chain and an update is warranted.

    UPDATE action.usr_circ_history 
        SET 
            due_date = NEW.due_date,
            checkin_time = NEW.checkin_time
        WHERE 
            source_circ = first_circ 
            AND (
                due_date <> NEW.due_date OR (
                    (checkin_time IS NULL AND NEW.checkin_time IS NOT NULL) OR
                    (checkin_time IS NOT NULL AND NEW.checkin_time IS NULL) OR
                    (checkin_time <> NEW.checkin_time)
                )
            );
    RETURN NEW;
END;                                                                           
$FUNK$ LANGUAGE PLPGSQL; 

CREATE TRIGGER maintain_usr_circ_history_tgr 
    AFTER INSERT OR UPDATE ON action.circulation 
    FOR EACH ROW EXECUTE PROCEDURE action.maintain_usr_circ_history();

CREATE OR REPLACE VIEW action.all_circulation_combined_types AS 
 SELECT acirc.id AS id,
    acirc.xact_start,
    acirc.circ_lib,
    acirc.circ_staff,
    acirc.create_time,
    ac_acirc.circ_modifier AS item_type,
    'regular_circ'::text AS circ_type
   FROM action.circulation acirc,
    asset.copy ac_acirc
  WHERE acirc.target_copy = ac_acirc.id
UNION ALL
 SELECT ancc.id::BIGINT AS id,
    ancc.circ_time AS xact_start,
    ancc.circ_lib,
    ancc.staff AS circ_staff,
    ancc.circ_time AS create_time,
    cnct_ancc.name AS item_type,
    'non-cat_circ'::text AS circ_type
   FROM action.non_cataloged_circulation ancc,
    config.non_cataloged_type cnct_ancc
  WHERE ancc.item_type = cnct_ancc.id
UNION ALL
 SELECT aihu.id::BIGINT AS id,
    aihu.use_time AS xact_start,
    aihu.org_unit AS circ_lib,
    aihu.staff AS circ_staff,
    aihu.use_time AS create_time,
    ac_aihu.circ_modifier AS item_type,
    'in-house_use'::text AS circ_type
   FROM action.in_house_use aihu,
    asset.copy ac_aihu
  WHERE aihu.item = ac_aihu.id
UNION ALL
 SELECT ancihu.id::BIGINT AS id,
    ancihu.use_time AS xact_start,
    ancihu.org_unit AS circ_lib,
    ancihu.staff AS circ_staff,
    ancihu.use_time AS create_time,
    cnct_ancihu.name AS item_type,
    'non-cat-in-house_use'::text AS circ_type
   FROM action.non_cat_in_house_use ancihu,
    config.non_cataloged_type cnct_ancihu
  WHERE ancihu.item_type = cnct_ancihu.id
UNION ALL
 SELECT aacirc.id AS id,
    aacirc.xact_start,
    aacirc.circ_lib,
    aacirc.circ_staff,
    aacirc.create_time,
    ac_aacirc.circ_modifier AS item_type,
    'aged_circ'::text AS circ_type
   FROM action.aged_circulation aacirc,
    asset.copy ac_aacirc
  WHERE aacirc.target_copy = ac_aacirc.id;

CREATE TABLE action.curbside (
    id          SERIAL      PRIMARY KEY,
    patron      INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    org         INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    slot        TIMESTAMPTZ,
    staged      TIMESTAMPTZ,
    stage_staff     INT     REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    arrival     TIMESTAMPTZ,
    delivered   TIMESTAMPTZ,
    delivery_staff  INT     REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    notes       TEXT
);

CREATE TABLE action.batch_hold_event (
    id          SERIAL  PRIMARY KEY,
    staff       INT     NOT NULL REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    bucket      INT     NOT NULL REFERENCES container.user_bucket (id) ON UPDATE CASCADE ON DELETE CASCADE,
    target      INT     NOT NULL,
    hold_type   TEXT    NOT NULL DEFAULT 'T', -- maybe different hold types in the future...
    run_date    TIMESTAMP WITH TIME ZONE    NOT NULL DEFAULT NOW(),
    cancelled   TIMESTAMP WITH TIME ZONE
);

CREATE TABLE action.batch_hold_event_map (
    id                  SERIAL  PRIMARY KEY,
    batch_hold_event    INT     NOT NULL REFERENCES action.batch_hold_event (id) ON UPDATE CASCADE ON DELETE CASCADE,
    hold                INT     NOT NULL REFERENCES action.hold_request (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE action.eresource_link_click (
    id          BIGSERIAL PRIMARY KEY,
    clicked_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    url         TEXT,
    record      BIGINT NOT NULL REFERENCES biblio.record_entry (id)
);

CREATE TABLE action.eresource_link_click_course (
    id            SERIAL      PRIMARY KEY,
    click         BIGINT NOT NULL REFERENCES action.eresource_link_click (id) ON DELETE CASCADE,
    course        INT REFERENCES asset.course_module_course (id) ON UPDATE CASCADE ON DELETE SET NULL,
    course_name   TEXT NOT NULL,
    course_number TEXT NOT NULL
);

CREATE FUNCTION action.delete_old_eresource_link_clicks(days integer)
    RETURNS VOID AS
    'DELETE FROM action.eresource_link_click
     WHERE clicked_at < current_timestamp
               - ($1::text || '' days'')::interval'
    LANGUAGE SQL
    VOLATILE;

CREATE TABLE action.ingest_queue (
    id          SERIAL      PRIMARY KEY,
    created     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    who         INT         REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    start_time  TIMESTAMPTZ,
    end_time    TIMESTAMPTZ,
    threads     INT,
    why         TEXT
);

CREATE TABLE action.ingest_queue_entry (
    id          BIGSERIAL   PRIMARY KEY,
    record      BIGINT      NOT NULL, -- points to a record id of the appropriate record_type
    record_type TEXT        NOT NULL,
    action      TEXT        NOT NULL,
    run_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    state_data  TEXT        NOT NULL DEFAULT '',
    queue       INT         REFERENCES action.ingest_queue (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    override_by BIGINT      REFERENCES action.ingest_queue_entry (id) ON UPDATE CASCADE ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ingest_time TIMESTAMPTZ,
    fail_time   TIMESTAMPTZ
);
CREATE UNIQUE INDEX record_pending_once ON action.ingest_queue_entry (record_type,record,state_data) WHERE ingest_time IS NULL AND override_by IS NULL;
CREATE INDEX entry_override_by_idx ON action.ingest_queue_entry (override_by) WHERE override_by IS NOT NULL;

CREATE OR REPLACE FUNCTION action.enqueue_ingest_entry (
    record_id       BIGINT,
    rtype           TEXT DEFAULT 'biblio',
    when_to_run     TIMESTAMPTZ DEFAULT NOW(),
    queue_id        INT  DEFAULT NULL,
    ingest_action   TEXT DEFAULT 'update', -- will be the most common?
    old_state_data  TEXT DEFAULT ''
) RETURNS BOOL AS $F$
DECLARE
    new_entry       action.ingest_queue_entry%ROWTYPE;
    prev_del_entry  action.ingest_queue_entry%ROWTYPE;
    diag_detail     TEXT;
    diag_context    TEXT;
BEGIN

    IF ingest_action = 'delete' THEN
        -- first see if there is an outstanding entry
        SELECT  * INTO prev_del_entry
          FROM  action.ingest_queue_entry
          WHERE qe.record = record_id
                AND qe.state_date = old_state_data
                AND qe.record_type = rtype
                AND qe.ingest_time IS NULL
                AND qe.override_by IS NULL;
    END IF;

    WITH existing_queue_entry_cte AS (
        SELECT  queue_id AS queue,
                rtype AS record_type,
                record_id AS record,
                qe.id AS override_by,
                ingest_action AS action,
                q.run_at AS run_at,
                old_state_data AS state_data
          FROM  action.ingest_queue_entry qe
                JOIN action.ingest_queue q ON (qe.queue = q.id)
          WHERE qe.record = record_id
                AND q.end_time IS NULL
                AND qe.record_type = rtype
                AND qe.state_data = old_state_data
                AND qe.ingest_time IS NULL
                AND qe.fail_time IS NULL
                AND qe.override_by IS NULL
    ), existing_nonqueue_entry_cte AS (
        SELECT  queue_id AS queue,
                rtype AS record_type,
                record_id AS record,
                qe.id AS override_by,
                ingest_action AS action,
                qe.run_at AS run_at,
                old_state_data AS state_data
          FROM  action.ingest_queue_entry qe
          WHERE qe.record = record_id
                AND qe.queue IS NULL
                AND qe.record_type = rtype
                AND qe.state_data = old_state_data
                AND qe.ingest_time IS NULL
                AND qe.fail_time IS NULL
                AND qe.override_by IS NULL
    ), new_entry_cte AS (
        SELECT * FROM existing_queue_entry_cte
          UNION ALL
        SELECT * FROM existing_nonqueue_entry_cte
          UNION ALL
        SELECT queue_id, rtype, record_id, NULL, ingest_action, COALESCE(when_to_run,NOW()), old_state_data
    ), insert_entry_cte AS (
        INSERT INTO action.ingest_queue_entry
            (queue, record_type, record, override_by, action, run_at, state_data)
          SELECT queue, record_type, record, override_by, action, run_at, state_data FROM new_entry_cte
            ORDER BY 4 NULLS LAST, 6
            LIMIT 1
        RETURNING *
    ) SELECT * INTO new_entry FROM insert_entry_cte;

    IF prev_del_entry.id IS NOT NULL THEN -- later delete overrides earlier unapplied entry
        UPDATE  action.ingest_queue_entry
          SET   override_by = new_entry.id
          WHERE id = prev_del_entry.id;

        UPDATE  action.ingest_queue_entry
          SET   override_by = NULL
          WHERE id = new_entry.id;

    ELSIF new_entry.override_by IS NOT NULL THEN
        RETURN TRUE; -- already handled, don't notify
    END IF;

    NOTIFY queued_ingest;

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS diag_detail  = PG_EXCEPTION_DETAIL,
                            diag_context = PG_EXCEPTION_CONTEXT;
    RAISE WARNING '%\n%', diag_detail, diag_context;
    RETURN FALSE;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.process_ingest_queue_entry (qeid BIGINT) RETURNS BOOL AS $func$
DECLARE
    ingest_success  BOOL := NULL;
    qe              action.ingest_queue_entry%ROWTYPE;
    aid             authority.record_entry.id%TYPE;
BEGIN

    SELECT * INTO qe FROM action.ingest_queue_entry WHERE id = qeid;
    IF qe.ingest_time IS NOT NULL OR qe.override_by IS NOT NULL THEN
        RETURN TRUE; -- Already done
    END IF;

    IF qe.action = 'delete' THEN
        IF qe.record_type = 'biblio' THEN
            SELECT metabib.indexing_delete(r.*, qe.state_data) INTO ingest_success FROM biblio.record_entry r WHERE r.id = qe.record;
        ELSIF qe.record_type = 'authority' THEN
            SELECT authority.indexing_delete(r.*, qe.state_data) INTO ingest_success FROM authority.record_entry r WHERE r.id = qe.record;
        END IF;
    ELSE
        IF qe.record_type = 'biblio' THEN
            IF qe.action = 'propagate' THEN
                SELECT authority.apply_propagate_changes(qe.state_data::BIGINT, qe.record) INTO aid;
                SELECT aid = qe.state_data::BIGINT INTO ingest_success;
            ELSE
                SELECT metabib.indexing_update(r.*, qe.action = 'insert', qe.state_data) INTO ingest_success FROM biblio.record_entry r WHERE r.id = qe.record;
            END IF;
        ELSIF qe.record_type = 'authority' THEN
            SELECT authority.indexing_update(r.*, qe.action = 'insert', qe.state_data) INTO ingest_success FROM authority.record_entry r WHERE r.id = qe.record;
        END IF;
    END IF;

    IF NOT ingest_success THEN
        UPDATE action.ingest_queue_entry SET fail_time = NOW() WHERE id = qe.id;
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.queued.abort_on_error' AND enabled;
        IF FOUND THEN
            RAISE EXCEPTION 'Ingest action of % on %.record_entry % for queue entry % failed', qe.action, qe.record_type, qe.record, qe.id;
        ELSE
            RAISE WARNING 'Ingest action of % on %.record_entry % for queue entry % failed', qe.action, qe.record_type, qe.record, qe.id;
        END IF;
    ELSE
        IF qe.record_type = 'biblio' THEN
            PERFORM reporter.simple_rec_update(qe.record, qe.action = 'delete');
        END IF;
        UPDATE action.ingest_queue_entry SET ingest_time = NOW() WHERE id = qe.id;
    END IF;

    RETURN ingest_success;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.complete_duplicated_entries () RETURNS TRIGGER AS $F$
BEGIN
    IF NEW.ingest_time IS NOT NULL THEN
        UPDATE action.ingest_queue_entry SET ingest_time = NEW.ingest_time WHERE override_by = NEW.id;
    END IF;

    RETURN NULL;
END;
$F$ LANGUAGE PLPGSQL;

CREATE TRIGGER complete_duplicated_entries_trigger
    AFTER UPDATE ON action.ingest_queue_entry
    FOR EACH ROW WHEN (NEW.override_by IS NULL)
    EXECUTE PROCEDURE action.complete_duplicated_entries();

CREATE OR REPLACE FUNCTION action.set_ingest_queue(INT) RETURNS VOID AS $$
    $_SHARED{"ingest_queue_id"} = $_[0];
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.get_ingest_queue() RETURNS INT AS $$
    return $_SHARED{"ingest_queue_id"};
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.clear_ingest_queue() RETURNS VOID AS $$
    delete($_SHARED{"ingest_queue_id"});
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.set_queued_ingest_force(TEXT) RETURNS VOID AS $$
    $_SHARED{"ingest_queue_force"} = $_[0];
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.get_queued_ingest_force() RETURNS TEXT AS $$
    return $_SHARED{"ingest_queue_force"};
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION action.clear_queued_ingest_force() RETURNS VOID AS $$
    delete($_SHARED{"ingest_queue_force"});
$$ LANGUAGE plperlu;

CREATE OR REPLACE FUNCTION authority.propagate_changes
    (aid BIGINT, bid BIGINT) RETURNS BIGINT AS $func$
DECLARE
    queuing_success BOOL := FALSE;
BEGIN

    PERFORM 1 FROM config.global_flag
        WHERE name IN ('ingest.queued.all','ingest.queued.authority.propagate')
            AND enabled;

    IF FOUND THEN
        -- XXX enqueue special 'propagate' bib action
        SELECT action.enqueue_ingest_entry( bid, 'biblio', NOW(), NULL, 'propagate', aid::TEXT) INTO queuing_success;

        IF queuing_success THEN
            RETURN aid;
        END IF;
    END IF;

    PERFORM authority.apply_propagate_changes(aid, bid);
    RETURN aid;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.apply_propagate_changes
    (aid BIGINT, bid BIGINT) RETURNS BIGINT AS $func$
DECLARE
    bib_forced  BOOL := FALSE;
    bib_rec     biblio.record_entry%ROWTYPE;
    new_marc    TEXT;
BEGIN

    SELECT INTO bib_rec * FROM biblio.record_entry WHERE id = bid;

    new_marc := vandelay.merge_record_xml(
        bib_rec.marc, authority.generate_overlay_template(aid));

    IF new_marc = bib_rec.marc THEN
        -- Authority record change had no impact on this bib record.
        -- Nothing left to do.
        RETURN aid;
    END IF;

    PERFORM 1 FROM config.global_flag
        WHERE name = 'ingest.disable_authority_auto_update_bib_meta'
            AND enabled;

    IF NOT FOUND THEN
        -- update the bib record editor and edit_date
        bib_rec.editor := (
            SELECT editor FROM authority.record_entry WHERE id = aid);
        bib_rec.edit_date = NOW();
    END IF;

    PERFORM action.set_queued_ingest_force('ingest.queued.biblio.update.disabled');

    UPDATE biblio.record_entry SET
        marc = new_marc,
        editor = bib_rec.editor,
        edit_date = bib_rec.edit_date
    WHERE id = bid;

    PERFORM action.clear_queued_ingest_force();

    RETURN aid;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.indexing_ingest_or_delete () RETURNS TRIGGER AS $func$
DECLARE
    old_state_data      TEXT := '';
    new_action          TEXT;
    queuing_force       TEXT;
    queuing_flag_name   TEXT;
    queuing_flag        BOOL := FALSE;
    queuing_success     BOOL := FALSE;
    ingest_success      BOOL := FALSE;
    ingest_queue        INT;
BEGIN

    -- Identify the ingest action type
    IF TG_OP = 'UPDATE' THEN

        -- Gather type-specific data for later use
        IF TG_TABLE_SCHEMA = 'authority' THEN
            old_state_data = OLD.heading;
        END IF;

        IF NOT OLD.deleted THEN -- maybe reingest?
            IF NEW.deleted THEN
                new_action = 'delete'; -- nope, delete
            ELSE
                new_action = 'update'; -- yes, update
            END IF;
        ELSIF NOT NEW.deleted THEN
            new_action = 'insert'; -- revivify, AKA insert
        ELSE
            RETURN NEW; -- was and is still deleted, don't ingest
        END IF;
    ELSIF TG_OP = 'INSERT' THEN
        new_action = 'insert'; -- brand new
    ELSE
        RETURN OLD; -- really deleting the record
    END IF;

    queuing_flag_name := 'ingest.queued.'||TG_TABLE_SCHEMA||'.'||new_action;
    -- See if we should be queuing anything
    SELECT  enabled INTO queuing_flag
      FROM  config.internal_flag
      WHERE name IN ('ingest.queued.all','ingest.queued.'||TG_TABLE_SCHEMA||'.all', queuing_flag_name)
            AND enabled
      LIMIT 1;

    SELECT action.get_queued_ingest_force() INTO queuing_force;
    IF queuing_flag IS NULL AND queuing_force = queuing_flag_name THEN
        queuing_flag := TRUE;
    END IF;

    -- you (or part of authority propagation) can forcibly disable specific queuing actions
    IF queuing_force = queuing_flag_name||'.disabled' THEN
        queuing_flag := FALSE;
    END IF;

    -- And if we should be queuing ...
    IF queuing_flag THEN
        ingest_queue := action.get_ingest_queue();

        -- ... but this is NOT a named or forced queue request (marc editor update, say, or vandelay overlay)...
        IF queuing_force IS NULL AND ingest_queue IS NULL AND new_action = 'update' THEN -- re-ingest?

            PERFORM * FROM config.internal_flag WHERE name = 'ingest.reingest.force_on_same_marc' AND enabled;

            --  ... then don't do anything if ingest.reingest.force_on_same_marc is not enabled and the MARC hasn't changed
            IF NOT FOUND AND OLD.marc = NEW.marc THEN
                RETURN NEW;
            END IF;
        END IF;

        -- Otherwise, attempt to enqueue
        SELECT action.enqueue_ingest_entry( NEW.id, TG_TABLE_SCHEMA, NOW(), ingest_queue, new_action, old_state_data) INTO queuing_success;
    END IF;

    -- If queuing was not requested, or failed for some reason, do it live.
    IF NOT queuing_success THEN
        IF queuing_flag THEN
            RAISE WARNING 'Enqueuing of %.record_entry % for ingest failed, attempting direct ingest', TG_TABLE_SCHEMA, NEW.id;
        END IF;

        IF new_action = 'delete' THEN
            IF TG_TABLE_SCHEMA = 'biblio' THEN
                SELECT metabib.indexing_delete(NEW.*, old_state_data) INTO ingest_success;
            ELSIF TG_TABLE_SCHEMA = 'authority' THEN
                SELECT authority.indexing_delete(NEW.*, old_state_data) INTO ingest_success;
            END IF;
        ELSE
            IF TG_TABLE_SCHEMA = 'biblio' THEN
                SELECT metabib.indexing_update(NEW.*, new_action = 'insert', old_state_data) INTO ingest_success;
            ELSIF TG_TABLE_SCHEMA = 'authority' THEN
                SELECT authority.indexing_update(NEW.*, new_action = 'insert', old_state_data) INTO ingest_success;
            END IF;
        END IF;

        IF NOT ingest_success THEN
            PERFORM * FROM config.internal_flag WHERE name = 'ingest.queued.abort_on_error' AND enabled;
            IF FOUND THEN
                RAISE EXCEPTION 'Ingest of %.record_entry % failed', TG_TABLE_SCHEMA, NEW.id;
            ELSE
                RAISE WARNING 'Ingest of %.record_entry % failed', TG_TABLE_SCHEMA, NEW.id;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$func$ LANGUAGE PLPGSQL;

CREATE TRIGGER aaa_indexing_ingest_or_delete AFTER INSERT OR UPDATE ON biblio.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.indexing_ingest_or_delete ();
CREATE TRIGGER aaa_auth_ingest_or_delete AFTER INSERT OR UPDATE ON authority.record_entry FOR EACH ROW EXECUTE PROCEDURE evergreen.indexing_ingest_or_delete ();

COMMIT;

