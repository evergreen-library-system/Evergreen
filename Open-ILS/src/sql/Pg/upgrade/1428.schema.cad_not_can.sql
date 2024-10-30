BEGIN;

SELECT evergreen.upgrade_deps_block_check('1428', :eg_version);

ALTER TABLE acq.exchange_rate 
	DROP CONSTRAINT exchange_rate_from_currency_fkey
	,ADD CONSTRAINT exchange_rate_from_currency_fkey FOREIGN KEY (from_currency) REFERENCES acq.currency_type (code) ON UPDATE CASCADE;

ALTER TABLE acq.exchange_rate 
	DROP CONSTRAINT exchange_rate_to_currency_fkey
	,ADD CONSTRAINT exchange_rate_to_currency_fkey FOREIGN KEY (to_currency) REFERENCES acq.currency_type (code) ON UPDATE CASCADE;

ALTER TABLE acq.funding_source
    DROP CONSTRAINT funding_source_currency_type_fkey
    ,ADD CONSTRAINT funding_source_currency_type_fkey FOREIGN KEY (currency_type) REFERENCES acq.currency_type (code) ON UPDATE CASCADE;

UPDATE acq.fund_debit SET origin_currency_type ='CAD' WHERE origin_currency_type = 'CAN';
UPDATE acq.provider SET currency_type ='CAD' WHERE currency_type = 'CAN';
UPDATE acq.currency_type SET code = 'CAD' WHERE code = 'CAN';

COMMIT;
