BEGIN;

-- Replaces and augments some of the data from 0289.data.payment_receipt_format.sql
INSERT INTO config.upgrade_log (version) VALUES ('0326'); -- phasefx

UPDATE action_trigger.event_definition SET template =
$$
[%- USE date -%]
[%- SET user = target.0.xact.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Subject: Payment Receipt

[% date.format -%]
[%- SET xact_mp_hash = {} -%]
[%- FOR mp IN target %][%# Template is hooked around payments, but let us make the receipt focused on transactions -%]
    [%- SET xact_id = mp.xact.id -%]
    [%- IF ! xact_mp_hash.defined( xact_id ) -%][%- xact_mp_hash.$xact_id = { 'xact' => mp.xact, 'payments' => [] } -%][%- END -%]
    [%- xact_mp_hash.$xact_id.payments.push(mp) -%]
[%- END -%]
[%- FOR xact_id IN xact_mp_hash.keys.sort -%]
    [%- SET xact = xact_mp_hash.$xact_id.xact %]
Transaction ID: [% xact_id %]
    [% IF xact.circulation %][% helpers.get_copy_bib_basics(xact.circulation.target_copy).title %]
    [% ELSE %]Miscellaneous
    [% END %]
    Line item billings:
        [%- SET mb_type_hash = {} -%]
        [%- FOR mb IN xact.billings %][%# Group billings by their btype -%]
            [%- IF mb.voided == 'f' -%]
                [%- SET mb_type = mb.btype.id -%]
                [%- IF ! mb_type_hash.defined( mb_type ) -%][%- mb_type_hash.$mb_type = { 'sum' => 0.00, 'billings' => [] } -%][%- END -%]
                [%- IF ! mb_type_hash.$mb_type.defined( 'first_ts' ) -%][%- mb_type_hash.$mb_type.first_ts = mb.billing_ts -%][%- END -%]
                [%- mb_type_hash.$mb_type.last_ts = mb.billing_ts -%]
                [%- mb_type_hash.$mb_type.sum = mb_type_hash.$mb_type.sum + mb.amount -%]
                [%- mb_type_hash.$mb_type.billings.push( mb ) -%]
            [%- END -%]
        [%- END -%]
        [%- FOR mb_type IN mb_type_hash.keys.sort -%]
            [%- IF mb_type == 1 %][%-# Consolidated view of overdue billings -%]
                $[% mb_type_hash.$mb_type.sum %] for [% mb_type_hash.$mb_type.billings.0.btype.name %] 
                    on [% mb_type_hash.$mb_type.first_ts %] through [% mb_type_hash.$mb_type.last_ts %]
            [%- ELSE -%][%# all other billings show individually %]
                [% FOR mb IN mb_type_hash.$mb_type.billings %]
                    $[% mb.amount %] for [% mb.btype.name %] on [% mb.billing_ts %] [% mb.note %]
                [% END %]
            [% END %]
        [% END %]
    Line item payments:
        [% FOR mp IN xact_mp_hash.$xact_id.payments %]
            Payment ID: [% mp.id %]
                Paid [% mp.amount %] via [% SWITCH mp.payment_type -%]
                    [% CASE "cash_payment" %]cash
                    [% CASE "check_payment" %]check
                    [% CASE "credit_card_payment" %]credit card (
                        [%- SET cc_chunks = mp.credit_card_payment.cc_number.replace(' ','').chunk(4); -%]
                        [%- cc_chunks.slice(0, -1+cc_chunks.max).join.replace('\S','X') -%] 
                        [% cc_chunks.last -%]
                        exp [% mp.credit_card_payment.expire_month %]/[% mp.credit_card_payment.expire_year -%]
                    )
                    [% CASE "credit_payment" %]credit
                    [% CASE "forgive_payment" %]forgiveness
                    [% CASE "goods_payment" %]goods
                    [% CASE "work_payment" %]work
                [%- END %] on [% mp.payment_ts %] [% mp.note %]
        [% END %]
[% END %]
$$
WHERE id = 29;

UPDATE action_trigger.event_definition SET template =
$$
[%- USE date -%][%- SET user = target.0.xact.usr -%]
<div style="li { padding: 8px; margin 5px; }">
    <div>[% date.format %]</div><br/>
    <ol>
    [% SET xact_mp_hash = {} %]
    [% FOR mp IN target %][%# Template is hooked around payments, but let us make the receipt focused on transactions %]
        [% SET xact_id = mp.xact.id %]
        [% IF ! xact_mp_hash.defined( xact_id ) %][% xact_mp_hash.$xact_id = { 'xact' => mp.xact, 'payments' => [] } %][% END %]
        [% xact_mp_hash.$xact_id.payments.push(mp) %]
    [% END %]
    [% FOR xact_id IN xact_mp_hash.keys.sort %]
        [% SET xact = xact_mp_hash.$xact_id.xact %]
        <li>Transaction ID: [% xact_id %]
            [% IF xact.circulation %][% helpers.get_copy_bib_basics(xact.circulation.target_copy).title %]
            [% ELSE %]Miscellaneous
            [% END %]
            Line item billings:<ol>
                [% SET mb_type_hash = {} %]
                [% FOR mb IN xact.billings %][%# Group billings by their btype %]
                    [% IF mb.voided == 'f' %]
                        [% SET mb_type = mb.btype.id %]
                        [% IF ! mb_type_hash.defined( mb_type ) %][% mb_type_hash.$mb_type = { 'sum' => 0.00, 'billings' => [] } %][% END %]
                        [% IF ! mb_type_hash.$mb_type.defined( 'first_ts' ) %][% mb_type_hash.$mb_type.first_ts = mb.billing_ts %][% END %]
                        [% mb_type_hash.$mb_type.last_ts = mb.billing_ts %]
                        [% mb_type_hash.$mb_type.sum = mb_type_hash.$mb_type.sum + mb.amount %]
                        [% mb_type_hash.$mb_type.billings.push( mb ) %]
                    [% END %]
                [% END %]
                [% FOR mb_type IN mb_type_hash.keys.sort %]
                    <li>[% IF mb_type == 1 %][%# Consolidated view of overdue billings %]
                        $[% mb_type_hash.$mb_type.sum %] for [% mb_type_hash.$mb_type.billings.0.btype.name %] 
                            on [% mb_type_hash.$mb_type.first_ts %] through [% mb_type_hash.$mb_type.last_ts %]
                    [% ELSE %][%# all other billings show individually %]
                        [% FOR mb IN mb_type_hash.$mb_type.billings %]
                            $[% mb.amount %] for [% mb.btype.name %] on [% mb.billing_ts %] [% mb.note %]
                        [% END %]
                    [% END %]</li>
                [% END %]
            </ol>
            Line item payments:<ol>
                [% FOR mp IN xact_mp_hash.$xact_id.payments %]
                    <li>Payment ID: [% mp.id %]
                        Paid [% mp.amount %] via [% SWITCH mp.payment_type -%]
                            [% CASE "cash_payment" %]cash
                            [% CASE "check_payment" %]check
                            [% CASE "credit_card_payment" %]credit card (
                                [%- SET cc_chunks = mp.credit_card_payment.cc_number.replace(' ','').chunk(4); -%]
                                [%- cc_chunks.slice(0, -1+cc_chunks.max).join.replace('\S','X') -%] 
                                [% cc_chunks.last -%]
                                exp [% mp.credit_card_payment.expire_month %]/[% mp.credit_card_payment.expire_year -%]
                            )
                            [% CASE "credit_payment" %]credit
                            [% CASE "forgive_payment" %]forgiveness
                            [% CASE "goods_payment" %]goods
                            [% CASE "work_payment" %]work
                        [%- END %] on [% mp.payment_ts %] [% mp.note %]
                    </li>
                [% END %]
            </ol>
        </li>
    [% END %]
    </ol>
</div>
$$
WHERE id = 30;

INSERT INTO action_trigger.environment (
        event_def,
        path
    ) VALUES -- for fleshing mp objects
         ( 29, 'credit_card_payment')
        ,( 29, 'xact.billings')
        ,( 29, 'xact.billings.btype')
        ,( 30, 'credit_card_payment')
        ,( 30, 'xact.billings')
        ,( 30, 'xact.billings.btype')
;

COMMIT;

