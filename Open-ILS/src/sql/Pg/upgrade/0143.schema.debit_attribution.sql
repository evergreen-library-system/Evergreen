BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0143'); -- Scott McKellar

CREATE TABLE acq.debit_attribution (
	id                     INT         NOT NULL PRIMARY KEY,
	fund_debit             INT         NOT NULL
	                                   REFERENCES acq.fund_debit
	                                   DEFERRABLE INITIALLY DEFERRED,
    debit_amount           NUMERIC     NOT NULL,
	funding_source_credit  INT         REFERENCES acq.funding_source_credit
	                                   DEFERRABLE INITIALLY DEFERRED,
    credit_amount          NUMERIC
);

CREATE INDEX acq_attribution_debit_idx
	ON acq.debit_attribution( fund_debit );

CREATE INDEX acq_attribution_credit_idx
	ON acq.debit_attribution( funding_source_credit );

-- The following three types are intended for internal use
-- by the acq.attribute_debits() function.

-- For a combination of fund and funding_source: How much that source
-- allocated to that fund, and how much is left.
CREATE TYPE acq.fund_source_balance AS
(
	fund       INT,        -- fund id
	source     INT,        -- funding source id
	amount     NUMERIC,    -- original total allocation
	balance    NUMERIC     -- what's left
);

-- For a fund: a list of funding_source_credits to which
-- the fund's debits can be attributed.
CREATE TYPE acq.fund_credits AS
(
	fund       INT,        -- fund id
	credit_count INT,      -- number of entries in the following array
	credit     INT []      -- funding source credits from which a fund may draw
);

-- For a funding source credit: the funding source, the currency type
-- of the funding source, and the current balance.
CREATE TYPE acq.funding_source_credit_balance AS
(
	credit_id       INT,        -- if for funding source credit
	funding_source  INT,        -- id of funding source
	currency_type   TEXT,       -- currency type of funding source
	amount          NUMERIC,    -- original amount of credit
	balance         NUMERIC     -- how much is left
);

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
	curr_fund_src_bal   acq.fund_source_balance;
	fund_source_balance acq.fund_source_balance [];
	curr_fund_cr_list   acq.fund_credits;
	fund_credit_list    acq.fund_credits [];
	curr_cr_bal         acq.funding_source_credit_balance;
	cr_bal              acq.funding_source_credit_balance[];
	crl_max             INT;     -- Number of entries in fund_credits[]
	fcr_max             INT;     -- Number of entries in a credit list
	fsa_max             INT;     -- Number of entries in fund_source_balance[]
	fscr_max            INT;     -- Number of entries in cr_bal[]
	fsa                 RECORD;
	fc                  RECORD;
	sc                  RECORD;
	cr                  RECORD;
	--
	-- Used exclusively in the main loop:
	--
	deb                 RECORD;
	debit_balance       NUMERIC;  -- amount left to attribute for current debit
	conv_debit_balance  NUMERIC;  -- debit balance in currency of the fund
	attr_amount         NUMERIC;  -- amount being attributed, in currency of debit
	conv_attr_amount    NUMERIC;  -- amount being attributed, in currency of source
	conv_cred_balance   NUMERIC;  -- credit_balance in the currency of the fund
	conv_alloc_balance  NUMERIC;  -- allocated balance in the currency of the fund
	fund_found          BOOL; 
	credit_found        BOOL;
	alloc_found         BOOL;
	curr_cred_x         INT;   -- index of current credit in cr_bal[]
	curr_fund_src_x     INT;   -- index of current credit in fund_source_balance[]
	attrib_count        INT;   -- populates id of acq.debit_attribution
