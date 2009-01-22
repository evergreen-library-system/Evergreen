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
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('claims_returned','circ','Circulating Item marked Claims Returned');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('claims_returned.found','circ','Claims Returned Circulating Item is checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('missing','acp','Item marked Missing');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('missing.found','acp','Missing Item checked in');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('transit.start','acp','An Item is placed into transit');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('transit.finish','acp','An Item is received from a transit');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_request.success','ahr','A hold is succefully placed');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_request.failure','ahr','A hold is attempted by not succefully placed');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold.capture','ahr','A targeted Item is captured for a hold');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_transit.start','ahtc','A hold-captured Item is placed into transit');
INSERT INTO action_trigger.hook (key,core_type,description) VALUES ('hold_transit.finish','ahtc','A hold-captured Item is received from a transit');
INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES ('checkout.due','circ','Checked out Item is Due',TRUE);
-- and much more, I'm sure

-- Specialized collection modules.  Given an FM object, gather some info and return a scalar or ref.
CREATE TABLE action_trigger.collector (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Collector:: namespace
    description TEXT    
);
INSERT INTO action_trigger.collector (module,description) VALUES ('CircCountsByCircMod','Count of Circulations for a User, broken down by circulation modifier');

-- Simple tests on an FM object from hook.core_type to test for "should we still do this."
CREATE TABLE action_trigger.validator (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Validator:: namespace
    description TEXT    
);
INSERT INTO action_trigger.validator (module,description) VALUES ('CircIsOpen','Check that the circulation is still open');
INSERT INTO action_trigger.validator (module,description) VALUES ('HoldIsAvailable','Check that an item is on the hold shelf');

-- After an event passes validation (action_trigger.validator), the reactor processes it.
CREATE TABLE action_trigger.reactor (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Reactor:: namespace
    description TEXT    
);
INSERT INTO action_trigger.reactor (module,description) VALUES ('SendEmail','Send an email based on a user-defined template');
INSERT INTO action_trigger.reactor (module,description) VALUES ('GenerateBatchOverduePDF','Output a batch PDF of overdue notices for printing');

-- After an event is reacted to (either succes or failure) a cleanup module is run against the resulting environment
CREATE TABLE action_trigger.cleanup (
    module      TEXT    PRIMARY KEY, -- All live under the OpenILS::Trigger::Cleanup:: namespace
    description TEXT    
);
INSERT INTO action_trigger.cleanup (module,description) VALUES ('ClearAllPending','Remove all future, pending notifications for this target');

CREATE TABLE action_trigger.event_definition (
    id              SERIAL      PRIMARY KEY,
    active          BOOL        NOT NULL DEFAULT TRUE,
    owner           INT         NOT NULL REFERENCES actor.org_unit (id),
    hook            TEXT        NOT NULL REFERENCES action_trigger.hook (key),
    validator       TEXT        NOT NULL REFERENCES action_trigger.validator (module),
    reactor         TEXT        NOT NULL REFERENCES action_trigger.reactor (module),
    cleanup_success TEXT        REFERENCES action_trigger.cleanup (module),
    cleanup_failure TEXT        REFERENCES action_trigger.cleanup (module),
    delay           INTERVAL    NOT NULL DEFAULT '5 minutes',
    delay_field     TEXT,                 -- for instance, xact_start on a circ hook ... look for fields on hook.core_type where datatype=timestamp? If not set, delay from now()
    group_field     TEXT,                 -- field from this.hook.core_type to batch event targets together on, fed into reactor a group at a time.
    template        TEXT        NOT NULL, -- the TT block.  will have an 'environment' hash (or array of hashes, grouped events) built up by validator and collector(s), which can be modified.
    CONSTRAINT ev_def_owner_hook_val_react_clean_delay_once UNIQUE (owner, hook, validator, reactor, delay, delay_field)
);

CREATE TABLE action_trigger.environment (
    id          SERIAL  PRIMARY KEY,
    event_def   INT     NOT NULL REFERENCES action_trigger.event_definition (id),
    path        TEXT,       -- fields to flesh. given a hook with a core_type of circ, imagine circ_lib.parent_ou expanding to
                            -- {flesh: 2, flesh_fields: {circ: ['circ_lib'], aou: ['parent_ou']}} ... default is to flesh all
                            -- at flesh depth 1
    collector   TEXT    REFERENCES action_trigger.collector (module), -- if set, given the object at 'path', return some data
                                                                      -- to be stashed at environment.<label>
    label       TEXT    CHECK (label NOT IN ('result','target','event')),
    CONSTRAINT env_event_label_once UNIQUE (event_def,label)
);

CREATE TABLE action_trigger.event (
    id              BIGSERIAL   PRIMARY KEY,
    target          BIGINT      NOT NULL, -- points at the id from class defined by event_def.hook.core_type
    event_def       INT         REFERENCES action_trigger.event_definition (id),
    add_time        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    run_time        TIMESTAMPTZ NOT NULL,
    start_time      TIMESTAMPTZ,
    update_time     TIMESTAMPTZ,
    complete_time   TIMESTAMPTZ,
    update_process  INT,
    state           TEXT        NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','found','collecting','validating','reacting','cleanup','complete','error')),
    template_output TEXT,
    error_output    TEXT
);

CREATE TABLE action_trigger.event_params (
    id          BIGSERIAL   PRIMARY KEY,
    event_def   INT         NOT NULL REFERENCES action_trigger.event_definition (id),
    param       TEXT        NOT NULL, -- the key under environment.event.params to store the output of ...
    value       TEXT        NOT NULL, -- ... the eval() output of this.  Has access to environmen (and, well, all of perl)
    CONSTRAINT event_params_event_def_param_once UNIQUE (event_def,param)
);

--COMMIT;

