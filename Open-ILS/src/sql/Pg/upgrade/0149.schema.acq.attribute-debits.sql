BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0149'); -- Scott McKellar

CREATE OR REPLACE FUNCTION acq.attribute_debits() RETURNS VOID AS $$
/*
Function to attribute expenditures and encumbrances to funding source credits,
and thereby to funding sources.

Read the debits in chonological order, attributing each one to one or
more funding source credits.  Constraints:

1. Don't attribute more to a credit than the amount of the credit.

2. For a given fund, don't attribute more to a funding source than the
source has allocated to that fund.

3. Attribute debits to credits with deadlines before attributing them to
credits without deadlines.  Otherwise attribute to the earliest credits
first, based on the deadline date when present, or on the effective date
when there is no deadline.  Use funding_source_credit.id as a tie-breaker.
This ordering is defined by an ORDER BY clause on the view
acq.ordered_funding_source_credit.

Start by truncating the table acq.debit_attribution.  Then insert a row
into that table for each attribution.  If a debit cannot be fully
attributed, insert a row for the unattributable balance, with the 
funding_source_credit and credit_amount columns NULL.
*/
DECLARE
	curr_fund_source_bal RECORD;
	seqno                INT;     -- sequence num for credits applicable to a fund
	fund_credit          RECORD;  -- current row in temp t_fund_credit table
	fc                   RECORD;  -- used for loading t_fund_credit table
	sc                   RECORD;  -- used for loading t_fund_credit table
	--
	-- Used exclusively in the main loop:
	--
	deb                 RECORD;   -- current row from acq.fund_debit table
	curr_credit_bal     RECORD;   -- current row from temp t_credit table
	debit_balance       NUMERIC;  -- amount left to attribute for current debit
	conv_debit_balance  NUMERIC;  -- debit balance in currency of the fund
	attr_amount         NUMERIC;  -- amount being attributed, in currency of debit
	conv_attr_amount    NUMERIC;  -- amount being attributed, in currency of source
	conv_cred_balance   NUMERIC;  -- credit_balance in the currency of the fund
	conv_alloc_balance  NUMERIC;  -- allocated balance in the currency of the fund
	attrib_count        INT;      -- populates id of acq.debit_attribution
