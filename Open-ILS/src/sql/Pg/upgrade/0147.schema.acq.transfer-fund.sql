BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0147'); -- Scott McKellar

CREATE OR REPLACE FUNCTION acq.transfer_fund(
	old_fund   IN INT,
	old_amount IN NUMERIC,     -- in currency of old fund
	new_fund   IN INT,
	new_amount IN NUMERIC,     -- in currency of new fund
	user_id    IN INT,
	xfer_note  IN TEXT         -- to be recorded in acq.fund_transfer
	-- ,funding_source_in IN INT  -- if user wants to specify a funding source (see notes)
) RETURNS VOID AS $$
/* -------------------------------------------------------------------------------

Function to transfer money from one fund to another.

A transfer is represented as a pair of entries in acq.fund_allocation, with a
negative amount for the old (losing) fund and a positive amount for the new
(gaining) fund.  In some cases there may be more than one such pair of entries
in order to pull the money from different funding sources, or more specifically
from different funding source credits.  For each such pair there is also an
entry in acq.fund_transfer.

Since funding_source is a non-nullable column in acq.fund_allocation, we must
choose a funding source for the transferred money to come from.  This choice
must meet two constraints, so far as possible:

1. The amount transferred from a given funding source must not exceed the
amount allocated to the old fund by the funding source.  To that end we
compare the amount being transferred to the amount allocated.

2. We shouldn't transfer money that has already been spent or encumbered, as
defined by the funding attribution process.  We attribute expenses to the
oldest funding source credits first.  In order to avoid transferring that
attributed money, we reverse the priority, transferring from the newest funding
source credits first.  There can be no guarantee that this approach will
avoid overcommitting a fund, but no other approach can do any better.

In this context the age of a funding source credit is defined by the
deadline_date for credits with deadline_dates, and by the effective_date for
credits without deadline_dates, with the proviso that credits with deadline_dates
are all considered "older" than those without.

----------

In the signature for this function, there is one last parameter commented out,
named "funding_source_in".  Correspondingly, the WHERE clause for the query
driving the main loop has an OR clause commented out, which references the
funding_source_in parameter.

If these lines are uncommented, this function will allow the user optionally to
restrict a fund transfer to a specified funding source.  If the source
parameter is left NULL, then there will be no such restriction.

------------------------------------------------------------------------------- */ 
DECLARE
	same_currency      BOOLEAN;
	currency_ratio     NUMERIC;
	old_fund_currency  TEXT;
	old_remaining      NUMERIC;  -- in currency of old fund
	new_fund_currency  TEXT;
	new_fund_active    BOOLEAN;
	new_remaining      NUMERIC;  -- in currency of new fund
	curr_old_amt       NUMERIC;  -- in currency of old fund
	curr_new_amt       NUMERIC;  -- in currency of new fund
	source_addition    NUMERIC;  -- in currency of funding source
	source_deduction   NUMERIC;  -- in currency of funding source
	orig_allocated_amt NUMERIC;  -- in currency of funding source
	allocated_amt      NUMERIC;  -- in currency of fund
	source             RECORD;
