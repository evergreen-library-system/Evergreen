BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0289'); -- phasefx

INSERT INTO action_trigger.hook (key,core_type,description,passive) VALUES (
        'money.format.payment_receipt.email',
        'mp', 
        oils_i18n_gettext(
            'money.format.payment_receipt.email',
            'An email has been requested for a payment receipt.',
            'ath',
            'description'
        ), 
        FALSE
    )
    ,(
        'money.format.payment_receipt.print',
        'mp', 
        oils_i18n_gettext(
            'money.format.payment_receipt.print',
            'A payment receipt needs to be formatted for printing.',
            'ath',
            'description'
        ), 
        FALSE
    )
;

INSERT INTO action_trigger.event_definition (
        id,
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        group_field,
        granularity,
        template
    ) VALUES (
        29,
        TRUE,
        1,
        'money.payment_receipt.email',
        'money.format.payment_receipt.email',
        'NOOP_True',
        'SendEmail',
        'xact.usr',
        NULL,
$$
[%- USE date -%]
[%- SET user = target.0.xact.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Payment Receipt

    [% FOR mp IN target %]
            Payment ID: [% mp.id %]
            Paid [% mp.amount %] via [% SWITCH mp.payment_type %]
                [% CASE "cash_payment" %]cash
                [% CASE "check_payment" %]check
                [% CASE "credit_card_payment" %]credit card
                [% CASE "credit_payment" %]credit
                [% CASE "forgive_payment" %]forgiveness
                [% CASE "goods_payment" %]goods
                [% CASE "work_payment" %]work
            [% END %] on [% mp.payment_ts %] for
            [% IF mp.xact.circulation %]
                [% helpers.get_copy_bib_basics(mp.xact.circulation.target_copy).title %]
            [% ELSE %]
                grocery
            [% END %]
    [% END %]
$$
    )
    ,(
        30,
        TRUE,
        1,
        'money.payment_receipt.print',
        'money.format.payment_receipt.print',
        'NOOP_True',
        'ProcessTemplate',
        'xact.usr',
        'print-on-demand',
$$
[%- USE date -%]
[%- SET user = target.0.xact.usr -%]
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <div>[% date.format %]</div>
    <br/>

    <ol>
    [% FOR mp IN target %]
        <li>
            Payment ID: [% mp.id %]
            Paid [% mp.amount %] via [% SWITCH mp.payment_type %]
                [% CASE "cash_payment" %]cash
                [% CASE "check_payment" %]check
                [% CASE "credit_card_payment" %]credit card
                [% CASE "credit_payment" %]credit
                [% CASE "forgive_payment" %]forgiveness
                [% CASE "goods_payment" %]goods
                [% CASE "work_payment" %]work
            [% END %] on [% mp.payment_ts %] for
            [% IF mp.xact.circulation %]
                [% helpers.get_copy_bib_basics(mp.xact.circulation.target_copy).title %]
            [% ELSE %]
                grocery
            [% END %]
        </li>
    [% END %]
    </ol>
</div>
$$
    )
;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES -- for fleshing mp objects
         ( 29, 'xact')
        ,( 29, 'xact.usr')
        ,( 29, 'xact.grocery' )
        ,( 29, 'xact.circulation' )
        ,( 29, 'xact.summary' )
        ,( 30, 'xact')
        ,( 30, 'xact.usr')
        ,( 30, 'xact.grocery' )
        ,( 30, 'xact.circulation' )
        ,( 30, 'xact.summary' )
;

-- DELETE FROM action_trigger.environment WHERE event_def IN (29,30); DELETE FROM action_trigger.event where event_def IN (29,30); DELETE FROM action_trigger.event_definition WHERE id IN (29,30); DELETE FROM action_trigger.hook WHERE key IN ('money.format.payment_receipt.email','money.format.payment_receipt.print'); DELETE FROM config.upgrade_log WHERE version = '0289'; -- from testing, this sql will remove these events, etc.

COMMIT;

