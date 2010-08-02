BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0356'); -- miker

ALTER TABLE acq.edi_account DROP CONSTRAINT acq_edi_account_id_unique;
ALTER TABLE acq.edi_account ADD CONSTRAINT PRIMARY KEY (id);
 
DROP INDEX money.money_mat_summary_id_idx;
ALTER TABLE money.materialized_billable_xact_summary ADD CONSTRAINT PRIMARY KEY (id);

ALTER TABLE staging.billing_address_stage ADD CONSTRAINT PRIMARY KEY (row_id);

COMMIT;