BEGIN
	--
	-- Sanity checks
	--
	IF old_fund IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: old fund id is NULL';
	END IF;
	--
	IF old_amount IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: amount to transfer is NULL';
	END IF;
	--
	-- The new fund and its amount must be both NULL or both not NULL.
	--
	IF new_fund IS NOT NULL AND new_amount IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: amount to transfer to receiving fund is NULL';
	END IF;
	--
	IF new_fund IS NULL AND new_amount IS NOT NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: receiving fund is NULL, its amount is not NULL';
	END IF;
	--
	IF user_id IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: user id is NULL';
	END IF;
	--
	-- Initialize the amounts to be transferred, each denominated
	-- in the currency of its respective fund.  They will be
	-- reduced on each iteration of the loop.
	--
	old_remaining := old_amount;
	new_remaining := new_amount;
	--
	-- RAISE NOTICE 'Transferring % in fund % to % in fund %',
	--	old_amount, old_fund, new_amount, new_fund;
	--
	-- Get the currency types of the old and new funds.
	--
	SELECT
		currency_type
	INTO
		old_fund_currency
	FROM
		acq.fund
	WHERE
		id = old_fund;
	--
	IF old_fund_currency IS NULL THEN
		RAISE EXCEPTION 'acq.transfer_fund: old fund id % is not defined', old_fund;
	END IF;
	--
	IF new_fund IS NOT NULL THEN
		SELECT
			currency_type,
			active
		INTO
			new_fund_currency,
			new_fund_active
		FROM
			acq.fund
		WHERE
			id = new_fund;
		--
		IF new_fund_currency IS NULL THEN
			RAISE EXCEPTION 'acq.transfer_fund: new fund id % is not defined', new_fund;
		ELSIF NOT new_fund_active THEN
			--
			-- No point in putting money into a fund from whence you can't spend it
			--
			RAISE EXCEPTION 'acq.transfer_fund: new fund id % is inactive', new_fund;
		END IF;
		--
		IF new_amount = old_amount THEN
			same_currency := true;
			currency_ratio := 1;
		ELSE
			--
			-- We'll have to translate currency between funds.  We presume that
			-- the calling code has already applied an appropriate exchange rate,
			-- so we'll apply the same conversion to each sub-transfer.
			--
			same_currency := false;
			currency_ratio := new_amount / old_amount;
		END IF;
	END IF;
	--
	-- Identify the funding source(s) from which we want to transfer the money.
	-- The principle is that we want to transfer the newest money first, because
	-- we spend the oldest money first.  The priority for spending is defined
	-- by a sort of the view acq.ordered_funding_source_credit.
	--
	FOR source in
		SELECT
			ofsc.id,
			ofsc.funding_source,
			ofsc.amount,
			ofsc.amount * acq.exchange_ratio( fs.currency_type, old_fund_currency )
				AS converted_amt,
			fs.currency_type
		FROM
			acq.ordered_funding_source_credit AS ofsc,
			acq.funding_source fs
		WHERE
			ofsc.funding_source = fs.id
			and ofsc.funding_source IN
			(
				SELECT funding_source
				FROM acq.fund_allocation
				WHERE fund = old_fund
			)
			-- and
			-- (
			-- 	ofsc.funding_source = funding_source_in
			-- 	OR funding_source_in IS NULL
			-- )
		ORDER BY
			ofsc.sort_priority desc,
			ofsc.sort_date desc,
			ofsc.id desc
	LOOP
		--
		-- Determine how much money the old fund got from this funding source,
		-- denominated in the currency types of the source and of the fund.
		-- This result may reflect transfers from previous iterations.
		--
		SELECT
			COALESCE( sum( amount ), 0 ),
			COALESCE( sum( amount )
				* acq.exchange_ratio( source.currency_type, old_fund_currency ), 0 )
		INTO
			orig_allocated_amt,     -- in currency of the source
			allocated_amt           -- in currency of the old fund
		FROM
			acq.fund_allocation
		WHERE
			fund = old_fund
			and funding_source = source.funding_source;
		--	
		-- Determine how much to transfer from this credit, in the currency
		-- of the fund.   Begin with the amount remaining to be attributed:
		--
		curr_old_amt := old_remaining;
		--
		-- Can't attribute more than was allocated from the fund:
		--
		IF curr_old_amt > allocated_amt THEN
			curr_old_amt := allocated_amt;
		END IF;
		--
		-- Can't attribute more than the amount of the current credit:
		--
		IF curr_old_amt > source.converted_amt THEN
			curr_old_amt := source.converted_amt;
		END IF;
		--
		curr_old_amt := trunc( curr_old_amt, 2 );
		--
		old_remaining := old_remaining - curr_old_amt;
		--
		-- Determine the amount to be deducted, if any,
		-- from the old allocation.
		--
		IF old_remaining > 0 THEN
			--
			-- In this case we're using the whole allocation, so use that
			-- amount directly instead of applying a currency translation
			-- and thereby inviting round-off errors.
			--
			source_deduction := - orig_allocated_amt;
		ELSE 
			source_deduction := trunc(
				( - curr_old_amt ) *
					acq.exchange_ratio( old_fund_currency, source.currency_type ),
				2 );
		END IF;
		--
		IF source_deduction <> 0 THEN
			--
			-- Insert negative allocation for old fund in fund_allocation,
			-- converted into the currency of the funding source
			--
			INSERT INTO acq.fund_allocation (
				funding_source,
				fund,
				amount,
				allocator,
				note
			) VALUES (
				source.funding_source,
				old_fund,
				source_deduction,
				user_id,
				'Transfer to fund ' || new_fund
			);
		END IF;
		--
		IF new_fund IS NOT NULL THEN
			--
			-- Determine how much to add to the new fund, in
			-- its currency, and how much remains to be added:
			--
			IF same_currency THEN
				curr_new_amt := curr_old_amt;
			ELSE
				IF old_remaining = 0 THEN
					--
					-- This is the last iteration, so nothing should be left
					--
					curr_new_amt := new_remaining;
					new_remaining := 0;
				ELSE
					curr_new_amt := trunc( curr_old_amt * currency_ratio, 2 );
					new_remaining := new_remaining - curr_new_amt;
				END IF;
			END IF;
			--
			-- Determine how much to add, if any,
			-- to the new fund's allocation.
			--
			IF old_remaining > 0 THEN
				--
				-- In this case we're using the whole allocation, so use that amount
				-- amount directly instead of applying a currency translation and
				-- thereby inviting round-off errors.
				--
				source_addition := orig_allocated_amt;
			ELSIF source.currency_type = old_fund_currency THEN
				--
				-- In this case we don't need a round trip currency translation,
				-- thereby inviting round-off errors:
				--
				source_addition := curr_old_amt;
			ELSE 
				source_addition := trunc(
					curr_new_amt *
						acq.exchange_ratio( new_fund_currency, source.currency_type ),
					2 );
			END IF;
			--
			IF source_addition <> 0 THEN
				--
				-- Insert positive allocation for new fund in fund_allocation,
				-- converted to the currency of the founding source
				--
				INSERT INTO acq.fund_allocation (
					funding_source,
					fund,
					amount,
					allocator,
					note
				) VALUES (
					source.funding_source,
					new_fund,
					source_addition,
					user_id,
					'Transfer from fund ' || old_fund
				);
			END IF;
		END IF;
		--
		IF trunc( curr_old_amt, 2 ) <> 0
		OR trunc( curr_new_amt, 2 ) <> 0 THEN
			--
			-- Insert row in fund_transfer, using amounts in the currency of the funds
			--
			INSERT INTO acq.fund_transfer (
				src_fund,
				src_amount,
				dest_fund,
				dest_amount,
				transfer_user,
				note,
				funding_source_credit
			) VALUES (
				old_fund,
				trunc( curr_old_amt, 2 ),
				new_fund,
				trunc( curr_new_amt, 2 ),
				user_id,
				xfer_note,
				source.id
			);
		END IF;
		--
		if old_remaining <= 0 THEN
			EXIT;                   -- Nothing more to be transferred
		END IF;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMIT;
