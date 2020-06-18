BEGIN;

SELECT evergreen.upgrade_deps_block_check('1205', :eg_version);

INSERT INTO config.print_template 
    (id, name, locale, active, owner, label, template) 
VALUES (
    3, 'booking_capture', 'en-US', TRUE,
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    oils_i18n_gettext(3, 'Booking capture slip', 'cpt', 'label'),
$TEMPLATE$
[%-
    USE date;
    SET data = template_data;
    # template_data is data returned from open-ils.booking.resources.capture_for_reservation.
-%]
<div>
  [% IF data.transit;
       dest_ou = helpers.get_org_unit(data.transit.dest);
  %]
  <div>This item need to be routed to <strong>[% dest_ou.shortname %]</strong></div>
  [% ELSE %]
  <div>This item need to be routed to <strong>RESERVATION SHELF:</strong></div>
  [% END %]
  <div>Barcode: [% data.reservation.current_resource.barcode %]</div>
  <div>Title: [% data.reservation.current_resource.type.name %]</div>
  <div>Note: [% data.reservation.note %]</div>
  <br/>
  <p><strong>Reserved for patron</strong> [% data.reservation.usr.family_name %], [% data.reservation.usr.first_given_name %] [% data.reservation.usr.second_given_name %]
  <br/>Barcode: [% data.reservation.usr.card.barcode %]</p>
  <p>Request time: [% date.format(helpers.format_date(data.reservation.request_time, client_timezone), '%x %r', locale) %]
  <br/>Reserved from:
    [% date.format(helpers.format_date(data.reservation.start_time, client_timezone), '%x %r', locale) %]
    - [% date.format(helpers.format_date(data.reservation.end_time, client_timezone), '%x %r', locale) %]</p>
  <p>Slip date: [% date.format(helpers.current_date(client_timezone), '%x %r', locale) %]<br/>
  Printed by [% data.staff.family_name %], [% data.staff.first_given_name %] [% data.staff.second_given_name %]
    at [% data.workstation %]</p>
</div>
<br/>

$TEMPLATE$
);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.booking.captured', 'gui', 'object',
    oils_i18n_gettext(
        'booking.manage',
        'Grid Config: Booking Captured Reservations',
        'cwst', 'label')
);


COMMIT;
