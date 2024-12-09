BEGIN;
-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1445', :eg_version);

UPDATE action_trigger.event_definition
SET template =
$$

[%- USE date -%][%- SET user = target.0.xact.usr -%]
<div style="font-family: Arial, Helvetica, sans-serif;">

   <!-- Header aligned left -->
   <div style="text-align:left;">
       <span style="padding-top:1em;">[% date.format %]</span>
    </div><br/>

     [% SET grand_total = 0.00 %]
    <ol>
    [% SET xact_mp_hash = {} %]
    [% FOR mp IN target %][%# Create an array of transactions/amount paid for each payment made %]
        [% SET xact_id = mp.xact.id %]
        [% SET amount = mp.amount %]
        [% IF ! xact_mp_hash.defined( xact_id ) %]
           [% xact_mp_hash.$xact_id = { 'xact' => mp.xact, 'payment' => amount } %]
        [% END %]
    [% END %]

    [% FOR xact_id IN xact_mp_hash.keys.sort %]
        [% SET xact = xact_mp_hash.$xact_id.xact %]
        <li>
          Transaction ID: [% xact_mp_hash.$xact_id.xact.id %]<br />
          [% IF xact.circulation %]
             Title: "[% helpers.get_copy_bib_basics(xact.circulation.target_copy).title %]" <br />
          [% END %]

           [%# Go get all the date needed from xact_summary %]

           [% SET mbts = xact.summary %]

           Transaction Type: [% mbts.last_billing_type%]<br />
           Date: [% mbts.last_billing_ts %] <br />

           Note: [% mbts.last_billing_note %] <br />

           Amount: $[% xact_mp_hash.$xact_id.payment | format("%.2f") %]
           [% grand_total = grand_total + xact_mp_hash.$xact_id.payment %]
        </li>
        <br />
    [% END %]
    </ol>

    <div> <!-- Summary of all the information -->
       Payment Type: [% SWITCH mp.payment_type -%]
                    [% CASE "cash_payment" %]Cash
                    [% CASE "check_payment" %]Check
                    [% CASE "credit_card_payment" %]Credit Card
                    [%- IF mp.credit_card_payment.cc_number %] ([% mp.credit_card_payment.cc_number %])[% END %]
                    [% CASE "debit_card_payment" %]Debit Card
                    [% CASE "credit_payment" %]Credit
                    [% CASE "forgive_payment" %]Forgiveness
                    [% CASE "goods_payment" %]Goods
                    [% CASE "work_payment" %]Work
                [%- END %] <br />
       Total:<strong> $[% grand_total | format("%.2f") %] </strong>
    </div>

</div>
$$
WHERE id = 30 AND template =
$$

[%- USE date -%][%- SET user = target.0.xact.usr -%]
<div style="font-family: Arial, Helvetica, sans-serif;">

   <!-- Header aligned left -->
   <div style="text-align:left;">
       <span style="padding-top:1em;">[% date.format %]</span>
    </div><br/>

     [% SET grand_total = 0.00 %]
    <ol>
    [% SET xact_mp_hash = {} %]
    [% FOR mp IN target %][%# Create an array of transactions/amount paid for each payment made %]
        [% SET xact_id = mp.xact.id %]
        [% SET amount = mp.amount %]
        [% IF ! xact_mp_hash.defined( xact_id ) %]
           [% xact_mp_hash.$xact_id = { 'xact' => mp.xact, 'payment' => amount } %]
        [% END %]
    [% END %]

    [% FOR xact_id IN xact_mp_hash.keys.sort %]
        [% SET xact = xact_mp_hash.$xact_id.xact %]
        <li>
          Transaction ID: [% xact_mp_hash.$xact_id.xact.id %]<br />
          [% IF xact.circulation %]
             Title: "[% helpers.get_copy_bib_basics(xact.circulation.target_copy).title %]" <br />
          [% END %]

           [%# Go get all the date needed from xact_summary %]

           [% SET mbts = xact.summary %]

           Transaction Type: [% mbts.last_billing_type%]<br />
           Date: [% mbts.last_billing_ts %] <br />

           Note: [% mbts.last_billing_note %] <br />

           Amount: $[% xact_mp_hash.$xact_id.payment | format("%.2f") %]
           [% grand_total = grand_total + xact_mp_hash.$xact_id.payment %]
        </li>
        <br />
    [% END %]
    </ol>

    <div> <!-- Summary of all the information -->
       Payment Type: Credit Card <br />
       Total:<strong> $[% grand_total | format("%.2f") %] </strong>
    </div>

</div>
$$;

COMMIT;
