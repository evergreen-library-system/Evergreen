-- Evergreen DB patch XXXX.data.mark-email-and-phone-invalid.sql
--
-- Add org unit settings and standing penalty types to support
-- the mark email/phone invalid features.
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);


INSERT INTO config.standing_penalty (id, name, label, staff_alert) VALUES
    (
        31,
        'INVALID_PATRON_EMAIL_ADDRESS',
        oils_i18n_gettext(
            31,
            'Patron had an invalid email address',
            'csp',
            'label'
        ),
        TRUE
    ),
    (
        32,
        'INVALID_PATRON_DAY_PHONE',
        oils_i18n_gettext(
            32,
            'Patron had an invalid daytime phone number',
            'csp',
            'label'
        ),
        TRUE
    ),
    (
        33,
        'INVALID_PATRON_EVENING_PHONE',
        oils_i18n_gettext(
            33,
            'Patron had an invalid evening phone number',
            'csp',
            'label'
        ),
        TRUE
    ),
    (
        34,
        'INVALID_PATRON_OTHER_PHONE',
        oils_i18n_gettext(
            34,
            'Patron had an invalid other phone number',
            'csp',
            'label'
        ),
        TRUE
    );


COMMIT;
