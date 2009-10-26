BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0054');

-- Sample Pre-due Notice --

INSERT INTO action_trigger.event_definition (id, active, owner, name, hook, validator, reactor, delay, delay_field, group_field, template) 
    VALUES (6, 'f', 1, '3 Day Courtesy Notice', 'checkout.due', 'CircIsOpen', 'SendEmail', '-3 days', 'due_date', 'usr', 
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Courtesy Notice

Dear [% user.family_name %], [% user.first_given_name %]
As a reminder, the following items are due in 3 days.

[% FOR circ IN target %]
    Title: [% circ.target_copy.call_number.record.simple_record.title %] 
    Barcode: [% circ.target_copy.barcode %] 
    Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Item Cost: [% helpers.get_copy_price(circ.target_copy) %]
    Library: [% circ.circ_lib.name %]
    Library Phone: [% circ.circ_lib.phone %]
[% END %]

$$);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
    (6, 'target_copy.call_number.record.simple_record'),
    (6, 'usr'),
    (6, 'circ_lib.billing_address');

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
    (6, 'max_delay_age', '"1 day"');

-- also add the max delay age to the default overdue notice event def
INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
    (1, 'max_delay_age', '"1 day"');
  
COMMIT;
