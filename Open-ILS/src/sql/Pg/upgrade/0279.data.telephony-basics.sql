BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0279'); -- atz / senator

INSERT INTO
    config.org_unit_setting_type (name, label, description, datatype)
    VALUES (
        'notice.telephony.callfile_lines',
        'Telephony: Arbitrary line(s) to include in each notice callfile',
        $$
        This overrides lines from opensrf.xml.
        Line(s) must be valid for your target server and platform
        (e.g. Asterisk 1.4).
        $$,
        'string'
    );

INSERT INTO action_trigger.reactor (module, description) VALUES (
    'AstCall', 'Possibly place a phone call with Asterisk'
);

INSERT INTO
    action_trigger.event_definition (
        id, active, owner, name, hook, validator, reactor,
        cleanup_success, cleanup_failure, delay, delay_field, group_field,
        max_delay, granularity, usr_field, opt_in_setting, template
    ) VALUES (
        24,
        FALSE,
        1,
        'Telephone Overdue Notice',
        'checkout.due', 'NOOP_True', 'AstCall',
        DEFAULT, DEFAULT, '5 seconds', 'due_date', 'usr',
        DEFAULT, DEFAULT, DEFAULT, DEFAULT,
        $$
[% phone = target.0.usr.day_phone | replace('[\s\-\(\)]', '') -%]
[% IF phone.match('^[2-9]') %][% country = 1 %][% ELSE %][% country = '' %][% END -%]
Channel: [% channel_prefix %]/[% country %][% phone %]
Context: overdue-test
MaxRetries: 1
RetryTime: 60
WaitTime: 30
Extension: 10
Archive: 1
Set: eg_user_id=[% target.0.usr.id %]
Set: items=[% target.size %]
Set: titlestring=[% titles = [] %][% FOR circ IN target %][% titles.push(circ.target_copy.call_number.record.simple_record.title) %][% END %][% titles.join(". ") %]
$$
    );

INSERT INTO
    action_trigger.environment (id, event_def, path)
    VALUES
        (DEFAULT, 24, 'target_copy.call_number.record.simple_record'),
        (DEFAULT, 24, 'usr')
    ;

COMMIT;
