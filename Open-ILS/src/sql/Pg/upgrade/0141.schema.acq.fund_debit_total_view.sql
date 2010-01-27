BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0141'); -- Scott McKellar

CREATE OR REPLACE VIEW acq.fund_debit_total AS
    SELECT  fund.id AS fund,
            fund_debit.encumbrance AS encumbrance,
            COALESCE( SUM(fund_debit.amount), 0 ) AS amount
      FROM acq.fund AS fund
			LEFT JOIN acq.fund_debit AS fund_debit
				ON ( fund.id = fund_debit.fund )
      GROUP BY 1,2;

COMMIT;
