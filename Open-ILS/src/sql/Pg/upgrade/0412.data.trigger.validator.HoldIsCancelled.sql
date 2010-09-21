BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0412'); -- phasefx

INSERT INTO action_trigger.validator (module, description) VALUES (
    'HoldIsCancelled',
    oils_i18n_gettext(
        'HoldIsCancelled',
        'Check whether a hold request is cancelled.',
        'atval',
        'description'
    )
);

COMMIT;

