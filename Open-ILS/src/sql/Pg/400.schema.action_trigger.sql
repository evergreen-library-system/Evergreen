/*
 * Copyright (C) 2009  Equinox Software, Inc.
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

DROP SCHEMA IF EXISTS action_trigger CASCADE;

BEGIN;

CREATE SCHEMA action_trigger;

CREATE TABLE action_trigger.hook (
    key         TEXT    PRIMARY KEY,
    core_type   TEXT    NOT NULL,
    description TEXT,
    passive     BOOL    NOT NULL DEFAULT FALSE
);
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('checkout','circ','Item checked out to user');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('checkin','circ','Item checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('lost','circ','Circulating Item marked Lost');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('lost.found','circ','Lost Circulating Item checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('lost.auto','circ','Circulating Item automatically marked lost');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('claims_returned','circ','Circulating Item marked Claims Returned');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('claims_returned.found','circ','Claims Returned Circulating Item is checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('missing','acp','Item marked Missing');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('missing.found','acp','Missing Item checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('transit.start','acp','An Item is placed into transit');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('transit.finish','acp','An Item is received from a transit');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_request.success','ahr','A hold is successfully placed');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_request.failure','ahr','A hold is attempted but not successfully placed');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold.capture','ahr','A targeted Item is captured for a hold');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold.available','ahr','A held item is ready for pickup');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_transit.start','ahtc','A hold-captured Item is placed into transit');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_transit.finish','ahtc','A hold-captured Item is received from a transit');
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('checkout.due','circ','Checked out Item is Due',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('penalty.PATRON_EXCEEDS_FINES','ausp','Patron has exceeded allowed fines',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('penalty.PATRON_EXCEEDS_OVERDUE_COUNT','ausp','Patron has exceeded allowed overdue count',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('penalty.PATRON_EXCEEDS_CHECKOUT_COUNT','ausp','Patron has exceeded allowed checkout count',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('penalty.PATRON_EXCEEDS_COLLECTIONS_WARNING','ausp','Patron has exceeded maximum fine amount for collections department warning',TRUE);
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('acqpo.activated','acqpo','Purchase order was activated',FALSE);
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('format.po.html','acqpo','Formats a Purchase Order as an HTML document');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('format.po.pdf','acqpo','Formats a Purchase Order as a PDF document');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('damaged','acp','Item marked damaged');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('checkout.damaged','circ','A circulating item is marked damaged and the patron is fined');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('renewal','circ','Item renewed to user');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('checkout.due.emergency_closing','aecc','Circulation due date was adjusted by the Emergency Closing handler');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold.shelf_expire.emergency_closing','aech','Hold shelf expire time was adjusted by the Emergency Closing handler');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('booking.due.emergency_closing','aecr','Booking reservation return date was adjusted by the Emergency Closing handler');

-- and much more, I'm sure

-- Specialized collection modules.  Given an FM object, gather some info and return a scalar or ref.
CREATE TABLE action_trigger.collector (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Collector:: namespace
    description TEXT    
);
INSERT INTO action_trigger.collector (module,description) VALUES ('fourty_two','Returns the answer to life, the universe and everything');
--INSERT INTO action_trigger.collector (module,description) VALUES ('CircCountsByCircMod','Count of Circulations for a User, broken down by circulation modifier');

-- Simple tests on an FM object from hook.core_type to test for "should we still do this."
CREATE TABLE action_trigger.validator (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Validator:: namespace
    description TEXT    
);
INSERT INTO action_trigger.validator (module,description) VALUES ('fourty_two','Returns the answer to life, the universe and everything');
INSERT INTO action_trigger.validator (module,description) VALUES ('NOOP_True','Always returns true -- validation always passes');
INSERT INTO action_trigger.validator (module,description) VALUES ('NOOP_False','Always returns false -- validation always fails');
INSERT INTO action_trigger.validator (module,description) VALUES ('CircIsOpen','Check that the circulation is still open');
INSERT INTO action_trigger.validator (module,description) VALUES ('HoldIsAvailable','Check that an item is on the hold shelf');
INSERT INTO action_trigger.validator (module,description) VALUES ('CircIsOverdue','Check that the circulation is overdue');
INSERT INTO action_trigger.validator (module,description) VALUES ('MaxPassiveDelayAge','Check that the event is not too far past the delay_field time -- requires a max_delay_age interval parameter');
INSERT INTO action_trigger.validator (module,description) VALUES ('MinPassiveTargetAge','Check that the target is old enough to be used by this event -- requires a min_target_age interval parameter, and accepts an optional target_age_field to specify what time to use for offsetting');

-- After an event passes validation (action_trigger.validator), the reactor processes it.
CREATE TABLE action_trigger.reactor (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Reactor:: namespace
    description TEXT    
);

INSERT INTO action_trigger.reactor (module,description) VALUES
(   'fourty_two',
    oils_i18n_gettext(
        'fourty_two',
        'Returns the answer to life, the universe and everything',
        'atreact',
        'description'
    )
);
INSERT INTO action_trigger.reactor (module,description) VALUES
(   'NOOP_True',
    oils_i18n_gettext(
        'NOOP_True',
        'Always returns true -- reaction always passes',
        'atreact',
        'description'
    )
);
INSERT INTO action_trigger.reactor (module,description) VALUES
(   'NOOP_False',
    oils_i18n_gettext(
        'NOOP_False',
        'Always returns false -- reaction always fails',
        'atreact',
        'description'
    )
);
INSERT INTO action_trigger.reactor (module,description) VALUES
(   'SendEmail',
    oils_i18n_gettext(
        'SendEmail',
        'Send an email based on a user-defined template',
        'atreact',
        'description'
    )
);

-- TODO: build a PDF generator
--INSERT INTO action_trigger.reactor (module,description) VALUES
--(   'GenerateBatchOverduePDF',
--    oils_i18n_gettext(
--        'GenerateBatchOverduePDF',
--        'Output a batch PDF of overdue notices for printing',
--        'atreact',
--        'description'
--    )
--);

INSERT INTO action_trigger.reactor (module,description) VALUES
(   'MarkItemLost',
    oils_i18n_gettext(
        'MarkItemLost',
        'Marks a circulation and associated item as lost',
        'atreact',
        'description'
    )
);
INSERT INTO action_trigger.reactor (module,description) VALUES
(   'ApplyCircFee',
    oils_i18n_gettext(
        'ApplyCircFee',
        'Applies a billing with a pre-defined amount to a circulation',
        'atreact',
        'description'
    )
);
INSERT INTO action_trigger.reactor (module,description) VALUES
(   'ProcessTemplate',
    oils_i18n_gettext(
        'ProcessTemplate',
        'Processes the configured template',
        'atreact',
        'description'
    )
);

-- After an event is reacted to (either success or failure) a cleanup module is run against the resulting environment
CREATE TABLE action_trigger.cleanup (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Cleanup:: namespace
    description TEXT    
);
INSERT INTO action_trigger.cleanup (module,description) VALUES ('fourty_two','Returns the answer to life, the universe and everything');
INSERT INTO action_trigger.cleanup (module,description) VALUES ('NOOP_True','Always returns true -- cleanup always passes');
INSERT INTO action_trigger.cleanup (module,description) VALUES ('NOOP_False','Always returns false -- cleanup always fails');
INSERT INTO action_trigger.cleanup (module,description) VALUES ('ClearAllPending','Remove all future, pending notifications for this target');

CREATE TABLE action_trigger.event_definition (
    id              SERIAL      PRIMARY KEY,
    active          BOOL        NOT NULL DEFAULT TRUE,
    owner           INT         NOT NULL REFERENCES actor.org_unit (id) DEFERRABLE INITIALLY DEFERRED,
    name            TEXT        NOT NULL,
    hook            TEXT        NOT NULL REFERENCES action_trigger.hook (key) DEFERRABLE INITIALLY DEFERRED,
    validator       TEXT        NOT NULL REFERENCES action_trigger.validator (module) DEFERRABLE INITIALLY DEFERRED,
    reactor         TEXT        NOT NULL REFERENCES action_trigger.reactor (module) DEFERRABLE INITIALLY DEFERRED,
    cleanup_success TEXT        REFERENCES action_trigger.cleanup (module) DEFERRABLE INITIALLY DEFERRED,
    cleanup_failure TEXT        REFERENCES action_trigger.cleanup (module) DEFERRABLE INITIALLY DEFERRED,
    delay           INTERVAL    NOT NULL DEFAULT '5 minutes',
    max_delay       INTERVAL,
    repeat_delay    INTERVAL,
    usr_field       TEXT,
    opt_in_setting  TEXT        REFERENCES config.usr_setting_type (name) DEFERRABLE INITIALLY DEFERRED,
    delay_field     TEXT,                 -- for instance, xact_start on a circ hook ... look for fields on hook.core_type where datatype=timestamp? If not set, delay from now()
    group_field     TEXT,                 -- field from this.hook.core_type to batch event targets together on, fed into reactor a group at a time.
    template        TEXT,                 -- the TT block.  will have an 'environment' hash (or array of hashes, grouped events) built up by validator and collector(s), which can be modified.
    granularity     TEXT,   -- could specify a batch which is the only time these events should actually run

    message_template        TEXT,
    message_usr_path        TEXT,
    message_library_path    TEXT,
    message_title           TEXT,
    retention_interval      INTERVAL,

    CONSTRAINT ev_def_owner_hook_val_react_clean_delay_once UNIQUE (owner, hook, validator, reactor, delay, delay_field),
    CONSTRAINT ev_def_name_owner_once UNIQUE (owner, name)
);

CREATE OR REPLACE FUNCTION action_trigger.check_valid_retention_interval() 
    RETURNS TRIGGER AS $_$
BEGIN
    /*
     * 1. Retention intervals are always allowed on active hooks.
     * 2. On passive hooks, retention intervals are only allowed
     *    when the event definition has a max_delay value and the
     *    retention_interval value is greater than the difference 
     *    beteween the delay and max_delay values.
     */ 
    PERFORM TRUE FROM action_trigger.hook 
        WHERE key = NEW.hook AND NOT passive;

    IF FOUND THEN
        RETURN NEW;
    END IF;

    IF NEW.max_delay IS NOT NULL THEN
        IF EXTRACT(EPOCH FROM NEW.retention_interval) > 
            ABS(EXTRACT(EPOCH FROM (NEW.max_delay - NEW.delay))) THEN
            RETURN NEW; -- all good
        ELSE
            RAISE EXCEPTION 'retention_interval is too short';
        END IF;
    ELSE
        RAISE EXCEPTION 'retention_interval requires max_delay';
    END IF;
