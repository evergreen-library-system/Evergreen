BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0180'); -- Scott McKellar

INSERT INTO acq.cancel_reason ( id, org_unit, label, description ) VALUES (
	1, 1, 'invalid_isbn', oils_i18n_gettext( 1, 'ISBN is unrecognizable', 'acqcr', 'label' ));

INSERT INTO acq.cancel_reason ( id, org_unit, label, description ) VALUES (
	2, 1, 'postpone', oils_i18n_gettext( 2, 'Title has been postponed', 'acqcr', 'label' ));

INSERT INTO permission.perm_list (id, code, description)
    VALUES (365, 'ADMIN_ACQ_CANCEL_CAUSE', 
	oils_i18n_gettext( 365, 'Allow a user to create/update/delete reasons for order cancellations', 'ppl', 'description' ));

COMMIT;
