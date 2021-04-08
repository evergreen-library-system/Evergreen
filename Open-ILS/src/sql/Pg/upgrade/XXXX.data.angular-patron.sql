
BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version); 

/*
INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.catalog.results.count', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.catalog.results.count',
        'Catalog Results Page Size',
        'cwst', 'label'
    )
);

eg.circ.patron.holds.prefetch

eg.grid.circ.patron.holds

holds_for_patron print template
*/


-- insert then update for easier iterative development tweaks
INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('items_out', 'Patron Items Out', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  circulations = template_data.circulations;
%]
<div>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You have the following items:</div>
  <hr/>
  <ol>
  [% FOR checkout IN circulations %]
    <li>
      <div>[% checkout.title %]</div>
      <div>
      [% IF checkout.copy %]Barcode: [% checkout.copy.barcode %][% END %]
    Due: [% date.format(helpers.format_date(checkout.dueDate, staff_org_timezone), '%x %r') %]
      </div>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>[% staff_org.name %] [% date.format(date.now, '%x %r') %]</div>
  <div>You were helped by [% staff.first_given_name %]</div>
  <br/>
</div>
$TEMPLATE$ WHERE name = 'items_out';

UPDATE config.print_template SET active = TRUE WHERE name = 'patron_address';

-- insert then update for easier iterative development tweaks
INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('bills_current', 'Bills, Current', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  xacts = template_data.xacts;
%]
<div>
  <style>td { padding: 1px 3px 1px 3px; }</style>
  <div>Welcome to [% staff_org.name %]</div>
  <div>You have the following bills:</div>
  <hr/>
  <ol>
  [% FOR xact IN xacts %]
    <li>
      <table>
        <tr>
          <td>Bill #:</td>
          <td>[% xact.id %]</td>
        </tr>
        <tr>
          <td>Date:</td>
          <td>[% date.format(helpers.format_date(
            xact.xact_start, staff_org_timezone), '%x %r') %]
          </td>
        </tr>
        <tr>
          <td>Last Billing:</td>
          <td>[% xact.summary.last_billing_type %]</td>
        </tr>
        <tr>
          <td>Total Billed:</td>
          <td>[% money(xact.summary.total_owed) %]</td>
        </tr>
        <tr>
          <td>Last Payment:</td>
          <td>
            [% xact.summary.last_payment_type %]
            [% IF xact.summary.last_payment_ts %]
              at [% date.format(helpers.format_date(
                xact.summary.last_payment_ts, staff_org_timezone), '%x %r') %]
            [% END %]
          </td>
        </tr>
        <tr>
          <td>Total Paid:</td>
          <td>[% money(xact.summary.total_paid) %]</td>
        </tr>
        <tr>
          <td>Balance:</td>
          <td>[% money(xact.summary.balance_owed) %]</td>
        </tr>
      </table>
    </li>
  [% END %]
  </ol>
  <hr/>
  <div>[% staff_org.name %] [% date.format(date.now, '%x %r') %]</div>
  <div>You were helped by [% staff.first_given_name %]</div>
  <br/>
</div>
$TEMPLATE$ WHERE name = 'bills_current';


INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('bills_payment', 'Bills, Payment', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET payments = template_data.payments;
  SET previous_balance = template_data.previous_balance;
  SET new_balance = template_data.new_balance;
  SET payment_type = template_data.payment_type;
  SET payment_total = template_data.payment_total;
  SET payment_applied = template_data.payment_applied;
  SET amount_voided = template_data.amount_voided;
  SET change_given = template_data.change_given;
  SET payment_note = template_data.payment_note;
  SET copy_barcode = template_data.copy_barcode;
  SET title = template_data.title;
%]
<div>
  <style>td { padding: 1px 3px 1px 3px; }</style>
  <div>Welcome to [% staff_org.name %]</div>
  <div>A receipt of your transaction:</div>
  <hr/>

  <table style="width:100%"> 
    <tr> 
      <td>Original Balance:</td> 
      <td align="right">[% money(previous_balance) %]</td> 
    </tr> 
    <tr> 
      <td>Payment Method:</td> 
      <td align="right">
        [% SWITCH payment_type %]
          [% CASE "cash_payment" %]Cash
          [% CASE "check_payment" %]Check
          [% CASE "credit_card_payment" %]Credit Card
          [% CASE "debit_card_payment" %]Debit Card
          [% CASE "credit_payment" %]Patron Credit
          [% CASE "work_payment" %]Work
          [% CASE "forgive_payment" %]Forgive
          [% CASE "goods_payment" %]Goods
        [% END %]
      </td>
    </tr> 
    <tr> 
      <td>Payment Received:</td> 
      <td align="right">[% money(payment_total) %]</td> 
    </tr> 
    <tr> 
      <td>Payment Applied:</td> 
      <td align="right">[% money(payment_applied) %]</td> 
    </tr> 
    <tr> 
      <td>Billings Voided:</td> 
      <td align="right">[% money(amount_voided) %]</td> 
    </tr> 
    <tr> 
      <td>Change Given:</td> 
      <td align="right">[% money(change_given) %]</td> 
    </tr> 
    <tr> 
      <td>New Balance:</td> 
      <td align="right">[% money(new_balance) %]</td> 
    </tr> 
  </table> 
  <p>Note: [% payment_note %]</p>
  <p>
    Specific Bills
    <blockquote>
      [% FOR payment IN payments %]
        <table style="width:100%">
          <tr>
            <td>Bill # [% payment.xact.id %]</td>
            <td>[% payment.xact.summary.last_billing_type %]</td>
            <td>Received: [% money(payment.amount) %]</td>
          </tr>
          [% IF payment.copy_barcode %]
          <tr>
            <td colspan="5">[% payment.copy_barcode %] [% payment.title %]</td>
          </tr>
          [% END %]
        </table>
        <br/>
      [% END %]
    </blockquote>
  </p> 
  <hr/>
  <br/><br/> 
  <div>[% staff_org.name %] [% date.format(date.now, '%x %r') %]</div>
  <div>You were helped by [% staff.first_given_name %]</div>
