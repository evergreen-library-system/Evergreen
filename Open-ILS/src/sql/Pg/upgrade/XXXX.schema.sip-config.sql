
BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version);

DROP SCHEMA IF EXISTS sip CASCADE;

CREATE SCHEMA sip;

-- Collections of settings that can be linked to one or more SIP accounts.
CREATE TABLE sip.setting_group (
    id          SERIAL PRIMARY KEY,
    label       TEXT UNIQUE NOT NULL,
    institution TEXT NOT NULL -- Duplicates OK
);

-- Key/value setting pairs
CREATE TABLE sip.setting (
    id SERIAL       PRIMARY KEY,
    setting_group   INTEGER NOT NULL REFERENCES sip.setting_group (id)
                    ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL,
    value           JSON NOT NULL,
    CONSTRAINT      name_once_per_inst UNIQUE (setting_group, name)
);

CREATE TABLE sip.account (
    id              SERIAL PRIMARY KEY,
    enabled         BOOLEAN NOT NULL DEFAULT TRUE,
    setting_group   INTEGER NOT NULL REFERENCES sip.setting_group (id)
                    DEFERRABLE INITIALLY DEFERRED,
    sip_username    TEXT NOT NULL,
    usr             BIGINT NOT NULL REFERENCES actor.usr(id)
                    DEFERRABLE INITIALLY DEFERRED,
    workstation     INTEGER REFERENCES actor.workstation(id),
    -- sessions for transient accounts are not tracked in sip.session
    transient       BOOLEAN NOT NULL DEFAULT FALSE,
    activity_who    TEXT -- config.usr_activity_type.ewho
);

CREATE TABLE sip.session (
    key         TEXT PRIMARY KEY,
    ils_token   TEXT NOT NULL UNIQUE,
    account     INTEGER NOT NULL REFERENCES sip.account(id)
                ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    create_time TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE sip.screen_message (
    key     TEXT PRIMARY KEY,
    message TEXT NOT NULL
);

-- SEED DATA

INSERT INTO actor.passwd_type (code, name, login, crypt_algo, iter_count)
    VALUES ('sip2', 'SIP2 Client Password', FALSE, 'bf', 5);

-- ID 1 is magic.
INSERT INTO sip.setting_group (id, label, institution) 
    VALUES (1, 'Default Settings', 'example');

-- carve space for other canned setting groups
SELECT SETVAL('sip.setting_group_id_seq'::TEXT, 1000);

-- has to be global since settings are linked to accounts and if
-- status-before-login is used, no account information will be available.
INSERT INTO config.global_flag (name, value, enabled, label) VALUES
(   'sip.sc_status_before_login_institution', NULL, FALSE, 
    oils_i18n_gettext(
        'sip.sc_status_before_login_institution',
        'Activate status-before-login-support and define the institution ' ||
        'value which should be used in the response',
        'cgf', 'label')
);

INSERT INTO sip.setting (setting_group, name, value, description)
VALUES (
    1, 'currency', '"USD"',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'currency'),
        'Monetary amounts are reported in this currency',
        'sipset', 'description')
), (
    1, 'av_format', '"eg_legacy"',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'av_format'),
        'AV Format. Options: eg_legacy, 3m, swyer_a, swyer_b',
        'sipset', 'description')
), (
    1, 'due_date_use_sip_date_format', 'false',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'due_date_use_sip_date_format'),
        'Due date uses 18-char date format (YYYYMMDDZZZZHHMMSS).  Otherwise "YYYY-MM-DD HH:MM:SS',
        'sipset', 'description')
), (
    1, 'patron_status_permit_loans', 'false',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'patron_status_permit_loans'),
        'Checkout and renewal are allowed even when penalties blocking these actions exist',
        'sipset', 'description')
), (
    1, 'patron_status_permit_all', 'false',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'patron_status_permit_all'),
        'Holds, checkouts, and renewals allowed regardless of blocking penalties',
        'sipset', 'description')
), (
    1, 'default_activity_who', 'null',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'default_activity_who'),
        'Patron holds data may be returned as either "title" or "barcode"',
        'sipset', 'description')
), (
    1, 'msg64_summary_datatype', '"title"',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'msg64_summary_datatype'),
        'Patron circulation data may be returned as either "title" or "barcode"',
        'sipset', 'description')
), (
    1, 'msg64_hold_items_available', '"title"',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'msg64_hold_items_available'),
        'Patron holds data may be returned as either "title" or "barcode"',
        'sipset', 'description')
), (
    1, 'checkout.override.COPY_ALERT_MESSAGE', 'true',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'checkout.override.COPY_ALERT_MESSAGE'),
        'Checkout override copy alert message',
        'sipset', 'description')
), (
    1, 'checkout.override.COPY_NOT_AVAILABLE', 'true',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'checkout.override.COPY_NOT_AVAILABLE'),
        'Checkout override copy not available message',
        'sipset', 'description')
), (
    1, 'checkin.override.COPY_ALERT_MESSAGE', 'true',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'checkin.override.COPY_ALERT_MESSAGE'),
        'Checkin override copy alert message',
        'sipset', 'description')
), (
    1, 'checkin.override.COPY_BAD_STATUS', 'true',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'checkin.override.COPY_BAD_STATUS'),
        'Checkin override bad copy status',
        'sipset', 'description')
), (
    1, 'checkin.override.COPY_STATUS_MISSING', 'true',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'checkin.override.COPY_STATUS_MISSING'),
        'Checkin override copy status missing',
        'sipset', 'description')
), (
    1, 'checkin_hold_as_transit', 'false',
    oils_i18n_gettext(
        (SELECT id FROM sip.setting WHERE name = 'checkin_hold_as_transit'),
        'Checkin local holds as transits',
        'sipset', 'description')
);

INSERT INTO sip.screen_message (key, message) VALUES (
    'checkout.open_circ_exists', 
    oils_i18n_gettext(
        'checkout.open_circ_exists',
        'This item is already checked out',
        'sipsm', 'message')
), (
    'checkout.patron_not_allowed', 
    oils_i18n_gettext(
        'checkout.patron_not_allowed',
        'Patron is not allowed to checkout the selected item',
        'sipsm', 'message')
), (
    'payment.overpayment_not_allowed',
    oils_i18n_gettext(
        'payment.overpayment_not_allowed',
        'Overpayment not allowed',
        'sipsm', 'message')
), (
    'payment.transaction_not_found',
    oils_i18n_gettext(
        'payment.transaction_not_found',
        'Bill not found',
        'sipsm', 'message')
);


/* EXAMPLE SETTINGS

-- Example linking a SIP password to the 'admin' account.
SELECT actor.set_passwd(1, 'sip2', 'sip_password');

INSERT INTO actor.workstation (name, owning_lib) VALUES ('BR1-SIP2-Gateway', 4);

INSERT INTO sip.account(
    setting_group, sip_username, sip_password, usr, workstation
) VALUES (
    1, 'admin', 
    (SELECT id FROM actor.passwd WHERE usr = 1 AND passwd_type = 'sip2'),
    1, 
    (SELECT id FROM actor.workstation WHERE name = 'BR1-SIP2-Gateway')
);

*/

COMMIT;