BEGIN
	--
	-- Load a temporary table.  For each combination of fund and funding source,
	-- load an entry with the total amount allocated to that fund by that source.
	-- This sum may reflect transfers as well as original allocations.  We will
	-- reduce this balance whenever we attribute debits to it.
	--
	CREATE TEMP TABLE t_fund_source_bal
	ON COMMIT DROP AS
		SELECT
			fund AS fund,
			funding_source AS source,
			sum( amount ) AS balance
		FROM
			acq.fund_allocation
		GROUP BY
			fund,
			funding_source
		HAVING
			sum( amount ) > 0;
	--
	CREATE INDEX t_fund_source_bal_idx
		ON t_fund_source_bal( fund, source );
	-------------------------------------------------------------------------------
	--
	-- Load another temporary table.  For each fund, load zero or more
	-- funding source credits from which that fund can get money.
	--
	CREATE TEMP TABLE t_fund_credit (
		fund        INT,
		seq         INT,
		credit      INT
	) ON COMMIT DROP;
	--
	FOR fc IN
		SELECT DISTINCT fund
		FROM acq.fund_allocation
		ORDER BY fund
	LOOP                  -- Loop over the funds
		seqno := 1;
		FOR sc IN
			SELECT
				ofsc.id
			FROM
				acq.ordered_funding_source_credit AS ofsc
			WHERE
				ofsc.funding_source IN
				(
					SELECT funding_source
					FROM acq.fund_allocation
					WHERE fund = fc.fund
				)
    		ORDER BY
    		    ofsc.sort_priority,
    		    ofsc.sort_date,
    		    ofsc.id
		LOOP                        -- Add each credit to the list
			INSERT INTO t_fund_credit (
				fund,
				seq,
				credit
			) VALUES (
				fc.fund,
				seqno,
				sc.id
			);
			--RAISE NOTICE 'Fund % credit %', fc.fund, sc.id;
			seqno := seqno + 1;
		END LOOP;     -- Loop over credits for a given fund
	END LOOP;         -- Loop over funds
	--
	CREATE INDEX t_fund_credit_idx
		ON t_fund_credit( fund, seq );
	-------------------------------------------------------------------------------
	--
	-- Load yet another temporary table.  This one is a list of funding source
	-- credits, with their balances.  We shall reduce those balances as we
	-- attribute debits to them.
	--
	CREATE TEMP TABLE t_credit
	ON COMMIT DROP AS
        SELECT
            fsc.id AS credit,
            fsc.funding_source AS source,
            fsc.amount AS balance,
            fs.currency_type AS currency_type
        FROM
            acq.funding_source_credit AS fsc,
            acq.funding_source fs
        WHERE
            fsc.funding_source = fs.id
			AND fsc.amount > 0;
	--
	CREATE INDEX t_credit_idx
		ON t_credit( credit );
	--
	-------------------------------------------------------------------------------
	--
	-- Now that we have loaded the lookup tables: loop through the debits,
	-- attributing each one to one or more funding source credits.
	-- 
	truncate table acq.debit_attribution;
	--
	attrib_count := 0;
	FOR deb in
		SELECT
			fd.id,
			fd.fund,
			fd.amount,
			f.currency_type,
			fd.encumbrance
		FROM
			acq.fund_debit fd,
			acq.fund f
		WHERE
			fd.fund = f.id
		ORDER BY
			fd.id
	LOOP
		--RAISE NOTICE 'Debit %, fund %', deb.id, deb.fund;
		--
		debit_balance := deb.amount;
		--
		-- Loop over the funding source credits that are eligible
		-- to pay for this debit
		--
		FOR fund_credit IN
			SELECT
				credit
			FROM
				t_fund_credit
			WHERE
				fund = deb.fund
			ORDER BY
				seq
		LOOP
			--RAISE NOTICE '   Examining credit %', fund_credit.credit;
			--
			-- Look up the balance for this credit.  If it's zero, then
			-- it's not useful, so treat it as if you didn't find it.
			-- (Actually there shouldn't be any zero balances in the table,
			-- but we check just to make sure.)
			--
			SELECT *
			INTO curr_credit_bal
			FROM t_credit
			WHERE
				credit = fund_credit.credit
				AND balance > 0;
			--
			IF curr_credit_bal IS NULL THEN
				--
				-- This credit is exhausted; try the next one.
				--
				CONTINUE;
			END IF;
			--
			--
			-- At this point we have an applicable credit with some money left.
			-- Now see if the relevant funding_source has any money left.
			--
			-- Look up the balance of the allocation for this combination of
			-- fund and source.  If you find such an entry, but it has a zero
			-- balance, then it's not useful, so treat it as unfound.
			-- (Actually there shouldn't be any zero balances in the table,
			-- but we check just to make sure.)
			--
			SELECT *
			INTO curr_fund_source_bal
			FROM t_fund_source_bal
			WHERE
				fund = deb.fund
				AND source = curr_credit_bal.source
				AND balance > 0;
			--
			IF curr_fund_source_bal IS NULL THEN
				--
				-- This fund/source doesn't exist or is already exhausted,
				-- so we can't use this credit.  Go on to the next one.
				--
				CONTINUE;
			END IF;
			--
			-- Convert the available balances to the currency of the fund
			--
			conv_alloc_balance := curr_fund_source_bal.balance * acq.exchange_ratio(
				curr_credit_bal.currency_type, deb.currency_type );
			conv_cred_balance := curr_credit_bal.balance * acq.exchange_ratio(
				curr_credit_bal.currency_type, deb.currency_type );
			--
			-- Determine how much we can attribute to this credit: the minimum
			-- of the debit amount, the fund/source balance, and the
			-- credit balance
			--
			--RAISE NOTICE '   deb bal %', debit_balance;
			--RAISE NOTICE '      source % balance %', curr_credit_bal.source, conv_alloc_balance;
			--RAISE NOTICE '      credit % balance %', curr_credit_bal.credit, conv_cred_balance;
			--
			conv_attr_amount := NULL;
			attr_amount := debit_balance;
			--
			IF attr_amount > conv_alloc_balance THEN
				attr_amount := conv_alloc_balance;
				conv_attr_amount := curr_fund_source_bal.balance;
			END IF;
			IF attr_amount > conv_cred_balance THEN
				attr_amount := conv_cred_balance;
				conv_attr_amount := curr_credit_bal.balance;
			END IF;
			--
			-- If we're attributing all of one of the balances, then that's how
			-- much we will deduct from the balances, and we already captured
			-- that amount above.  Otherwise we must convert the amount of the
			-- attribution from the currency of the fund back to the currency of
			-- the funding source.
			--
			IF conv_attr_amount IS NULL THEN
				conv_attr_amount := attr_amount * acq.exchange_ratio(
					deb.currency_type, curr_credit_bal.currency_type );
			END IF;
			--
			-- Insert a row to record the attribution
			--
			attrib_count := attrib_count + 1;
			INSERT INTO acq.debit_attribution (
				id,
				fund_debit,
				debit_amount,
				funding_source_credit,
				credit_amount
			) VALUES (
				attrib_count,
				deb.id,
				attr_amount,
				curr_credit_bal.credit,
				conv_attr_amount
			);
			--
			-- Subtract the attributed amount from the various balances
			--
			debit_balance := debit_balance - attr_amount;
			curr_fund_source_bal.balance := curr_fund_source_bal.balance - conv_attr_amount;
			--
			IF curr_fund_source_bal.balance <= 0 THEN
				--
				-- This allocation is exhausted.  Delete it so
				-- that we don't waste time looking at it again.
				--
				DELETE FROM t_fund_source_bal
				WHERE
					fund = curr_fund_source_bal.fund
					AND source = curr_fund_source_bal.source;
			ELSE
				UPDATE t_fund_source_bal
				SET balance = balance - conv_attr_amount
				WHERE
					fund = curr_fund_source_bal.fund
					AND source = curr_fund_source_bal.source;
			END IF;
			--
			IF curr_credit_bal.balance <= 0 THEN
				--
				-- This funding source credit is exhausted.  Delete it
				-- so that we don't waste time looking at it again.
				--
				--DELETE FROM t_credit
				--WHERE
				--	credit = curr_credit_bal.credit;
				--
				DELETE FROM t_fund_credit
				WHERE
					credit = curr_credit_bal.credit;
			ELSE
				UPDATE t_credit
				SET balance = curr_credit_bal.balance
				WHERE
					credit = curr_credit_bal.credit;
			END IF;
			--
			-- Are we done with this debit yet?
			--
			IF debit_balance <= 0 THEN
				EXIT;       -- We've fully attributed this debit; stop looking at credits.
			END IF;
		END LOOP;       -- End loop over credits
		--
		IF debit_balance <> 0 THEN
			--
			-- We weren't able to attribute this debit, or at least not
			-- all of it.  Insert a row for the unattributed balance.
			--
			attrib_count := attrib_count + 1;
			INSERT INTO acq.debit_attribution (
				id,
				fund_debit,
				debit_amount,
				funding_source_credit,
				credit_amount
			) VALUES (
				attrib_count,
				deb.id,
				debit_balance,
				NULL,
				NULL
			);
		END IF;
	END LOOP;   -- End of loop over debits
END;
$$ LANGUAGE 'plpgsql';

COMMIT;