END;
$_$ LANGUAGE PLPGSQL;

CREATE TRIGGER is_valid_retention_interval 
    BEFORE INSERT OR UPDATE ON action_trigger.event_definition
    FOR EACH ROW WHEN (NEW.retention_interval IS NOT NULL)
    EXECUTE PROCEDURE action_trigger.check_valid_retention_interval();

CREATE TABLE action_trigger.environment (
    id          SERIAL  PRIMARY KEY,
    event_def   INT     NOT NULL REFERENCES action_trigger.event_definition (id) DEFERRABLE INITIALLY DEFERRED,
    path        TEXT,       -- fields to flesh. given a hook with a core_type of circ, imagine circ_lib.parent_ou expanding to
                            -- {flesh: 2, flesh_fields: {circ: ['circ_lib'], aou: ['parent_ou']}} ... default is to flesh all
                            -- at flesh depth 1
    collector   TEXT    REFERENCES action_trigger.collector (module) DEFERRABLE INITIALLY DEFERRED, -- if set, given the object at 'path', return some data
                                                                      -- to be stashed at environment.<label>
    label       TEXT    CHECK (label NOT IN ('result','target','event')),
    CONSTRAINT env_event_label_once UNIQUE (event_def,label)
);

CREATE TABLE action_trigger.event_output (
    id              BIGSERIAL   PRIMARY KEY,
    create_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_error        BOOLEAN     NOT NULL DEFAULT FALSE,
    data            TEXT        NOT NULL
);

