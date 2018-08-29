BEGIN;
    -- SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

    ALTER TABLE config.rule_circ_duration
    ADD column max_auto_renewals INTEGER;

    ALTER TABLE action.circulation
    ADD column auto_renewal BOOLEAN;

    ALTER TABLE action.circulation
    ADD column auto_renewal_remaining INTEGER;

    INSERT INTO action_trigger.validator values('CircIsAutoRenewable', 'Checks whether the circulation is able to be autorenewed.');
    INSERT INTO action_trigger.reactor values('Circ::AutoRenew', 'Auto-Renews a circulation.');
    INSERT INTO action_trigger.hook(key, core_type, description) values('autorenewal', 'circ', 'Item was auto-renewed to patron.');

    -- AutoRenewer A/T Def: 
    INSERT INTO action_trigger.event_definition(active, owner, name, hook, validator, reactor, delay, max_delay, delay_field, group_field)
        values (false, 1, 'Autorenew', 'checkout.due', 'CircIsOpen', 'Circ::AutoRenew', '-23 hours'::interval,'-1 minute'::interval, 'due_date', 'usr');

    -- AutoRenewal outcome Email notifier A/T Def:
    INSERT INTO action_trigger.event_definition(active, owner, name, hook, validator, reactor, group_field, template)
        values (false, 1, 'AutorenewNotify', 'autorenewal', 'NOOP_True', 'SendEmail', 'usr', 
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Items Out Auto-Renewal Notification 
Auto-Submitted: auto-generated

Dear [% user.family_name %], [% user.first_given_name %]
An automatic renewal attempt was made for the following items:

[% FOR circ IN target %]
    [%- SET idx = loop.count - 1; SET udata =  user_data.$idx -%]
    [%- SET cid = circ.target_copy || udata.copy -%]
    [%- SET copy_details = helpers.get_copy_bib_basics(cid) -%]
    Item# [% loop.count %]
    Title: [% copy_details.title %]
    Author: [% copy_details.author %]
    [%- IF udata.is_renewed %]
    Status: Loan Renewed
    New Due Date: [% date.format(helpers.format_date(udata.new_due_date), '%Y-%m-%d') %]
    [%- ELSE %]
    Status: Not Renewed
    Reason: [% udata.reason %]
    Due Date: [% date.format(helpers.format_date(circ.due_date), '%Y-%m-%d') %]
    [% END %]
[% END %]
$$
    );

    INSERT INTO action_trigger.environment (event_def, path ) VALUES
    ( currval('action_trigger.event_definition_id_seq'), 'usr' ),
    ( currval('action_trigger.event_definition_id_seq'), 'circ_lib' );

COMMIT;
