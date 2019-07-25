BEGIN;

ALTER TABLE booking.reservation
    ADD COLUMN note TEXT;

COMMIT;