CREATE TABLE action_trigger.event (
    id              BIGSERIAL   PRIMARY KEY,
    target          BIGINT      NOT NULL, -- points at the id from class defined by event_def.hook.core_type
    event_def       INT         REFERENCES action_trigger.event_definition (id) DEFERRABLE INITIALLY DEFERRED,
    add_time        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_time        TIMESTAMPTZ NOT NULL,
    start_time      TIMESTAMPTZ,
    update_time     TIMESTAMPTZ,
    complete_time   TIMESTAMPTZ,
    update_process  INT,
    state           TEXT        NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','invalid','found','collecting','collected','validating','valid','reacting','reacted','cleaning','complete','error')),
    user_data       TEXT        CHECK (user_data IS NULL OR is_json( user_data )),
    template_output BIGINT      REFERENCES action_trigger.event_output (id),
    error_output    BIGINT      REFERENCES action_trigger.event_output (id),
    async_output    BIGINT      REFERENCES action_trigger.event_output (id)
);
CREATE INDEX atev_target_def_idx ON action_trigger.event (target,event_def);
CREATE INDEX atev_def_state ON action_trigger.event (event_def,state);
CREATE INDEX atev_template_output ON action_trigger.event (template_output);
CREATE INDEX atev_async_output ON action_trigger.event (async_output);
CREATE INDEX atev_error_output ON action_trigger.event (error_output);

