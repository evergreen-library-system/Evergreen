BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0242'); -- Scott McKellar

ALTER TABLE acq.cancel_reason
	ADD COLUMN keep_debits BOOL NOT NULL DEFAULT FALSE;

INSERT INTO acq.cancel_reason ( id, org_unit, label, description, keep_debits ) VALUES (
    3, 1, 'delivered_but_lost',
    oils_i18n_gettext( 2, 'Delivered but not received; presumed lost', 'acqcr', 'label' ), TRUE );

COMMIT;
