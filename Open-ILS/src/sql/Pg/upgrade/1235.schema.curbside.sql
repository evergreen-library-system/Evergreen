BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1235', :eg_version);

CREATE TABLE action.curbside (
    id          SERIAL      PRIMARY KEY,
    patron      INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    org         INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    slot        TIMESTAMPTZ,
    staged      TIMESTAMPTZ,
    stage_staff     INT     REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    arrival     TIMESTAMPTZ,
    delivered   TIMESTAMPTZ,
    delivery_staff  INT     REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    notes       TEXT
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'circ.curbside',
    'Enable curbside pickup functionality at library.',
    'circ',
    'When set to TRUE, enable staff and public interfaces to schedule curbside pickup of holds that become available for pickup.',
    'bool'
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'circ.curbside.granularity',
    'Time interval between curbside appointments',
    'circ',
    'Time interval between curbside appointments',
    'interval'
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'circ.curbside.max_concurrent',
    'Maximum number of patrons that may select a particular curbside pickup time',
    'circ',
    'Maximum number of patrons that may select a particular curbside pickup time',
    'integer'
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'circ.curbside.disable_patron_input',
    'Disable patron modification of curbside appointments in public catalog',
    'circ',
    'When set to TRUE, patrons cannot use the My Account interface to select curbside pickup times',
    'bool'
);

INSERT INTO actor.org_unit_setting (org_unit, name, value)
    SELECT id, 'circ.curbside', 'false' FROM actor.org_unit WHERE parent_ou IS NULL
        UNION
    SELECT id, 'circ.curbside.max_concurrent', '10' FROM actor.org_unit WHERE parent_ou IS NULL
        UNION
    SELECT id, 'circ.curbside.granularity', '"15 minutes"' FROM actor.org_unit WHERE parent_ou IS NULL
;

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'hold.offer_curbside',
    'ahr',
    oils_i18n_gettext(
        'hold.offer_curbside',
        'Hook used to trigger the notification of an offer of curbside pickup',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'hold.confirm_curbside',
    'acsp',
    oils_i18n_gettext(
        'hold.confirm_curbside',
        'Hook used to trigger the notification of the creation or update of a curbside pickup appointment with an arrival URL',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.reactor (module, description) VALUES (
    'CurbsideSlot', 'Create a curbside pickup appointment slot when necessary'
);

INSERT INTO action_trigger.validator (module, description) VALUES (
    'Curbside', 'Confirm that curbside pickup is enabled for the hold pickup library'
);

------------------- Disabled example A/T defintions ------------------------------

-- Create a "dummy" slot when applicable, and trigger the "offer curbside" events
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay
) VALUES (
    'f',
    1,
    'Trigger curbside offer events and create a placeholder for the patron, where applicable',
    'hold.available',
    'Curbside',
    'CurbsideSlot',
    '00:30:00'
);

-- Email offer
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay,
    delay_field,
    group_field,
    template
) VALUES (
    'f',
    1,
    'Curbside offer Email notification, triggered by CurbsideSlot reactor on a definition attached to the hold.available hook',
    'hold.offer_curbside',
    'Curbside',
    'SendEmail',
    '00:00:00',
    'shelf_time',
    'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Curbside Pickup
Auto-Submitted: auto-generated

[% target.0.pickup_lib.name %] is now offering curbside delivery
service.  Please call [% target.0.pickup_lib.phone %] or visit the
link below to schedule a pickup time.

https://example.org/eg/opac/myopac/holds_curbside

Stay safe! Wash your hands!
$$);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'pickup_lib'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
);

INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (currval('action_trigger.event_definition_id_seq'), 'check_email_notify', 1);

-- SMS offer
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay,
    delay_field,
    group_field,
    template
) VALUES (
    false,
    1,
    'Curbside offer SMS notification, triggered by CurbsideSlot reactor on a definition attached to the hold.available hook',
    'hold.offer_curbside',
    'Curbside',
    'SendSMS',
    '00:00:00',
    'shelf_time',
    'sms_notify',
    $$[%- USE date -%]
[%- user = target.0.usr -%]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
To: [%- params.recipient_email || helpers.get_sms_gateway_email(target.0.sms_carrier,target.0.sms_notify) %]
Subject: Curbside Pickup
Auto-Submitted: auto-generated

[% target.0.pickup_lib.name %] offers curbside pickup.
Call [% target.0.pickup_lib.phone %] or visit https://example.org/eg/opac/myopac/holds_curbside
$$
);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'pickup_lib'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
);

INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (currval('action_trigger.event_definition_id_seq'), 'check_sms_notify', 1);

-- Email confirmation
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay,
    template
) VALUES (
    'f',
    1,
    'Curbside confirmation Email notification',
    'hold.confirm_curbside',
    'Curbside',
    'SendEmail',
    '00:00:00',
$$
[%- USE date -%]
[%- user = target.patron -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Curbside Pickup Confirmed
Auto-Submitted: auto-generated

This email is to confirm that you have scheduled a curbside item
pickup at [% target.org.name %] for [% date.format(helpers.format_date(target.slot), '%a, %d %b %Y %T') %].

You can cancel or change to your appointment, add vehicle description
notes, and alert staff to your arrival by going to the link below.

When you arrive, please call [% target.org.phone %] or visit the
link below to let us know you are here.

https://example.org/eg/opac/myopac/holds_curbside

Stay safe! Wash your hands!
$$);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'org'
), (
    currval('action_trigger.event_definition_id_seq'),
    'patron'
);

-- We do /not/ add this by default, treating curbside request as implicit opt-in
/*
INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (currval('action_trigger.event_definition_id_seq'), 'check_email_notify', 1);
*/

-- SMS confirmation
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay,
    template
) VALUES (
    false,
    1,
    'Curbside confirmation SMS notification',
    'hold.confirm_curbside',
    'Curbside',
    'SendSMS',
    '00:00:00',
    $$[%- USE date -%]
[%- user = target.patron -%]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
To: [%- params.recipient_email || helpers.get_sms_gateway_email(helpers.get_user_setting(user.id, 'opac.default_sms_carrier'), helpers.get_user_setting(user.id, 'opac.default_sms_notify')) %]
Subject: Curbside Pickup Confirmed
Auto-Submitted: auto-generated

Location: [% target.org.name %]
Time: [% date.format(helpers.format_date(target.slot), '%a, %d %b %Y %T') %]
Make changes at https://example.org/eg/opac/myopac/holds_curbside
$$
);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'org'
), (
    currval('action_trigger.event_definition_id_seq'),
    'patron'
);

-- We do /not/ add this by default, treating curbside request as implicit opt-in
/*
INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (currval('action_trigger.event_definition_id_seq'), 'check_sms_notify', 1);
*/


COMMIT;
