BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0356'); -- miker

ALTER TABLE acq.edi_account ADD PRIMARY KEY (id);
ALTER TABLE acq.edi_account DROP CONSTRAINT acq_edi_account_id_unique CASCADE;

-- Now rebuild the constraints dropped via cascade.
ALTER TABLE acq.provider    ADD CONSTRAINT provider_edi_default_fkey FOREIGN KEY (edi_default) REFERENCES acq.edi_account (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE acq.edi_message ADD CONSTRAINT edi_message_account_fkey  FOREIGN KEY (account    ) REFERENCES acq.edi_account (id) DEFERRABLE INITIALLY DEFERRED;
 
DROP INDEX money.money_mat_summary_id_idx;
ALTER TABLE money.materialized_billable_xact_summary ADD PRIMARY KEY (id);

ALTER TABLE staging.billing_address_stage ADD PRIMARY KEY (row_id);

COMMIT;

