-- Evergreen DB patch 0565.schema.action-trigger.event_definition.hold-cancel-no-target-notification.sql
--
-- New action trigger event definition: Hold Cancelled (No Target) Email Notification
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0565', :eg_version);

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, delay_field, group_field, template)
    VALUES (38, FALSE, 1, 
        'Hold Cancelled (No Target) Email Notification', 
        'hold_request.cancel.expire_no_target', 
        'HoldIsCancelled', 'SendEmail', '30 minutes', 'cancel_time', 'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Hold Request Cancelled

Dear [% user.family_name %], [% user.first_given_name %]
The following holds were cancelled because no items were found to fullfil the hold.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
    Library: [% hold.pickup_lib.name %]
    Request Date: [% date.format(helpers.format_date(hold.rrequest_time), '%Y-%m-%d') %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (38, 'usr'),
    (38, 'pickup_lib'),
    (38, 'bib_rec.bib_record.simple_record');

COMMIT;
