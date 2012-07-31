BEGIN;

SELECT evergreen.upgrade_deps_block_check('0730', :eg_version);

DROP FUNCTION acq.propagate_funds_by_org_tree (INT, INT, INT);
DROP FUNCTION acq.propagate_funds_by_org_unit (INT, INT, INT);

CREATE OR REPLACE FUNCTION acq.propagate_funds_by_org_tree(
	old_year INTEGER,
	user_id INTEGER,
	org_unit_id INTEGER,
    include_desc BOOL DEFAULT TRUE
) RETURNS VOID AS $$
DECLARE
--
new_id      INT;
old_fund    RECORD;
org_found   BOOLEAN;
--
BEGIN
	--
	-- Sanity checks
	--
	IF old_year IS NULL THEN
		RAISE EXCEPTION 'Input year argument is NULL';
	ELSIF old_year NOT BETWEEN 2008 and 2200 THEN
		RAISE EXCEPTION 'Input year is out of range';
	END IF;
	--
	IF user_id IS NULL THEN
		RAISE EXCEPTION 'Input user id argument is NULL';
	END IF;
	--
	IF org_unit_id IS NULL THEN
		RAISE EXCEPTION 'Org unit id argument is NULL';
	ELSE
		SELECT TRUE INTO org_found
		FROM actor.org_unit
		WHERE id = org_unit_id;
		--
		IF org_found IS NULL THEN
			RAISE EXCEPTION 'Org unit id is invalid';
		END IF;
	END IF;
	--
	-- Loop over the applicable funds
	--
	FOR old_fund in SELECT * FROM acq.fund
	WHERE
		year = old_year
		AND propagate
		AND ( ( include_desc AND org IN ( SELECT id FROM actor.org_unit_descendants( org_unit_id ) ) )
                OR (NOT include_desc AND org = org_unit_id ) )
    
	LOOP
		BEGIN
			INSERT INTO acq.fund (
				org,
				name,
				year,
				currency_type,
				code,
				rollover,
				propagate,
				balance_warning_percent,
				balance_stop_percent
			) VALUES (
				old_fund.org,
				old_fund.name,
				old_year + 1,
				old_fund.currency_type,
				old_fund.code,
				old_fund.rollover,
				true,
				old_fund.balance_warning_percent,
				old_fund.balance_stop_percent
			)
			RETURNING id INTO new_id;
		EXCEPTION
			WHEN unique_violation THEN
				--RAISE NOTICE 'Fund % already propagated', old_fund.id;
				CONTINUE;
		END;
		--RAISE NOTICE 'Propagating fund % to fund %',
		--	old_fund.code, new_id;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION acq.propagate_funds_by_org_unit( old_year INTEGER, user_id INTEGER, org_unit_id INTEGER ) RETURNS VOID AS $$
    SELECT acq.propagate_funds_by_org_tree( $1, $2, $3, FALSE );
$$ LANGUAGE SQL;


DROP FUNCTION acq.rollover_funds_by_org_tree (INT, INT, INT);
DROP FUNCTION acq.rollover_funds_by_org_unit (INT, INT, INT);


