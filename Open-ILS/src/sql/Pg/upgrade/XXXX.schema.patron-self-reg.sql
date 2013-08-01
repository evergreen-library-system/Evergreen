
BEGIN;

-- Track the requesting user
ALTER TABLE staging.user_stage
    ADD COLUMN requesting_usr INTEGER 
        REFERENCES actor.usr(id) ON DELETE SET NULL;

-- add county column to staged address tables and 
-- drop state requirement to match actor.usr_address
ALTER TABLE staging.mailing_address_stage 
    ADD COLUMN county TEXT,
    ALTER COLUMN state DROP DEFAULT,
    ALTER COLUMN state DROP NOT NULL;

ALTER TABLE staging.billing_address_stage 
    ADD COLUMN county TEXT,
    ALTER COLUMN state DROP DEFAULT,
    ALTER COLUMN state DROP NOT NULL;

INSERT INTO config.org_unit_setting_type
    (name, grp, datatype, label, description)
VALUES (
    'opac.allow_pending_user',
    'opac',
    'bool',
    oils_i18n_gettext(
        'opac.allow_pending_user',
        'Allow Patron Self-Registration',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.allow_pending_user',
        'Allow patrons to self-register, creating pending user accounts',
        'coust',
        'description'
    )
), (
    'opac.pending_user_expire_interval',
    'opac',
    'interval',
    oils_i18n_gettext(
        'opac.pending_user_expire_interval',
        'Patron Self-Reg. Expire Interval',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'opac.pending_user_expire_interval',
        'If set, this is the amount of time a pending user account will ' ||
        'be allowed to sit in the database.  After this time, the pending ' ||
        'user information will be purged',
        'coust',
        'description'
    )
), (
    'ui.patron.edit.aua.county.show',
    'gui',
    'bool',
    oils_i18n_gettext(
        'ui.patron.edit.aua.county.require',
        'Show count field on patron registration',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'ui.patron.edit.aua.county.require',
        'The county field will be shown on the patron registration screen',
        'coust',
        'description'
    )
);

COMMIT;
