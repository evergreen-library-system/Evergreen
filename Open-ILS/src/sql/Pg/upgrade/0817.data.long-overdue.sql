BEGIN;

-- NOTE: very IDs are still correct for perms and event_def data at merge.

SELECT evergreen.upgrade_deps_block_check('0817', :eg_version);

-- copy status

INSERT INTO config.copy_status
    (id, name, holdable, opac_visible, copy_active, restrict_copy_delete)
    VALUES (16, oils_i18n_gettext(16, 'Long Overdue', 'ccs', 'name'), 'f', 'f', 'f', 't');

-- checkin override perm

INSERT INTO permission.perm_list (id, code, description) VALUES (
    549, -- VERIFY
    'COPY_STATUS_LONGOVERDUE.override',
    oils_i18n_gettext(
        549, -- VERIFY
        'Allows the user to check-in long-overdue items, prompting ' ||
            'long-overdue check-in processing',
        'ppl',
        'code'
    )
), (
    550, -- VERIFY
    'SET_CIRC_LONG_OVERDUE',
    oils_i18n_gettext(
        550, -- VERIFY
        'Allows the user to mark a circulation as long-overdue',
        'ppl',
        'code'
    )
);

-- billing types

INSERT INTO config.billing_type (id, owner, name) VALUES
    (10, 1, oils_i18n_gettext(
        10, 'Long-Overdue Materials', 'cbt', 'name')),
    (11, 1, oils_i18n_gettext(
        11, 'Long-Overdue Materials Processing Fee', 'cbt', 'name'));

-- org settings

INSERT INTO config.org_unit_setting_type 
    (name, grp, datatype, label, description) VALUES 
(
    'circ.longoverdue_immediately_available',
    'circ', 'bool',
    oils_i18n_gettext(
        'circ.longoverdue_immediately_available',
        'Long-Overdue Items Usable on Checkin',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.longoverdue_immediately_available',
        'Long-overdue items are usable on checkin instead of going "home" first',
        'coust',
        'description'
    )
), (
    'circ.longoverdue_materials_processing_fee',
    'finance', 'currency',
    oils_i18n_gettext(
        'circ.longoverdue_materials_processing_fee',
        'Long-Overdue Materials Processing Fee',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.longoverdue_materials_processing_fee',
        'Long-Overdue Materials Processing Fee',
        'coust',
        'description'
    )
), (
    'circ.max_accept_return_of_longoverdue',
    'circ', 'interval',
    oils_i18n_gettext(
        'circ.max_accept_return_of_longoverdue',
        'Long-Overdue Max Return Interval',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.max_accept_return_of_longoverdue',
        'Long-overdue check-in processing (voiding fees, re-instating ' ||
            'overdues, etc.) will not take place for items that have been ' ||
            'overdue for (or have last activity older than) this amount of time',
        'coust',
        'description'
    )
), (
    'circ.restore_overdue_on_longoverdue_return',
    'circ', 'bool',
    oils_i18n_gettext(
        'circ.restore_overdue_on_longoverdue_return',
        'Restore Overdues on Long-Overdue Item Return',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.restore_overdue_on_longoverdue_return',
        'Restore Overdues on Long-Overdue Item Return',
        'coust',
        'description'
    )
), (
    'circ.void_longoverdue_on_checkin',
    'circ', 'bool',
    oils_i18n_gettext(
        'circ.void_longoverdue_on_checkin',
        'Void Long-Overdue Item Billing When Returned',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.void_longoverdue_on_checkin',
        'Void Long-Overdue Item Billing When Returned',
        'coust',
        'description'
    )
), (
    'circ.void_longoverdue_proc_fee_on_checkin',
    'circ', 'bool',
    oils_i18n_gettext(
        'circ.void_longoverdue_proc_fee_on_checkin',
        'Void Processing Fee on Long-Overdue Item Return',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.void_longoverdue_proc_fee_on_checkin',
        'Void Processing Fee on Long-Overdue Item Return',
        'coust',
        'description'
    )
), (
    'circ.void_overdue_on_longoverdue',
    'finance', 'bool',
    oils_i18n_gettext(
        'circ.void_overdue_on_longoverdue',
        'Void Overdue Fines When Items are Marked Long-Overdue',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.void_overdue_on_longoverdue',
        'Void Overdue Fines When Items are Marked Long-Overdue',
        'coust',
        'description'
    )
), (
    'circ.longoverdue.xact_open_on_zero',
    'finance', 'bool',
    oils_i18n_gettext(
        'circ.longoverdue.xact_open_on_zero',
        'Leave transaction open when long overdue balance equals zero',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.longoverdue.xact_open_on_zero',
        'Leave transaction open when long-overdue balance equals zero.  ' ||
            'This leaves the lost copy on the patron record when it is paid',
        'coust',
        'description'
    )
), (
    'circ.longoverdue.use_last_activity_date_on_return',
    'circ', 'bool',
    oils_i18n_gettext(
        'circ.longoverdue.use_last_activity_date_on_return',
        'Long-Overdue Check-In Interval Uses Last Activity Date',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.longoverdue.use_last_activity_date_on_return',
        'Use the long-overdue last-activity date instead of the due_date to ' ||
            'determine whether the item has been checked out too long to ' ||
            'perform long-overdue check-in processing.  If set, the system ' ||
            'will first check the last payment time, followed by the last ' ||
            'billing time, followed by the due date.  See also ' ||
            'circ.max_accept_return_of_longoverdue',
        'coust',
        'description'
    )
);

