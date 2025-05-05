BEGIN;

SELECT evergreen.upgrade_deps_block_check('YYYY', :eg_version); -- berick/csharp/Dyrcona/phasefx

INSERT INTO actor.passwd_type
    (code, name, login, crypt_algo, iter_count)
    VALUES ('ecard_vendor', 'eCard Vendor Password', FALSE, 'bf', 10);

-- Example linking a SIP password to the 'admin' account.
-- SELECT actor.set_passwd(1, 'ecard_vendor', 'ecard_password');

INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class )
VALUES
( 'opac.ecard_registration_enabled', 'opac',
    oils_i18n_gettext('opac.ecard_registration_enabled',
        'Enable eCard registration feature in the OPAC',
        'coust', 'label'),
    oils_i18n_gettext('opac.ecard_registration_enabled',
        'Enable access to the eCard registration form in the OPAC',
        'coust', 'description'),
    'bool', null)
,( 'opac.ecard_verification_enabled', 'opac',
    oils_i18n_gettext('opac.ecard_verification_enabled',
        'Enable eCard verification feature in the OPAC',
        'coust', 'label'),
    oils_i18n_gettext('opac.ecard_verification_enabled',
        'Enable access to the eCard verification form in the OPAC',
        'coust', 'description'),
    'bool', null)
,( 'vendor.quipu.ecard.account_id', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.account_id',
        'Quipu eCard Customer Account',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.account_id',
        'Quipu Customer Account ID to be used for eCard registration',
        'coust', 'description'),
    'integer', null)
,( 'vendor.quipu.ecard.shared_secret', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.shared_secret',
        'Quipu eCard Shared Secret',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.shared_secret',
        'Quipu Customer Account shared secret to be used for eCard authentication',
        'coust', 'description'),
    'string', null)
,( 'vendor.quipu.ecard.barcode_prefix', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.barcode_prefix',
        'Barcode prefix for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.barcode_prefix',
        'Set the barcode prefix for new Quipu eCard users',
        'coust', 'description'),
    'string', null)
,( 'vendor.quipu.ecard.barcode_length', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.barcode_length',
        'Barcode length for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.barcode_length',
        'Set the barcode length for new Quipu eCard users',
        'coust', 'description'),
    'integer', null)
,( 'vendor.quipu.ecard.calculate_checkdigit', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.calculate_checkdigit',
        'Calculate barcode checkdigit for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.calculate_checkdigit',
        'Calculate the barcode check digit for new Quipu eCard users',
        'coust', 'description'),
    'bool', null)
,( 'vendor.quipu.ecard.patron_profile', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.patron_profile',
        'Patron permission profile for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.patron_profile',
        'Patron permission profile for Quipu eCard feature',
        'coust', 'description'),
    'link', 'pgt')
,( 'vendor.quipu.ecard.patron_profile.verified', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.patron_profile.verified',
        'Patron permission profile after verification for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.patron_profile.verified',
        'Patron permission profile after verification for Quipu eCard feature. This is only used if the setting "Enable eCard verification feature in the OPAC" is active.',
        'coust', 'description'),
    'link', 'pgt')
,( 'vendor.quipu.ecard.admin_usrname', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.admin_usrname',
        'Evergreen Admin Username for the Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.admin_usrname',
        'Username of the Evergreen admin account that will create new Quipu eCard users',
        'coust', 'description'),
    'string', null)
,( 'vendor.quipu.ecard.admin_org_unit', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.admin_org_unit',
        'Admin organizational unit for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.admin_org_unit',
        'Organizational unit used by the Evergreen admin user of the Quipu eCard feature',
        'coust', 'description'),
    'link', 'aou')
;

-- A/T seed data
INSERT into action_trigger.hook (key, core_type, description) VALUES
( 'au.create.ecard', 'au', 'A patron has been created via Ecard');

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    'f', 1, 'Send Ecard Verification Email', 'au.create.ecard', 'NOOP_True', 'SendEmail', '00:00:00',
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = target.home_ou -%]
To: [%- params.recipient_email || user_data.email || user_data.0.email || user.email %]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Reply-To: [%- lib.email || params.sender_email || default_sender %]
Subject: Your Library Ecard Verification Code
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],

We will never call to ask you for this code, and make sure you do not share it with anyone calling you directly.

Use this code to verify the Ecard registration for your Evergreen account:

One-Time code: [% user.ident_value2 %]

Sincerely,
[% lib.name %]

Contact your library for more information:

[% lib.name %]
[%- SET addr = lib.mailing_address -%]
[%- IF !addr -%] [%- SET addr = lib.billing_address -%] [%- END %]
[% addr.street1 %] [% addr.street2 %]
[% addr.city %], [% addr.state %]
[% addr.post_code %]
[% lib.phone %]
$$);

INSERT INTO action_trigger.environment (event_def, path)
VALUES (currval('action_trigger.event_definition_id_seq'), 'home_ou'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.mailing_address'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.billing_address');

-- ID has to be under 100 in order to prevent it from appearing as a dropdown in the patron editor.
INSERT INTO config.standing_penalty (id, name, label, staff_alert, org_depth) 
VALUES (90, 'PATRON_TEMP_RENEWAL',
	'Patron was given a temporary account renewal. 
	Please archive this message after the account is fully renewed.', TRUE, 0
	);

INSERT into config.org_unit_setting_type (name, label, description, datatype) 
VALUES ( 
    'ui.patron.edit.au.guardian_email.show',
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian_email.show', 
        'GUI: Show guardian email field on patron registration', 
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian_email.show', 
        'The guardian email field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 
        'coust', 'description'
    ),
    'bool'
), (
    'ui.patron.edit.au.guardian_email.suggest',
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian_email.suggest', 
        'GUI: Suggest guardian email field on patron registration', 
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian_email.suggest', 
        'The guardian email field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 
        'coust', 'description'),
    'bool'
);

COMMIT;