BEGIN
	--
	-- Load an array.  For each combination of fund and funding source, load an
	-- entry with the total amount allocated to that fund by that source.  This
	-- sum may reflect transfers as well as original allocations.  The balance
	-- is initially equal to the original amount.
	--
	fsa_max := 0;
	FOR fsa IN
		SELECT
			fund AS fund,
			funding_source AS source,
			sum( amount ) AS amount
		FROM
			acq.fund_allocation
		GROUP BY
			fund,
			funding_source
		HAVING
			sum( amount ) <> 0
		ORDER BY
			fund,
			funding_source
	LOOP
		IF fsa.amount > 0 THEN
			--
			-- Add this fund/source combination to the list
			--
			curr_fund_src_bal.fund    := fsa.fund;
			curr_fund_src_bal.source  := fsa.source;
			curr_fund_src_bal.amount  := fsa.amount;
			curr_fund_src_bal.balance := fsa.amount;
			--
			fsa_max := fsa_max + 1;
			fund_source_balance[ fsa_max ] := curr_fund_src_bal;
		END IF;
		--
	END LOOP;
	-------------------------------------------------------------------------------
	--
	-- Load another array.  For each fund, load a list of funding
	-- source credits from which that fund can get money.
	--
	crl_max := 0;
	FOR fc IN
		SELECT DISTINCT fund
		FROM acq.fund_allocation
		ORDER BY fund
	LOOP                  -- Loop over the funds
		--
		-- Initialize the array entry
		--
		curr_fund_cr_list.fund := fc.fund;
		fcr_max := 0;
		curr_fund_cr_list.credit := NULL;
		--
		-- Make a list of the funding source credits
		-- applicable to this fund
		--
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
			fcr_max := fcr_max + 1;
			curr_fund_cr_list.credit[ fcr_max ] := sc.id;
			--
		END LOOP;
		--
		-- If there are any credits applicable to this fund,
		-- add the credit list to the list of credit lists.
		--
		IF fcr_max > 0 THEN
			curr_fund_cr_list.credit_count := fcr_max;
			crl_max := crl_max + 1;
			fund_credit_list[ crl_max ] := curr_fund_cr_list;
		END IF;
		--
	END LOOP;
	-------------------------------------------------------------------------------
	--
	-- Load yet another array.  This one is a list of funding source credits, with
	-- their balances.
	--
	fscr_max := 0;
    FOR cr in
        SELECT
            ofsc.id,
            ofsc.funding_source,
            ofsc.amount,
            fs.currency_type
        FROM
            acq.ordered_funding_source_credit AS ofsc,
            acq.funding_source fs
        WHERE
            ofsc.funding_source = fs.id
       ORDER BY
            ofsc.sort_priority,
            ofsc.sort_date,
            ofsc.id
	LOOP
		--
		curr_cr_bal.credit_id      := cr.id;
		curr_cr_bal.funding_source := cr.funding_source;
		curr_cr_bal.amount         := cr.amount;
		curr_cr_bal.balance        := cr.amount;
		curr_cr_bal.currency_type  := cr.currency_type;
		--
		fscr_max := fscr_max + 1;
		cr_bal[ fscr_max ] := curr_cr_bal;
	END LOOP;
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
			id
	LOOP
		debit_balance := deb.amount;
		--
		-- Find the list of credits applicable to this fund
		--
		fund_found := false;
		FOR i in 1 .. crl_max LOOP
			IF fund_credit_list[ i ].fund = deb.fund THEN
				curr_fund_cr_list := fund_credit_list[ i ];
				fund_found := true;
				exit;
			END IF;
		END LOOP;
		--
		-- If we didn't find an entry for this fund, then there are no applicable
		-- funding sources for this fund, and the debit is hence unattributable.
		--
		-- If we did find an entry for this fund, then we have a list of funding source
		-- credits that we can apply to it.  Go through that list and attribute the
		-- debit accordingly.
		--
		IF fund_found THEN
			--
			-- For each applicable credit
			--
			FOR i in 1 .. curr_fund_cr_list.credit_count LOOP
				--
				-- Find the entry in the credit list for this credit.  If you find it but
				-- it has a zero balance, it's not useful, so treat it as if you didn't
				-- find it.
				--
				credit_found := false;
				FOR j in 1 .. fscr_max LOOP
					IF cr_bal[ j ].credit_id = curr_fund_cr_list.credit[i] THEN
						curr_cr_bal  := cr_bal[ j ];
						IF curr_cr_bal.balance <> 0 THEN
							curr_cred_x  := j;
							credit_found := true;
						END IF;
						EXIT;
					END IF;
				END LOOP;
				--
				IF NOT credit_found THEN
					--
					-- This credit is not usable; try the next one.
					--
					CONTINUE;
				END IF;
				--
				-- At this point we have an applicable credit with some money left.
				-- Now see if the relevant funding_source has any money left.
				--
				-- Search the fund/source list for an entry with this combination
				-- of fund and source.  If you find such an entry, but it has a zero
				-- balance, then it's not useful, so treat it as unfound.
				--
				alloc_found := false;
				FOR j in 1 .. fsa_max LOOP
					IF fund_source_balance[ j ].fund = deb.fund
					AND fund_source_balance[ j ].source = curr_cr_bal.funding_source THEN
						curr_fund_src_bal := fund_source_balance[ j ];
						IF curr_fund_src_bal.balance <> 0 THEN
							curr_fund_src_x := j;
							alloc_found := true;
						END IF;
						EXIT;
					END IF;
				END LOOP;
				--
				IF NOT alloc_found THEN
					--
					-- This fund/source doesn't exist is already exhausted,
					-- so we can't use this credit.  Go on to the next on.
					--
					CONTINUE;
				END IF;
				--
				-- Convert the available balances to the currency of the fund
				--
				conv_alloc_balance := curr_fund_src_bal.balance * acq.exchange_ratio(
					curr_cr_bal.currency_type, deb.currency_type );
				conv_cred_balance := curr_cr_bal.balance * acq.exchange_ratio(
					curr_cr_bal.currency_type, deb.currency_type );
				--
				-- Determine how much we can attribute to this credit: the minimum
				-- of the debit amount, the fund/source balance, and the
				-- credit balance
				--
				attr_amount := debit_balance;
				IF attr_amount > conv_alloc_balance THEN
					attr_amount := conv_alloc_balance;
				END IF;
				IF attr_amount > conv_cred_balance THEN
					attr_amount := conv_cred_balance;
				END IF;
				--
				-- Convert the amount of the attribution to the
				-- currency of the funding source.
				--
				conv_attr_amount := attr_amount * acq.exchange_ratio(
					deb.currency_type, curr_cr_bal.currency_type );
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
					curr_cr_bal.credit_id,
					conv_attr_amount
				);
				--
				-- Subtract the attributed amount from the various balances
				--
				debit_balance := debit_balance - attr_amount;
				--
				curr_fund_src_bal.balance := curr_fund_src_bal.balance - conv_attr_amount;
				fund_source_balance[ curr_fund_src_x ] := curr_fund_src_bal;
				IF curr_fund_src_bal.balance <= 0 THEN
					--
					-- This allocation is exhausted.  Take it out of the list
					-- so that we don't waste time looking at it again.
					--
					FOR i IN curr_fund_src_x .. fsa_max - 1 LOOP
						fund_source_balance[ i ] := fund_source_balance[ i + 1 ];
					END LOOP;
					fund_source_balance[ fsa_max ] := NULL;
					fsa_max := fsa_max - 1;
				END IF;
				--
				curr_cr_bal.balance   := curr_cr_bal.balance - conv_attr_amount;
				cr_bal[ curr_cred_x ] := curr_cr_bal;
				IF curr_cr_bal.balance <= 0 THEN
					--
					-- This funding source credit is exhausted.  Take it out of
					-- the list so that we don't waste time looking at it again.
					--
					FOR i IN curr_cred_x .. fscr_max - 1 LOOP
						cr_bal[ i ] := cr_bal[ i + 1 ];
					END LOOP;
					cr_bal[ fscr_max ] := NULL;
					fscr_max := fscr_max - 1;
				END IF;
				--
				-- Are we done with this debit yet?
				--
				IF debit_balance <= 0 THEN
					EXIT;       -- We've fully attributed this debit; stop looking at credits.
				END IF;
			END LOOP;           -- End of loop over applicable credits
		END IF;
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
