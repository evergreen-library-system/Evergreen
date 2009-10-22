BEGIN;

-- Create new table acq.fund_allocation_percent
-- Populate it from acq.fund_allocation
-- Convert all percentages to amounts in acq.fund_allocation

INSERT INTO config.upgrade_log (version) VALUES ('0049'); -- Scott McKellar

CREATE TABLE acq.fund_allocation_percent
(
    id                   SERIAL            PRIMARY KEY,
    funding_source       INT               NOT NULL REFERENCES acq.funding_source
                                               DEFERRABLE INITIALLY DEFERRED,
    org                  INT               NOT NULL REFERENCES actor.org_unit
                                               DEFERRABLE INITIALLY DEFERRED,
    fund_code            TEXT,
    percent              NUMERIC           NOT NULL,
    allocator            INTEGER           NOT NULL REFERENCES actor.usr
                                               DEFERRABLE INITIALLY DEFERRED,
    note                 TEXT,
    create_time          TIMESTAMPTZ       NOT NULL DEFAULT now(),
    CONSTRAINT logical_key UNIQUE( funding_source, org, fund_code ),
    CONSTRAINT percentage_range CHECK( percent >= 0 AND percent <= 100 )
);

-- Trigger function to validate combination of org_unit and fund_code

CREATE OR REPLACE FUNCTION acq.fund_alloc_percent_val()
RETURNS TRIGGER AS $$
--
DECLARE
--
dummy int := 0;
--
BEGIN
    SELECT
        1
    INTO
        dummy
    FROM
        acq.fund
    WHERE
        org = NEW.org
        AND code = NEW.fund_code
        LIMIT 1;
    --
    IF dummy = 1 then
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'No fund exists for org % and code %', NEW.org, NEW.fund_code;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acq_fund_alloc_percent_val_trig
    BEFORE INSERT OR UPDATE ON acq.fund_allocation_percent
    FOR EACH ROW EXECUTE PROCEDURE acq.fund_alloc_percent_val();

-- To do: trigger to verify that percentages don't add up to more than 100

CREATE OR REPLACE FUNCTION acq.fap_limit_100()
RETURNS TRIGGER AS $$
DECLARE
--
total_percent numeric;
--
BEGIN
    SELECT
        sum( percent )
    INTO
        total_percent
    FROM
        acq.fund_allocation_percent AS fap
    WHERE
        fap.funding_source = NEW.funding_source;
    --
    IF total_percent > 100 THEN
        RAISE EXCEPTION 'Total percentages exceed 100 for funding_source %',
            NEW.funding_source;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER acqfap_limit_100_trig
    AFTER INSERT OR UPDATE ON acq.fund_allocation_percent
    FOR EACH ROW EXECUTE PROCEDURE acq.fap_limit_100();

-- Populate new table from acq.fund_allocation

INSERT INTO acq.fund_allocation_percent
(
    funding_source,
    org,
    fund_code,
    percent,
    allocator,
    note,
    create_time
)
    SELECT
        fa.funding_source,
        fund.org,
        fund.code,
        fa.percent,
        fa.allocator,
        fa.note,
        fa.create_time
    FROM
        acq.fund_allocation AS fa
            INNER JOIN acq.fund AS fund
                ON ( fa.fund = fund.id )
    WHERE
        fa.percent is not null
    ORDER BY
        fund.org;

-- Temporary function to convert percentages to amounts in acq.fund_allocation

-- Algorithm to apply to each funding source:

-- 1. Add up the credits.
-- 2. Add up the percentages.
-- 3. Multiply the sum of the percentages timies the sum of the credits.  Drop any
--    fractional cents from the result.  This is the total amount to be allocated.
-- 4. For each allocation: multiply the percentage by the total allocation.  Drop any
--    fractional cents to get a preliminary amount.
-- 5. Add up the preliminary amounts for all the allocations.
-- 6. Subtract the results of step 5 from the result of step 3.  The difference is the
--    number of residual cents (resulting from having dropped fractional cents) that
--    must be distributed across the funds in order to make the total of the amounts
--    match the total allocation.
-- 7. Make a second pass through the allocations, in decreasing order of the fractional
--    cents that were dropped from their amounts in step 4.  Add one cent to the amount
--    for each successive fund, until all the residual cents have been exhausted.

-- Result: the sum of the individual allocations now equals the total to be allocated,
-- to the penny.  The individual amounts match the percentages as closely as possible,
-- given the constraint that the total must match.

CREATE OR REPLACE FUNCTION acq.apply_percents()
RETURNS VOID AS $$
declare
--
tot              RECORD;
fund             RECORD;
tot_cents        INTEGER;
src              INTEGER;
id               INTEGER[];
curr_id          INTEGER;
pennies          NUMERIC[];
curr_amount      NUMERIC;
i                INTEGER;
total_of_floors  INTEGER;
total_percent    NUMERIC;
total_allocation INTEGER;
residue          INTEGER;
--
begin
	RAISE NOTICE 'Applying percents';
	FOR tot IN
		SELECT
			fsrc.funding_source,
			sum( fsrc.amount ) AS total
		FROM
			acq.funding_source_credit AS fsrc
		WHERE fsrc.funding_source IN
			( SELECT DISTINCT fa.funding_source
			  FROM acq.fund_allocation AS fa
			  WHERE fa.percent IS NOT NULL )
		GROUP BY
			fsrc.funding_source
	LOOP
		tot_cents = floor( tot.total * 100 );
		src = tot.funding_source;
		RAISE NOTICE 'Funding source % total %',
			src, tot_cents;
		i := 0;
		total_of_floors := 0;
		total_percent := 0;
		--
		FOR fund in
			SELECT
				fa.id,
				fa.percent,
				floor( fa.percent * tot_cents / 100 ) as floor_pennies
			FROM
				acq.fund_allocation AS fa
			WHERE
				fa.funding_source = src
				AND fa.percent IS NOT NULL
			ORDER BY
				mod( fa.percent * tot_cents / 100, 1 ),
				fa.fund,
				fa.id
		LOOP
			RAISE NOTICE '   %: %',
				fund.id,
				fund.floor_pennies;
			i := i + 1;
			id[i] = fund.id;
			pennies[i] = fund.floor_pennies;
			total_percent := total_percent + fund.percent;
			total_of_floors := total_of_floors + pennies[i];
		END LOOP;
		total_allocation := floor( total_percent * tot_cents /100 );
		RAISE NOTICE 'Total before distributing residue: %', total_of_floors;
		residue := total_allocation - total_of_floors;
		RAISE NOTICE 'Residue: %', residue;
		--
		-- Post the calculated amounts, revising as needed to
		-- distribute the rounding error
		--
		WHILE i > 0 LOOP
			IF residue > 0 THEN
				pennies[i] = pennies[i] + 1;
				residue := residue - 1;
			END IF;
			--
			-- Post amount
			--
			curr_id     := id[i];
			curr_amount := trunc( pennies[i] / 100, 2 );
			--
			UPDATE
				acq.fund_allocation AS fa
			SET
				amount = curr_amount,
				percent = NULL
			WHERE
				fa.id = curr_id;
			--
			RAISE NOTICE '   ID % and amount %',
				curr_id,
				curr_amount;
			i = i - 1;
		END LOOP;
	END LOOP;
end;
$$ LANGUAGE 'plpgsql';

-- Run the temporary function

select * from acq.apply_percents();

-- Drop the temporary function now that we're done with it

drop function acq.apply_percents();

COMMIT;
