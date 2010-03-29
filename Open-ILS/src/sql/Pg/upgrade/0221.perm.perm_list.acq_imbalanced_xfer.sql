BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0221'); -- senator

INSERT INTO permission.perm_list (id, code, description)
    VALUES (389, 'ACQ_XFER_MANUAL_DFUND_AMOUNT',
	oils_i18n_gettext( 389, 'Allow a user to transfer different amounts of money out of one fund and into another', 'ppl', 'description' ));

COMMIT;
