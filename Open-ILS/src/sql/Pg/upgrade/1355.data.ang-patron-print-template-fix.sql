BEGIN;

SELECT evergreen.upgrade_deps_block_check('1355', :eg_version); 


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

$TEMPLATE$ WHERE name = 'patron_data' AND template = $TEMPLATE$
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

$TEMPLATE$;

COMMIT;
