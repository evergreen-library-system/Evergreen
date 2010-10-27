BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0448'); -- phasefx

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES 
    (   'circ.staff_age_to_lost',
        'circ', 
        oils_i18n_gettext(
            'circ.staff_age_to_lost',
            'An overdue circulation should be aged to a Lost status.',
            'ath',
            'description'
        ), 
        TRUE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        delay_field
    ) VALUES (
        36,
        FALSE,
        1,
        'circ.staff_age_to_lost',
        'circ.staff_age_to_lost',
        'CircIsOverdue',
        'MarkItemLost',
        'due_date'
    )
;

-- DELETE FROM config.upgrade_log WHERE version = '0448'; DELETE FROM action_trigger.event WHERE event_def = 36; DELETE FROM action_trigger.event_params WHERE event_def = 36; DELETE FROM action_trigger.event_definition WHERE id = 36; DELETE FROM action_trigger.hook WHERE key = 'circ.staff_age_to_lost';

COMMIT;

