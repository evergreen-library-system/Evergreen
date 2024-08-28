BEGIN;

SELECT evergreen.upgrade_deps_block_check('1426', :eg_version);


CREATE TABLE action.hold_request_reset_reason (
    id SERIAL NOT NULL PRIMARY KEY,
    manual BOOLEAN,
    name TEXT UNIQUE
);

CREATE TABLE action.hold_request_reset_reason_entry (
    id SERIAL NOT NULL PRIMARY KEY,
    hold INT REFERENCES action.hold_request (id) DEFERRABLE INITIALLY DEFERRED,
    reset_reason INT REFERENCES action.hold_request_reset_reason (id) DEFERRABLE INITIALLY DEFERRED,
    note TEXT,
    reset_time TIMESTAMP WITH TIME ZONE,
    previous_copy BIGINT REFERENCES asset.copy (id) DEFERRABLE INITIALLY DEFERRED,
    requestor INT REFERENCES actor.usr (id) DEFERRABLE INITIALLY DEFERRED,
    requestor_workstation INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED
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
