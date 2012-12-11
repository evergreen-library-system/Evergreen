BEGIN;

-- Build the event defintions, environment, and params, then apply the same 
-- template to all CSV definitions.

-- All definitions assume a notify media of "V" (voice).

---------------------------------------------------
-- 1st overdue 
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', '1st Overdue CSV', 1, 'checkout.due','CircIsOverdue', 
    'ProcessTemplate', '7 days', 'due_date', 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'circ_lib'), 
(currval('action_trigger.event_definition_id_seq'), 'target_copy'), 
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '1'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''OVERDUE''')
;

---------------------------------------------------
-- 2nd overdue 
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', '2nd Overdue CSV', 1, 'checkout.due','CircIsOverdue', 
    'ProcessTemplate', '14 days', 'due_date', 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'circ_lib'), 
(currval('action_trigger.event_definition_id_seq'), 'target_copy'), 
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '2'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''OVERDUE''')
;

---------------------------------------------------
-- 3rd overdue 
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', '3rd Overdue CSV', 1, 'checkout.due','CircIsOverdue', 
    'ProcessTemplate', '28 days', 'due_date', 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'circ_lib'), 
(currval('action_trigger.event_definition_id_seq'), 'target_copy'), 
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '3'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''OVERDUE''')
;

---------------------------------------------------
-- predue 
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', '3-Day Predue CSV', 1, 'checkout.due','CircIsOpen', 
    'ProcessTemplate', '-3 days', 'due_date', 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'circ_lib'), 
(currval('action_trigger.event_definition_id_seq'), 'target_copy'), 
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '1'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''PREOVERDUE''')
;

---------------------------------------------------
-- hold ready for pickup 
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', 'Hold Ready CSV', 1, 'hold.available','HoldIsAvailable', 
    'ProcessTemplate', '30 minutes', 'shelf_time', 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'pickup_lib'), 
(currval('action_trigger.event_definition_id_seq'), 'current_copy'), 
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '1'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''RESERVE''')
;

---------------------------------------------------
-- hold expires on shelf soon
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', 'Hold Expires On Shelf Soon CSV', 1, 
    'hold_request.shelf_expires_soon',
    'HoldIsAvailable', 'ProcessTemplate', '-1 days', 
    'shelf_expire_time', 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'pickup_lib'), 
(currval('action_trigger.event_definition_id_seq'), 'current_copy'), 
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '2'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''PRERESERVE''')
;

---------------------------------------------------
-- hold expired on shelf
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', 'Hold Expired On Shelf CSV', 1, 
    'hold_request.cancel.expire_holds_shelf',
    'HoldIsCancelled', 'ProcessTemplate', '30 minutes', 
    'cancel_time', 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'pickup_lib'), 
(currval('action_trigger.event_definition_id_seq'), 'current_copy'),
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '1'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''RESERVEEXPIRE''')
;

---------------------------------------------------
-- hold cancelled
-- see also hooks hold_request.cancel.staff and
-- hold_request.cancel.patron
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', 'Hold Cancelled (no target) CSV', 1, 
    'hold_request.cancel.expire_no_target',
    'HoldIsCancelled', 'ProcessTemplate', '30 minutes', 
    'cancel_time', 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'pickup_lib'), 
(currval('action_trigger.event_definition_id_seq'), 'current_copy'),
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '1'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''RESERVECANCEL''')
;

---------------------------------------------------
-- recall
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', 'Copy Recall CSV', 1, 
    'circ.recall.target',
    'NOOP_True', 'ProcessTemplate', DEFAULT,
    NULL, 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'circ_lib'), 
(currval('action_trigger.event_definition_id_seq'), 'target_copy'), 
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '1'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''RECALL''')
;

---------------------------------------------------
-- patron exceeds fines threshold
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', 'Patron Exceeds Fines CSV', 1, 
    'penalty.PATRON_EXCEEDS_FINES',
    'NOOP_True', 'ProcessTemplate', DEFAULT,
    NULL, 'usr', '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'org_unit'),
(currval('action_trigger.event_definition_id_seq'), 'usr.card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '1'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''FINES''')
;

---------------------------------------------------
-- patron barred
INSERT INTO action_trigger.event_definition (active, name, owner, hook, 
    validator, reactor, delay, delay_field, group_field, template, granularity)