CREATE TABLE action_trigger.event_params (
    id          BIGSERIAL   PRIMARY KEY,
    event_def   INT         NOT NULL REFERENCES action_trigger.event_definition (id) DEFERRABLE INITIALLY DEFERRED,
    param       TEXT        NOT NULL, -- the key under environment.event.params to store the output of ...
    value       TEXT        NOT NULL, -- ... the eval() output of this.  Has access to environment (and, well, all of perl)
    CONSTRAINT event_params_event_def_param_once UNIQUE (event_def,param)
);

CREATE OR REPLACE FUNCTION action_trigger.purge_events() RETURNS VOID AS $_$
/**
  * Deleting expired events without simultaneously deleting their outputs
  * creates orphaned outputs.  Deleting their outputs and all of the events 
  * linking back to them, plus any outputs those events link to is messy and 
  * inefficient.  It's simpler to handle them in 2 sweeping steps.
  *
  * 1. Delete expired events.
  * 2. Delete orphaned event outputs.
  *
  * This has the added benefit of removing outputs that may have been
  * orphaned by some other process.  Such outputs are not usuable by
  * the system.
  *
  * This does not guarantee that all events within an event group are
  * purged at the same time.  In such cases, the remaining events will
  * be purged with the next instance of the purge (or soon thereafter).
  * This is another nod toward efficiency over completeness of old 
  * data that's circling the bit bucket anyway.
  */
BEGIN

    DELETE FROM action_trigger.event WHERE id IN (
        SELECT evt.id
        FROM action_trigger.event evt
        JOIN action_trigger.event_definition def ON (def.id = evt.event_def)
        WHERE def.retention_interval IS NOT NULL 
            AND evt.state <> 'pending'
            AND evt.update_time < (NOW() - def.retention_interval)
    );

    WITH linked_outputs AS (
        SELECT templates.id AS id FROM (
            SELECT DISTINCT(template_output) AS id
                FROM action_trigger.event WHERE template_output IS NOT NULL
            UNION
            SELECT DISTINCT(error_output) AS id
                FROM action_trigger.event WHERE error_output IS NOT NULL
            UNION
            SELECT DISTINCT(async_output) AS id
                FROM action_trigger.event WHERE async_output IS NOT NULL
        ) templates
    ) DELETE FROM action_trigger.event_output
        WHERE id NOT IN (SELECT id FROM linked_outputs);

END;
$_$ LANGUAGE PLPGSQL;

COMMIT;

