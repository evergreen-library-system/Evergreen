BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0460'); -- dbs

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES
        ('circ.holds.recall_threshold',
        oils_i18n_gettext( 'circ.holds.recall_threshold',
            'Recalls: Circulation duration that triggers a recall.', 'coust', 'label'),
        oils_i18n_gettext( 'circ.holds.recall_threshold',
            'Recalls: A hold placed on an item with a circulation duration longer than this will trigger a recall. For example, "14 days" or "3 weeks".', 'coust', 'description'),
        'interval')
;

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES
        ('circ.holds.recall_return_interval',
        oils_i18n_gettext( 'circ.holds.recall_return_interval',
            'Recalls: Truncated loan period.', 'coust', 'label'),
        oils_i18n_gettext( 'circ.holds.recall_return_interval',
            'Recalls: When a recall is triggered, this defines the adjusted loan period for the item. For example, "4 days" or "1 week".', 'coust', 'description'),
        'interval')
;

INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
    VALUES
        ('circ.holds.recall_fine_rules',
        oils_i18n_gettext( 'circ.holds.recall_fine_rules',
            'Recalls: An array of fine amount, fine interval, and maximum fine.', 'coust', 'label'),
        oils_i18n_gettext( 'circ.holds.recall_fine_rules',
            'Recalls: An array of fine amount, fine interval, and maximum fine. For example, to specify a new fine rule of $5.00 per day, with a maximum fine of $50.00, use: [5.00,"1 day",50.00]', 'coust', 'description'),
        'array')
;

INSERT INTO action_trigger.hook (key,core_type,description)
    VALUES ('circ.recall.target', 'circ', 'A checked-out copy has been recalled for a hold.');

INSERT INTO action_trigger.event_definition (id, owner, name, hook, validator, reactor, group_field, template)
    VALUES (37, 1, 'Item Recall Email Notice', 'circ.recall.target', 'NOOP_True', 'SendEmail', 'usr', 
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Item Recall Notification 

Dear [% user.family_name %], [% user.first_given_name %]

The following item which you have checked out has been recalled so that
another patron can have access to the item:

[% FOR circ IN target %]
    Title: [% circ.target_copy.call_number.record.simple_record.title %] 
    Barcode: [% circ.target_copy.barcode %] 
    Now Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Library: [% circ.circ_lib.name %]

    If this item is not returned by the new due date, fines will be assessed at
    the rate of [% circ.recurring_fine %] every [% circ.fine_interval %].
[% END %]
$$
);

INSERT INTO action_trigger.environment (event_def, path) VALUES
    (37, 'target_copy.call_number.record.simple_record'),
    (37, 'usr'),
    (37, 'circ_lib.billing_address')
;

COMMIT;
