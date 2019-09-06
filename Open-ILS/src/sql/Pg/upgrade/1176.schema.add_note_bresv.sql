BEGIN;

SELECT evergreen.upgrade_deps_block_check('1176', :eg_version);

ALTER TABLE booking.reservation
    ADD COLUMN note TEXT;

COMMIT;