VALUES (
    'f', 'Patron Barred CSV', 1, 
    'au.barred',
    'PatronBarred', 'ProcessTemplate', DEFAULT,
    NULL, NULL, '', 'notify-csv'
);

INSERT INTO action_trigger.environment (event_def, path) VALUES 
(currval('action_trigger.event_definition_id_seq'), 'home_ou'),
(currval('action_trigger.event_definition_id_seq'), 'card')
;

INSERT INTO action_trigger.event_params (event_def, param, value) VALUES
(currval('action_trigger.event_definition_id_seq'), 'notify_media', '''V'''),
(currval('action_trigger.event_definition_id_seq'), 'notify_level', '1'),
(currval('action_trigger.event_definition_id_seq'), 'notify_type', '''SUSPEND''')
;



---------------------------------------------------
-- apply the generic CVS template to all event defs
UPDATE action_trigger.event_definition SET template = $$
[%-
    USE date;

    # accommodate grouped events
    SET event = event.0 UNLESS event.id;
    SET target = [target] UNLESS event.event_def.group_field;

    core_type = event.event_def.hook.core_type;
    notice_org_unit = helpers.get_org_unit(event.event_def.owner);

    FOR target_obj IN target;

        # Mangle the data into a consistent shape
        circ = '';
        hold = '';
        copy = '';
        user = '';
        title = '';
        org_unit = '';
        date_info = '';

        IF core_type == 'circ';
            # e.g. overdue circ
            circ = target_obj;
            user = circ.usr;
            copy = circ.target_copy;
            org_unit = circ.circ_lib;
            date_info = circ.due_date;

        ELSIF core_type == 'ahr';
            # e.g. hold ready for pickup
            hold = target_obj;
            user = hold.usr;
            copy = hold.current_copy;
            org_unit = hold.pickup_lib;
            date_info = hold.shelf_expire_time;

        ELSIF core_type == 'ausp';
            # e.g. max fines
            user = target_obj.usr;
            org_unit = target_obj.org_unit;

        ELSIF core_type == 'au';
            # e.g. barred
            user = target_obj;
            org_unit = user.home_ou;
        END;

        user_locale = helpers.get_user_locale(user.id);
        user_lang = user_locale | replace('-.*', ''); # ISO 639-1 language
        user_phone = helpers.get_user_setting(
            user.id, 'opac.default_phone') || user.day_phone;

        IF copy;
            bib_data = helpers.get_copy_bib_basics(copy.id);
            title = bib_data.title;
        END;

        IF date_info;
            date_info = date.format(
                helpers.format_date(date_info), '%d/%m/%Y');
        END;

        # Print the data for each target object as CSV
-%]
[%- '"' _ helpers.escape_csv(params.notify_media) _ '",' -%]
[%- '"' _ helpers.escape_csv(user_lang) _ '",' -%]
[%- '"' _ helpers.escape_csv(params.notify_type) _ '",' -%]
[%- '"' _ helpers.escape_csv(params.notify_level) _ '",' -%]
[%- '"' _ helpers.escape_csv(user.card.barcode) _ '",' -%]
[%- '"' _ helpers.escape_csv(user.prefix) _ '",' -%]
[%- '"' _ helpers.escape_csv(user.first_given_name) _ '",' -%]
[%- '"' _ helpers.escape_csv(user.family_name) _ '",' -%]
[%- '"' _ helpers.escape_csv(user_phone) _ '",' -%]
[%- '"' _ helpers.escape_csv(user.email) _ '",' -%]
[%- '"' _ helpers.escape_csv(notice_org_unit.shortname) _ '",' -%]
[%- '"' _ helpers.escape_csv(org_unit.shortname) _ '",' -%]
[%- '"' _ helpers.escape_csv(org_unit.name) _ '",' -%]
[%- '"' _ helpers.escape_csv(copy.barcode) _ '",' -%]
[%- '"' _ helpers.escape_csv(date_info) _ '",' -%]
[%- '"' _ helpers.escape_csv(title) _ '",' -%]
[%- '"' _ helpers.escape_csv(event.id) _ '"'  %]
[% END -%]
$$
WHERE granularity = 'notify-csv';

COMMIT;