CREATE OR REPLACE FUNCTION acq.rollover_funds_by_org_tree(
	old_year INTEGER,
	user_id INTEGER,
	org_unit_id INTEGER,
    encumb_only BOOL DEFAULT FALSE,
    include_desc BOOL DEFAULT TRUE
) RETURNS VOID AS $$
DECLARE
--
new_fund    INT;
new_year    INT := old_year + 1;
org_found   BOOL;
perm_ous    BOOL;
xfer_amount NUMERIC := 0;
roll_fund   RECORD;
deb         RECORD;
detail      RECORD;
--
BEGIN
	--
	-- Sanity checks
	--
	IF old_year IS NULL THEN
		RAISE EXCEPTION 'Input year argument is NULL';
    ELSIF old_year NOT BETWEEN 2008 and 2200 THEN
        RAISE EXCEPTION 'Input year is out of range';
	END IF;
	--
	IF user_id IS NULL THEN
		RAISE EXCEPTION 'Input user id argument is NULL';
	END IF;
	--
	IF org_unit_id IS NULL THEN
		RAISE EXCEPTION 'Org unit id argument is NULL';
	ELSE
		--
		-- Validate the org unit
		--
		SELECT TRUE
		INTO org_found
		FROM actor.org_unit
		WHERE id = org_unit_id;
		--
		IF org_found IS NULL THEN
			RAISE EXCEPTION 'Org unit id % is invalid', org_unit_id;
		ELSIF encumb_only THEN
			SELECT INTO perm_ous value::BOOL FROM
			actor.org_unit_ancestor_setting(
				'acq.fund.allow_rollover_without_money', org_unit_id
			);
			IF NOT FOUND OR NOT perm_ous THEN
				RAISE EXCEPTION 'Encumbrance-only rollover not permitted at org %', org_unit_id;
			END IF;
		END IF;
	END IF;
	--
	-- Loop over the propagable funds to identify the details
	-- from the old fund plus the id of the new one, if it exists.
	--
	FOR roll_fund in
	SELECT
	    oldf.id AS old_fund,
	    oldf.org,
	    oldf.name,
	    oldf.currency_type,
	    oldf.code,
		oldf.rollover,
	    newf.id AS new_fund_id
	FROM
    	acq.fund AS oldf
    	LEFT JOIN acq.fund AS newf
        	ON ( oldf.code = newf.code )
	WHERE
 		    oldf.year = old_year
		AND oldf.propagate
        AND newf.year = new_year
		AND ( ( include_desc AND oldf.org IN ( SELECT id FROM actor.org_unit_descendants( org_unit_id ) ) )
                OR (NOT include_desc AND oldf.org = org_unit_id ) )
	LOOP
		--RAISE NOTICE 'Processing fund %', roll_fund.old_fund;
		--
		IF roll_fund.new_fund_id IS NULL THEN
			--
			-- The old fund hasn't been propagated yet.  Propagate it now.
			--
			INSERT INTO acq.fund (
				org,
				name,
				year,
				currency_type,
				code,
				rollover,
				propagate,
				balance_warning_percent,
				balance_stop_percent
			) VALUES (
				roll_fund.org,
				roll_fund.name,
				new_year,
				roll_fund.currency_type,
				roll_fund.code,
				true,
				true,
				roll_fund.balance_warning_percent,
				roll_fund.balance_stop_percent
			)
			RETURNING id INTO new_fund;
		ELSE
			new_fund = roll_fund.new_fund_id;
		END IF;
		--
		-- Determine the amount to transfer
		--
		SELECT amount
		INTO xfer_amount
		FROM acq.fund_spent_balance
		WHERE fund = roll_fund.old_fund;
		--
		IF xfer_amount <> 0 THEN
			IF NOT encumb_only AND roll_fund.rollover THEN
				--
				-- Transfer balance from old fund to new
				--
				--RAISE NOTICE 'Transferring % from fund % to %', xfer_amount, roll_fund.old_fund, new_fund;
				--
				PERFORM acq.transfer_fund(
					roll_fund.old_fund,
					xfer_amount,
					new_fund,
					xfer_amount,
					user_id,
					'Rollover'
				);
			ELSE
				--
				-- Transfer balance from old fund to the void
				--
				-- RAISE NOTICE 'Transferring % from fund % to the void', xfer_amount, roll_fund.old_fund;
				--
				PERFORM acq.transfer_fund(
					roll_fund.old_fund,
					xfer_amount,
					NULL,
					NULL,
					user_id,
					'Rollover into the void'
				);
			END IF;
		END IF;
		--
		IF roll_fund.rollover THEN
			--
			-- Move any lineitems from the old fund to the new one
			-- where the associated debit is an encumbrance.
			--
			-- Any other tables tying expenditure details to funds should
			-- receive similar treatment.  At this writing there are none.
			--
			UPDATE acq.lineitem_detail
			SET fund = new_fund
			WHERE
    			fund = roll_fund.old_fund -- this condition may be redundant
    			AND fund_debit in
    			(
        			SELECT id
        			FROM acq.fund_debit
        			WHERE
            			fund = roll_fund.old_fund
            			AND encumbrance
    			);
			--
			-- Move encumbrance debits from the old fund to the new fund
			--
			UPDATE acq.fund_debit
			SET fund = new_fund
			wHERE
				fund = roll_fund.old_fund
				AND encumbrance;
		END IF;
		--
		-- Mark old fund as inactive, now that we've closed it
		--
		UPDATE acq.fund
		SET active = FALSE
		WHERE id = roll_fund.old_fund;
	END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION acq.rollover_funds_by_org_unit( old_year INTEGER, user_id INTEGER, org_unit_id INTEGER, encumb_only BOOL DEFAULT FALSE ) RETURNS VOID AS $$
    SELECT acq.rollover_funds_by_org_tree( $1, $2, $3, $4, FALSE );
$$ LANGUAGE SQL;

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'acq.fund.allow_rollover_without_money',
        'acq',
        oils_i18n_gettext(
            'acq.fund.allow_rollover_without_money',
            'Allow funds to be rolled over without bringing the money along',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'acq.fund.allow_rollover_without_money',
            'Allow funds to be rolled over without bringing the money along.  This makes money left in the old fund disappear, modeling its return to some outside entity.',
            'coust',
            'description'
        ),
        'bool'
    );

COMMIT;
