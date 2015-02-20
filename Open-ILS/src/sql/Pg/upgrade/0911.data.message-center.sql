BEGIN;

SELECT evergreen.upgrade_deps_block_check('0911', :eg_version);

-- Auto-cancelled, no target
INSERT INTO action_trigger.event_definition (
    id, active, owner, name, hook,
    validator, reactor, delay, delay_field,
    group_field, message_usr_path, message_library_path, message_title,
    message_template
) VALUES (
    51, FALSE, 1, 'Hold Cancelled (No Target) User Message', 'hold_request.cancel.expire_no_target',
    'HoldIsCancelled', 'NOOP_True', '30 minutes', 'cancel_time',
    'usr', 'usr', 'usr.home_ou', 'Hold Request Cancelled',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
The following holds were cancelled because no items were found to fullfil them.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
    Library: [% hold.pickup_lib.name %]
    Request Date: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (51, 'usr'),
    (51, 'pickup_lib'),
    (51, 'bib_rec.bib_record.simple_record');


-- Cancelled by staff
INSERT INTO action_trigger.event_definition (
    id, active, owner, name, hook,
    validator, reactor, delay, delay_field,
    group_field, message_usr_path, message_library_path, message_title,
    message_template
) VALUES (
    52, FALSE, 1, 'Hold Cancelled (Staff) User Message', 'hold_request.cancel.staff',
    'HoldIsCancelled', 'NOOP_True', '30 minutes', 'cancel_time',
    'usr', 'usr', 'usr.home_ou', 'Hold Request Cancelled',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
The following holds were cancelled by a staff member.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
    Library: [% hold.pickup_lib.name %]
    Request Date: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]
    Cancellation Note: [% hold.cancel_note %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (52, 'usr'),
    (52, 'pickup_lib'),
    (52, 'bib_rec.bib_record.simple_record');


-- Shelf expired
INSERT INTO action_trigger.event_definition (
    id, active, owner, name, hook,
    validator, reactor, delay, delay_field,
    group_field, message_usr_path, message_library_path, message_title,
    message_template
) VALUES (
    53, TRUE, 1, 'Hold Cancelled (Shelf-Expired) User Message', 'hold_request.cancel.expire_holds_shelf',
    'HoldIsCancelled', 'NOOP_True', '30 minutes', 'cancel_time',
    'usr', 'usr', 'usr.home_ou', 'Hold Request Cancelled',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
The following holds were cancelled because they were never picked up.

[% FOR hold IN target %]
    Title: [% hold.bib_rec.bib_record.simple_record.title %]
    Author: [% hold.bib_rec.bib_record.simple_record.author %]
    Library: [% hold.pickup_lib.name %]
    Request Date: [% date.format(helpers.format_date(hold.request_time), '%Y-%m-%d') %]
    Pickup By: [% date.format(helpers.format_date(hold.shelf_expire_time), '%Y-%m-%d') %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (53, 'usr'),
    (53, 'pickup_lib'),
    (53, 'bib_rec.bib_record.simple_record');

COMMIT;