-- mark long-overdue reactor

INSERT INTO action_trigger.reactor (module, description) VALUES
(   'MarkItemLongOverdue',
    oils_i18n_gettext(
        'MarkItemLongOverdue',
        'Marks a circulating item as long-overdue and applies configured ' ||
        'penalties.  Also creates events for the longoverdue.auto hook',
        'atreact',
        'description'
    )
);

INSERT INTO action_trigger.validator (module, description) VALUES (
    'PatronNotInCollections', 
    'Event is valid if the linked patron is not in collections processing ' ||
        'at the context org unit'
);

-- VERIFY ID
INSERT INTO action_trigger.event_definition 
    (id, active, owner, name, hook, validator, reactor, delay, delay_field) 
VALUES ( 
    49, FALSE, 1, '6 Month Overdue Mark Long-Overdue', 
    'checkout.due', 'PatronNotInCollections', 
    'MarkItemLongOverdue', '6 months', 'due_date'
);

-- VERIFY ID
INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
    (49, 'editor', '''1'''); 

-- new longoverdue and longervdue.auto hook.

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'longoverdue',
    'circ',
    'Circulating Item marked long-overdue'
);

INSERT INTO action_trigger.hook (key,core_type,description) VALUES (
    'longoverdue.auto',
    'circ',
    'Circulating Item automatically marked long-overdue'
);

-- sample longoverdue.auto notification reactor

-- VERIFY ID
INSERT INTO action_trigger.event_definition 
    (id, active, owner, name, hook, validator, reactor, group_field, template) 
    VALUES ( 
        50, FALSE, 1, '6 Month Long Overdue Notice', 
        'longoverdue.auto', 'NOOP_True', 'SendEmail', 'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Overdue Items Marked Long Overdue

Dear [% user.family_name %], [% user.first_given_name %]
The following items are 6 months overdue and have been marked Long Overdue.

[% FOR circ IN target %]
    [%- copy_details = helpers.get_copy_bib_basics(circ.target_copy.id) -%]
    Title: [% copy_details.title %], by [% copy_details.author %]
    Call Number: [% circ.target_copy.call_number.label %]
    Shelving Location: [% circ.target_copy.location.name %]
    Barcode: [% circ.target_copy.barcode %]
    Due: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    Item Cost: [% helpers.get_copy_price(circ.target_copy) %]
    Total Owed For Transaction: [% circ.billable_transaction.summary.balance_owed %]
    Library: [% circ.circ_lib.name %]

[% END %]
$$);

-- ENV for above

-- VERIFY IDs
INSERT INTO action_trigger.environment (event_def, path) VALUES 
    (50, 'target_copy.call_number'),
    (50, 'usr'),
    (50, 'billable_transaction.summary'),
    (50, 'circ_lib.billing_address'),
    (50, 'target_copy.location');


--ROLLBACK;
COMMIT;
