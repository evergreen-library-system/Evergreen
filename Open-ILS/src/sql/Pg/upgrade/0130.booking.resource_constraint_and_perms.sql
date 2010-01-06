BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0130'); -- senator

ALTER TABLE booking.resource DROP CONSTRAINT br_unique;
ALTER TABLE booking.resource ADD CONSTRAINT br_unique UNIQUE (owner, barcode);

INSERT into permission.perm_list VALUES
    (360, 'RETRIEVE_RESERVATION_PULL_LIST', oils_i18n_gettext(360, 'Allows a user to retrieve a booking reservation pull list', 'ppl', 'description')),
    (361, 'CAPTURE_RESERVATION', oils_i18n_gettext(361, 'Allows a user to capture booking reservations', 'ppl', 'description')) ; 

COMMIT;
