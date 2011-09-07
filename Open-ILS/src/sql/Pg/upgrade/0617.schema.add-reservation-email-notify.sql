BEGIN;

SELECT evergreen.upgrade_deps_block_check('0617', :eg_version);

-- add notify columns to booking.reservation
ALTER TABLE booking.reservation
  ADD COLUMN email_notify BOOLEAN NOT NULL DEFAULT FALSE;

-- create the hook and validator
INSERT INTO action_trigger.hook (key, core_type, description, passive)
  VALUES ('reservation.available', 'bresv', 'A reservation is available for pickup', false);
INSERT INTO action_trigger.validator (module, description)
  VALUES ('ReservationIsAvailable','Checked that a reserved resource is available for checkout');

-- create org unit setting to toggle checkbox display
INSERT INTO config.org_unit_setting_type (name, label, description, datatype)
  VALUES ('booking.allow_email_notify', 'booking.allow_email_notify', 'Permit email notification when a reservation is ready for pickup.', 'bool');

COMMIT;
