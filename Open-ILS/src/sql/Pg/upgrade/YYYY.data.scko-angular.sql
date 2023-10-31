
BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('TODO', :eg_version); 

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('scko_items_out', 'Self-Checkout Items Out', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[%- 
    USE date;
    SET user = template_data.user;
    SET checkouts = template_data.checkouts;
-%]
<div>
  <style> li { padding: 8px; margin 5px; }</style>
  <div>[% date.format(date.now, '%x %r') %]</div>
  <br/>

  [% user.pref_family_name || user.family_name %], 
  [% user.pref_first_given_name || user.first_given_name %]

  <ol>
  [% FOR checkout IN checkouts %]
    <li>
      <div>[% checkout.title %]</div>
      <div>Barcode: [% checkout.copy.barcode %]</div>
      <div>Due Date: [% 
        date.format(helpers.format_date(
            checkout.circ.due_date, staff_org_timezone), '%x %r') 
      %]
      </div>
    </li>
  [% END %]
  </ol>
</div>
$TEMPLATE$ WHERE name = 'scko_items_out';

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('scko_holds', 'Self-Checkout Holds', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[%- 
    USE date;
    SET user = template_data.user;
    SET holds = template_data.holds;
-%]
<div>
  <style> li { padding: 8px; margin 5px; }</style>
  <div>[% date.format(date.now, '%x %r') %]</div>
  <br/>

  [% user.pref_family_name || user.family_name %], 
  [% user.pref_first_given_name || user.first_given_name %]

  <ol>
  [% FOR hold IN holds %]
    <li>
      <table>
        <tr>
          <td>Title:</td>
          <td>[% hold.title %]</td>
        </tr>
        <tr>
          <td>Author:</td>
          <td>[% hold.author %]</td>
        </tr>
        <tr>
          <td>Pickup Location:</td>
          <td>[% helpers.get_org_unit(hold.pickup_lib).name %]</td>
        </tr>
        <tr>
          <td>Status:</td>
          <td>
            [%- IF hold.ready -%]
                Ready for pickup
            [% ELSE %]
                #[% hold.relative_queue_position %] of [% hold.potentials %] copies.
            [% END %]
          </td>
        </tr>
      </table>
    </li>
  [% END %]
  </ol>
</div>
$TEMPLATE$ WHERE name = 'scko_holds';

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('scko_fines', 'Self-Checkout Fines', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[%- 
    USE date;
    USE money = format('$%.2f');
    SET user = template_data.user;
    SET xacts = template_data.xacts;
-%]
<div>
  <style> li { padding: 8px; margin 5px; }</style>
  <div>[% date.format(date.now, '%x %r') %]</div>
  <br/>

  [% user.pref_family_name || user.family_name %], 
  [% user.pref_first_given_name || user.first_given_name %]

  <ol>
  [% FOR xact IN xacts %]
    [% NEXT IF xact.balance_owed <= 0 %]
    <li>
      <table>
        <tr>
          <td>Details:</td>
          <td>[% xact.details %]</td>
        </tr>
        <tr>
          <td>Total Billed:</td>
          <td>[% money(xact.total_owed) %]</td>
        </tr>
        <tr>
          <td>Total Paid:</td>
          <td>[% money(xact.total_paid) %]</td>
        </tr>
        <tr>
          <td>Balance Owed:</td>
          <td>[% money(xact.balance_owed) %]</td>
        </tr>
      </table>
    </li>
  [% END %]
  </ol>
</div>
$TEMPLATE$ WHERE name = 'scko_fines';

INSERT INTO config.print_template 
    (name, label, owner, active, locale, content_type, template)
VALUES ('scko_checkouts', 'Self-Checkout Checkouts', 1, TRUE, 'en-US', 'text/html', '');

UPDATE config.print_template SET template = $TEMPLATE$
[%- 
    USE date;
    SET user = template_data.user;
    SET checkouts = template_data.checkouts;
    SET lib = staff_org;
    SET hours = lib.hours_of_operation;
    SET lib_addr = staff_org.billing_address || staff_org.mailing_address;
-%]
<div>
  <style> li { padding: 8px; margin 5px; }</style>
  <div>[% date.format(date.now, '%x %r') %]</div>
  <div>[% lib.name %]</div>
  <div>[% lib_addr.street1 %] [% lib_addr.street2 %]</div>
  <div>[% lib_addr.city %], [% lib_addr.state %] [% lib_addr.post_code %]</div>
  <div>[% lib.phone %]</div>
  <br/>

  [% user.pref_family_name || user.family_name %], 
  [% user.pref_first_given_name || user.first_given_name %]

  <ol>
  [% FOR checkout IN checkouts %]
    <li>
      <div>[% checkout.title %]</div>
      <div>Barcode: [% checkout.barcode %]</div>

      [% IF checkout.ctx.renewalFailure %]
      <div style="color:red;">Renewal Failed</div>
      [% END %]

      <div>Due Date: [% date.format(helpers.format_date(
        checkout.circ.due_date, staff_org_timezone), '%x') %]</div>
    </li>
  [% END %]
  </ol>

  <div>
    Library Hours
    [%- 
        BLOCK format_time;
          IF time;
            date.format(time _ ' 1/1/1000', format='%I:%M %p');
          END;
        END
    -%]
    <div>
      Monday 
      [% PROCESS format_time time = hours.dow_0_open %] 
      [% PROCESS format_time time = hours.dow_0_close %] 
    </div>
    <div>
      Tuesday 
      [% PROCESS format_time time = hours.dow_1_open %] 
      [% PROCESS format_time time = hours.dow_1_close %] 
    </div>
    <div>
      Wednesday 
      [% PROCESS format_time time = hours.dow_2_open %] 
      [% PROCESS format_time time = hours.dow_2_close %] 
    </div>
    <div>
      Thursday
      [% PROCESS format_time time = hours.dow_3_open %] 
      [% PROCESS format_time time = hours.dow_3_close %] 
    </div>
    <div>
      Friday
      [% PROCESS format_time time = hours.dow_4_open %] 
      [% PROCESS format_time time = hours.dow_4_close %] 
    </div>
    <div>
      Saturday
      [% PROCESS format_time time = hours.dow_5_open %] 
      [% PROCESS format_time time = hours.dow_5_close %] 
    </div>
    <div>
      Sunday 
      [% PROCESS format_time time = hours.dow_6_open %] 
      [% PROCESS format_time time = hours.dow_6_close %] 
    </div>
  </div>

</div>
$TEMPLATE$ WHERE name = 'scko_checkouts';


COMMIT;


