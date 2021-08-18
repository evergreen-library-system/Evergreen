BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);


CREATE TABLE action.hold_request_reset_reason (
    id serial NOT NULL,
    manual BOOLEAN,
    name TEXT,
    CONSTRAINT hold_request_reset_reason_pkey PRIMARY KEY (id),
    CONSTRAINT hold_request_reset_reason_name_key UNIQUE (name)
);

CREATE TABLE action.hold_request_reset_reason_entry (
    id serial NOT NULL,
    hold int,
    reset_reason int,
    note text,
    reset_time timestamp with time zone,
    previous_copy bigint,
    requestor int,
    requestor_workstation int,
    CONSTRAINT hold_request_reset_reason_entry_pkey PRIMARY KEY (id),
    CONSTRAINT action_hold_request_reset_reason_entry_reason_fkey FOREIGN KEY (reset_reason)
        REFERENCES action.hold_request_reset_reason (id) MATCH SIMPLE
        ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT action_hold_request_reset_reason_entry_previous_copy_fkey FOREIGN KEY (previous_copy)
        REFERENCES asset.copy (id) MATCH SIMPLE
        ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT action_hold_request_reset_reason_entry_requestor_fkey FOREIGN KEY (requestor)
        REFERENCES actor.usr (id) MATCH SIMPLE
        ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT action_hold_request_reset_reason_entry_req_workstation_fkey FOREIGN KEY (requestor_workstation)
        REFERENCES actor.workstation (id) MATCH SIMPLE
        ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT action_hold_request_reset_reason_entry_hold_fkey FOREIGN KEY (hold)
        REFERENCES action.hold_request (id) MATCH SIMPLE
        ON UPDATE NO ACTION ON DELETE NO ACTION DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX ahrrre_hold_idx ON action.hold_request_reset_reason_entry (hold);

INSERT INTO action.hold_request_reset_reason (id, name, manual) VALUES
(1,'HOLD_TIMED_OUT',false),
(2,'HOLD_MANUAL_RESET',true),
(3,'HOLD_BETTER_HOLD',false),
(4,'HOLD_FROZEN',true),
(5,'HOLD_UNFROZEN',true),
(6,'HOLD_CANCELED',true),
(7,'HOLD_UNCANCELED',true),
(8,'HOLD_UPDATED',true),
(9,'HOLD_CHECKED_OUT',true),
(10,'HOLD_CHECKED_IN',true);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.hold_retarget_previous_targets_interval', 'holds',
  oils_i18n_gettext('circ.hold_retarget_previous_targets_interval',
    'Retarget previous targets interval',
    'coust', 'label'),
  oils_i18n_gettext('circ.hold_retarget_previous_targets_interval',
    'Hold targeter will create proximity adjustments for previously targeted copies within this time interval (in days).',
    'coust', 'description'),
  'integer', null);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.hold_reset_reason_entry_age_threshold', 'holds',
  oils_i18n_gettext('circ.hold_reset_reason_entry_age_threshold',
    'Hold reset reason entry deletion interval',
    'coust', 'label'),
  oils_i18n_gettext('circ.hold_reset_reason_entry_age_threshold',
    'Hold reset reason entries will be removed if older than this interval. Default 1 year if no value provided.',
    'coust', 'description'),
  'interval', null);

COMMIT;