</div>
$TEMPLATE$ WHERE name = 'bills_payment';


INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('patron_data', 'Patron Data', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[% 
  USE date;
  USE money = format('$%.2f');
  SET patron = template_data.patron;
%]
<table>
  <tr><td>Barcode:</td><td>[% patron.card.barcode %]</td></tr>
  <tr><td>Patron's Username:</td><td>[% patron.usrname %]</td></tr>
  <tr><td>Prefix/Title:</td><td>[% patron.prefix %]</td></tr>
  <tr><td>First Name:</td><td>[% patron.first_given_name %]</td></tr>
  <tr><td>Middle Name:</td><td>[% patron.second_given_name %]</td></tr>
  <tr><td>Last Name:</td><td>[% patron.family_name %]</td></tr>
  <tr><td>Suffix:</td><td>[% patron.suffix %]</td></tr>
  <tr><td>Holds Alias:</td><td>[% patron.alias %]</td></tr>
  <tr><td>Date of Birth:</td><td>[% patron.dob %]</td></tr>
  <tr><td>Juvenile:</td><td>[% patron.juvenile %]</td></tr>
  <tr><td>Primary Identification Type:</td><td>[% patron.ident_type.name %]</td></tr>
  <tr><td>Primary Identification:</td><td>[% patron.ident_value %]</td></tr>
  <tr><td>Secondary Identification Type:</td><td>[% patron.ident_type2.name %]</td></tr>
  <tr><td>Secondary Identification:</td><td>[% patron.ident_value2 %]</td></tr>
  <tr><td>Email Address:</td><td>[% patron.email %]</td></tr>
  <tr><td>Daytime Phone:</td><td>[% patron.day_phone %]</td></tr>
  <tr><td>Evening Phone:</td><td>[% patron.evening_phone %]</td></tr>
  <tr><td>Other Phone:</td><td>[% patron.other_phone %]</td></tr>
  <tr><td>Home Library:</td><td>[% patron.home_ou.name %]</td></tr>
  <tr><td>Main (Profile) Permission Group:</td><td>[% patron.profile.name %]</td></tr>
  <tr><td>Privilege Expiration Date:</td><td>[% patron.expire_date %]</td></tr>
  <tr><td>Internet Access Level:</td><td>[% patron.net_access_level.name %]</td></tr>
  <tr><td>Active:</td><td>[% patron.active %]</td></tr>
  <tr><td>Barred:</td><td>[% patron.barred %]</td></tr>
  <tr><td>Is Group Lead Account:</td><td>[% patron.master_account %]</td></tr>
  <tr><td>Claims-Returned Count:</td><td>[% patron.claims_returned_count %]</td></tr>
  <tr><td>Claims-Never-Checked-Out Count:</td><td>[% patron.claims_never_checked_out_count %]</td></tr>
  <tr><td>Alert Message:</td><td>[% patron.alert_message %]</td></tr>

  [% FOR addr IN patron.addresses %]
    <tr><td colspan="2">----------</td></tr>
    <tr><td>Type:</td><td>[% addr.address_type %]</td></tr>
    <tr><td>Street (1):</td><td>[% addr.street1 %]</td></tr>
    <tr><td>Street (2):</td><td>[% addr.street2 %]</td></tr>
    <tr><td>City:</td><td>[% addr.city %]</td></tr>
    <tr><td>County:</td><td>[% addr.county %]</td></tr>
    <tr><td>State:</td><td>[% addr.state %]</td></tr>
    <tr><td>Postal Code:</td><td>[% addr.post_code %]</td></tr>
    <tr><td>Country:</td><td>[% addr.country %]</td></tr>
    <tr><td>Valid Address?:</td><td>[% addr.valid %]</td></tr>
    <tr><td>Within City Limits?:</td><td>[% addr.within_city_limits %]</td></tr>
  [% END %]

  [% FOR entry IN patron.stat_cat_entries %]
    <tr><td>-----------</td></tr>
    <tr><td>[% entry.stat_cat.name %]</td><td>[% entry.stat_cat_entry %]</td></tr>
  [% END %]

</table>

$TEMPLATE$ WHERE name = 'patron_data';

COMMIT;


