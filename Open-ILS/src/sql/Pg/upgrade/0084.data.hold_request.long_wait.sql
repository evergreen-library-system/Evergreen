BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0084'); -- senator

INSERT INTO action_trigger.hook (
        key,
        core_type,
        description,
        passive
    ) VALUES (
        'hold_request.long_wait',
        'ahr',
        'A patron has been waiting on a hold to be fulfilled for a long time.',
        TRUE
    );

INSERT INTO action_trigger.event_definition (
        id,
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
        9,
        FALSE,
        1,
        'Hold waiting for pickup for long time',
        'hold_request.long_wait',
        'NOOP_True',
        'SendEmail',
        '6 MONTHS',
        'request_time',
        'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Long Wait Hold Notification

Dear [% user.family_name %], [% user.first_given_name %]

You requested hold(s) on the following item(s), but unfortunately
we have not been able to fulfill your request after a considerable
length of time.  If you would still like to recieve these items,
no action is required.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
[% END %]
$$
);

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES
    (9, 'pickup_lib'),
    (9, 'usr'),
    (9, 'bib_rec.bib_record.simple_record');


COMMIT;
