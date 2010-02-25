BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0173'); -- Scott McKellar

-- For each fund: the total allocation from all sources, in the
-- currency of the fund (or 0 if there are no allocations)

CREATE VIEW acq.all_fund_allocation_total AS
SELECT
    f.id AS fund,
    COALESCE( SUM( a.amount * acq.exchange_ratio(
        s.currency_type, f.currency_type))::numeric(100,2), 0 )
    AS amount
FROM
    acq.fund f
        LEFT JOIN acq.fund_allocation a
            ON a.fund = f.id
        LEFT JOIN acq.funding_source s
            ON a.funding_source = s.id
GROUP BY
    f.id;

-- For every fund: the total encumbrances (or 0 if none),
-- in the currency of the fund.

CREATE VIEW acq.all_fund_encumbrance_total AS
SELECT
	f.id AS fund,
	COALESCE( encumb.amount, 0 ) AS amount
FROM
	acq.fund AS f
		LEFT JOIN (
			SELECT
				fund,
				sum( amount ) AS amount
			FROM
				acq.fund_debit
			WHERE
				encumbrance
			GROUP BY fund
		) AS encumb
			ON f.id = encumb.fund;

-- For every fund: the total spent (or 0 if none),
-- in the currency of the fund.

CREATE VIEW acq.all_fund_spent_total AS
SELECT
    f.id AS fund,
    COALESCE( spent.amount, 0 ) AS amount
FROM
    acq.fund AS f
        LEFT JOIN (
            SELECT
                fund,
                sum( amount ) AS amount
            FROM
                acq.fund_debit
            WHERE
                NOT encumbrance
            GROUP BY fund
        ) AS spent
            ON f.id = spent.fund;

-- For each fund: the amount not yet spent, in the currency
-- of the fund.  May include encumbrances.

CREATE VIEW acq.all_fund_spent_balance AS
SELECT
	c.fund,
	c.amount - d.amount AS amount
FROM acq.all_fund_allocation_total c
    LEFT JOIN acq.all_fund_spent_total d USING (fund);

-- For each fund: the amount neither spent nor encumbered,
-- in the currency of the fund

CREATE VIEW acq.all_fund_combined_balance AS
SELECT
     a.fund,
     a.amount - COALESCE( c.amount, 0 ) AS amount
FROM
     acq.all_fund_allocation_total a
        LEFT OUTER JOIN (
            SELECT
                fund,
                SUM( amount ) AS amount
            FROM
                acq.fund_debit
            GROUP BY
                fund
        ) AS c USING ( fund );

COMMIT;
