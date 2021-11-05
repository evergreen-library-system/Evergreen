--Upgrade Script for 3.7.1 to 3.8.0
\set eg_version '''3.8.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.8.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1260', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.photo_url.require',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.require',
            'Require Photo URL field on patron registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.require',
            'The Photo URL field will be required on the patron registration screen.',
            'coust',
            'description'
        ),
        'bool'
    );

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.photo_url.show',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.show',
            'Show Photo URL field on patron registration',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.show',
            'The Photo URL field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.',
            'coust',
            'description'
        ),
        'bool'
    );

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'ui.patron.edit.au.photo_url.suggest',
        'gui',
        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.suggest',
            'Suggest Photo URL field on patron registration',
            'coust',
            'label'
        ),

        oils_i18n_gettext(
            'ui.patron.edit.au.photo_url.suggest',
            'The Photo URL field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.',
            'coust',
            'description'
        ),
        'bool'
    );

INSERT INTO permission.perm_list ( id, code, description ) VALUES
( 632, 'UPDATE_USER_PHOTO_URL', oils_i18n_gettext( 632,
   'Update the user photo url field in patron registration and editor', 'ppl', 'description' ))
;

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
        SELECT
                pgt.id, perm.id, aout.depth, FALSE
        FROM
                permission.grp_tree pgt,
                permission.perm_list perm,
                actor.org_unit_type aout
        WHERE
                pgt.name = 'Circulators' AND
                aout.name = 'System' AND
                perm.code = 'UPDATE_USER_PHOTO_URL'
;


SELECT evergreen.upgrade_deps_block_check('1266', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record.copies', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record.copies',
        'Grid Config: eg.grid.catalog.record.copies',
        'cwst', 'label')
    );


SELECT evergreen.upgrade_deps_block_check('1267', :eg_version);

SELECT auditor.create_auditor ( 'acq', 'fund_debit' );



SELECT evergreen.upgrade_deps_block_check('1268', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.staff.catalog.results.show_more', 'gui', 'bool',
    oils_i18n_gettext(
        'eg.staff.catalog.results.show_more',
        'Show more details in Angular staff catalog',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1269', :eg_version);

WITH perms_to_add AS
    (SELECT id FROM
    permission.perm_list
    WHERE code IN ('VIEW_BOOKING_RESERVATION', 'VIEW_BOOKING_RESERVATION_ATTR_MAP'))

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT grp, perms_to_add.id as perm, depth, grantable
        FROM perms_to_add,
        permission.grp_perm_map
        
        --- Don't add the permissions if they have already been assigned
        WHERE grp NOT IN
            (SELECT DISTINCT grp FROM permission.grp_perm_map
            INNER JOIN perms_to_add ON perm=perms_to_add.id)
            
        --- Anybody who can view resources should also see reservations
        --- at the same level
        AND perm = (
            SELECT id
                FROM permission.perm_list
                WHERE code = 'VIEW_BOOKING_RESOURCE'
        );



SELECT evergreen.upgrade_deps_block_check('1270', :eg_version);

INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'BKS', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'COM', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'MAP', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'MIX', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'REC', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'SCO', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'SER', 39, 1, ' ');
INSERT INTO config.marc21_ff_pos_map (fixed_field, tag, rec_type,start_pos, length, default_val) VALUES ('Srce', '008', 'VIS', 39, 1, ' ');


INSERT INTO config.record_attr_definition (name,label,fixed_field) values ('srce','Srce','Srce');

INSERT INTO config.coded_value_map (id, ctype, code, value) VALUES
(1750, 'srce', ' ', oils_i18n_gettext('1750', 'National bibliographic agency', 'ccvm', 'value')),
(1751, 'srce', 'c', oils_i18n_gettext('1751', 'Cooperative cataloging program', 'ccvm', 'value')),
(1752, 'srce', 'd', oils_i18n_gettext('1752', 'Other', 'ccvm', 'value'));


SELECT evergreen.upgrade_deps_block_check('1271', :eg_version);

INSERT INTO config.org_unit_setting_type
    (grp, name, datatype, label, description, update_perm, view_perm)
VALUES (
    'credit',
    'credit.processor.stripe.currency', 'string',
    oils_i18n_gettext(
        'credit.processor.stripe.currency',
        'Stripe ISO 4217 currency code',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'credit.processor.stripe.currency',
        'Use an all lowercase version of a Stripe-supported ISO 4217 currency code.  Defaults to "usd"',
        'coust',
        'description'
    ),
    (SELECT id FROM permission.perm_list WHERE code = 'ADMIN_CREDIT_CARD_PROCESSING'),
    (SELECT id FROM permission.perm_list WHERE code = 'VIEW_CREDIT_CARD_PROCESSING')
);


SELECT evergreen.upgrade_deps_block_check('1272', :eg_version);

DO $$
BEGIN

  PERFORM FROM config.usr_setting_type WHERE name = 'circ.collections.exempt';

  IF NOT FOUND THEN

    INSERT INTO config.usr_setting_type (
      name,
      opac_visible,
      label,
      description,
      datatype,
      reg_default
    ) VALUES (
      'circ.collections.exempt',
      FALSE,
      oils_i18n_gettext(
        'circ.collections.exempt',
        'Collections: Exempt',
        'cust',
        'label'
      ),
      oils_i18n_gettext(
        'circ.collections.exempt',
        'User is exempt from collections tracking/processing',
        'cust',
        'description'
      ),
      'bool',
      'false'
    );

  END IF;

END
$$;


SELECT evergreen.upgrade_deps_block_check('1273', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype )
SELECT  'opac.did_you_mean.max_suggestions',
        'opac',
        'Maximum number of spelling suggestions that may be offered',
        'If set to -1, provide "best" suggestion if mispelled; if set higher than 0, the maximum suggestions that can be provided; if set to 0, disable suggestions.',
        'integer'
  WHERE NOT EXISTS (SELECT 1 FROM config.org_unit_setting_type WHERE name = 'opac.did_you_mean.max_suggestions');



SELECT evergreen.upgrade_deps_block_check('1274', :eg_version);

CREATE INDEX poi_fund_debit_idx ON acq.po_item (fund_debit);
CREATE INDEX ii_fund_debit_idx ON acq.invoice_item (fund_debit);


SELECT evergreen.upgrade_deps_block_check('1275', :eg_version);

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
    old_fund_row       acq.fund%ROWTYPE;
    new_fund_row       acq.fund%ROWTYPE;
    old_org_row        actor.org_unit%ROWTYPE;
    new_org_row        actor.org_unit%ROWTYPE;
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

    -- Fetch old and new fund's information
    -- in order to construct the allocation notes
    SELECT INTO old_fund_row * FROM acq.fund WHERE id = old_fund;
    SELECT INTO old_org_row * FROM actor.org_unit WHERE id = old_fund_row.org;
    SELECT INTO new_fund_row * FROM acq.fund WHERE id = new_fund;
    SELECT INTO new_org_row * FROM actor.org_unit WHERE id = new_fund_row.org;

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
			source_deduction := - curr_old_amt;
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
				'Transfer to fund ' || new_fund_row.code || ' ('
                                    || new_fund_row.year || ') ('
                                    || new_org_row.shortname || ')'
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
				source_addition := curr_new_amt;
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
				    'Transfer from fund ' || old_fund_row.code || ' ('
                                          || old_fund_row.year || ') ('
                                          || old_org_row.shortname || ')'
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


SELECT evergreen.upgrade_deps_block_check('1276', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.acq.fund.fund_debit', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.fund.fund_debit',
        'Grid Config: eg.grid.acq.fund.fund_debit',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.fund.fund_transfer', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.fund.fund_transfer',
        'Grid Config: eg.grid.acq.fund.fund_transfer',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.fund.fund_allocation', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.fund.fund_allocation',
        'Grid Config: eg.grid.acq.fund.fund_allocation',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.fund', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.fund',
        'Grid Config: eg.grid.admin.acq.fund',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.acq.funding_source', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.acq.funding_source',
        'Grid Config: eg.grid.admin.acq.funding_source',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.funding_source.fund_allocation', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.funding_source.fund_allocation',
        'Grid Config: eg.grid.acq.funding_source.fund_allocation',
        'cwst', 'label'
    )
), (
    'eg.grid.acq.funding_source.credit', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.acq.funding_source.credit',
        'Grid Config: eg.grid.acq.funding_source.credit',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1277', :eg_version);

-- if there are any straggling funds without a code set, fix that
UPDATE acq.fund
SET code = 'FUND-WITH-ID-' || id
WHERE code IS NULL;

ALTER TABLE acq.fund
    ALTER COLUMN code SET NOT NULL;


SELECT evergreen.upgrade_deps_block_check('1278', :eg_version);

CREATE OR REPLACE VIEW reporter.asset_call_number_dewey AS
  SELECT id AS call_number,
    call_number_dewey(label) AS dewey,
    CASE WHEN call_number_dewey(label) ~ '^[0-9]+\.?[0-9]*$'::text
      THEN btrim(to_char(10::double precision * floor(call_number_dewey(label)::double precision / 10::double precision), '000'::text))
      ELSE NULL::text
    END AS dewey_block_tens,
    CASE WHEN call_number_dewey(label) ~ '^[0-9]+\.?[0-9]*$'::text
      THEN btrim(to_char(100::double precision * floor(call_number_dewey(label)::double precision / 100::double precision), '000'::text))
      ELSE NULL::text
    END AS dewey_block_hundreds,
    CASE WHEN call_number_dewey(label) ~ '^[0-9]+\.?[0-9]*$'::text
      THEN (btrim(to_char(10::double precision * floor(call_number_dewey(label)::double precision / 10::double precision), '000'::text)) || '-'::text)
      || btrim(to_char(10::double precision * floor(call_number_dewey(label)::double precision / 10::double precision) + 9::double precision, '000'::text))
      ELSE NULL::text
    END AS dewey_range_tens,
    CASE WHEN call_number_dewey(label) ~ '^[0-9]+\.?[0-9]*$'::text
      THEN (btrim(to_char(100::double precision * floor(call_number_dewey(label)::double precision / 100::double precision), '000'::text)) || '-'::text)
      || btrim(to_char(100::double precision * floor(call_number_dewey(label)::double precision / 100::double precision) + 99::double precision, '000'::text))
      ELSE NULL::text
    END AS dewey_range_hundreds
  FROM asset.call_number
  WHERE call_number_dewey(label) ~ '^[0-9]'::text;



SELECT evergreen.upgrade_deps_block_check('1279', :eg_version);

UPDATE config.org_unit_setting_type SET fm_class='cnal', datatype='link' WHERE name='ui.patron.default_inet_access_level';



SELECT evergreen.upgrade_deps_block_check('1280', :eg_version);

UPDATE config.org_unit_setting_type
  SET description = $$How long to wait before allowing opportunistic capture of holds with a pickup library other than the context item's circulating library$$ -- ' vim
  WHERE name = 'circ.hold_stalling.soft';

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.pickup_hold_stalling.soft',
  'holds',
  'Pickup Library Soft stalling interval',
  'When set for the pickup library, this specifies that for holds with a request time age smaller than this interval only items scanned at the pickup library can be opportunistically captured. Example "5 days". This setting takes precedence over "Soft stalling interval" (circ.hold_stalling.soft) when the interval is in force.',
  'interval',
  null
);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.pickup_hold_stalling.hard',
  'holds',
  'Pickup Library Hard stalling interval',
  'When set for the pickup library, this specifies that no items with a calculated proximity greater than 0 from the pickup library can be directly targeted for this time period if there are local available copies.  Example "3 days".',
  'interval',
  null
);



SELECT evergreen.upgrade_deps_block_check('1281', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.cat.volcopy.defaults', 'cat', 'object',
    oils_i18n_gettext(
        'eg.cat.volcopy.defaults',
        'Holdings Editor Default Values and Visibility',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1282', :eg_version);

CREATE OR REPLACE FUNCTION search.symspell_lookup(
        raw_input text,
        search_class text,
        verbosity integer DEFAULT 2,
        xfer_case boolean DEFAULT false,
        count_threshold integer DEFAULT 1,
        soundex_weight integer DEFAULT 0,
        pg_trgm_weight integer DEFAULT 0,
        kbdist_weight integer DEFAULT 0
) RETURNS SETOF search.symspell_lookup_output
 LANGUAGE plpgsql
AS $function$
DECLARE
    prefix_length INT;
    maxED         INT;
    good_suggs  HSTORE;
    word_list   TEXT[];
    edit_list   TEXT[] := '{}';
    seen_list   TEXT[] := '{}';
    output      search.symspell_lookup_output;
    output_list search.symspell_lookup_output[];
    entry       RECORD;
    entry_key   TEXT;
    prefix_key  TEXT;
    sugg        TEXT;
    input       TEXT;
    word        TEXT;
    w_pos       INT := -1;
    smallest_ed INT := -1;
    global_ed   INT;
    i_len       INT;
    l_maxED     INT;
BEGIN
    SELECT value::INT INTO prefix_length FROM config.internal_flag WHERE name = 'symspell.prefix_length' AND enabled;
    prefix_length := COALESCE(prefix_length, 6);

    SELECT value::INT INTO maxED FROM config.internal_flag WHERE name = 'symspell.max_edit_distance' AND enabled;
    maxED := COALESCE(maxED, 3);

    word_list := ARRAY_AGG(x) FROM search.symspell_parse_words(raw_input) x;

    -- Common case exact match test for preformance
    IF verbosity = 0 AND CARDINALITY(word_list) = 1 AND CHARACTER_LENGTH(word_list[1]) <= prefix_length THEN
        EXECUTE
          'SELECT  '||search_class||'_suggestions AS suggestions,
                   '||search_class||'_count AS count,
                   prefix_key
             FROM  search.symspell_dictionary
             WHERE prefix_key = $1
                   AND '||search_class||'_count >= $2
                   AND '||search_class||'_suggestions @> ARRAY[$1]'
          INTO entry USING evergreen.lowercase(word_list[1]), COALESCE(count_threshold,1);
        IF entry.prefix_key IS NOT NULL THEN
            output.lev_distance := 0; -- definitionally
            output.prefix_key := entry.prefix_key;
            output.prefix_key_count := entry.count;
            output.suggestion_count := entry.count;
            output.input := word_list[1];
            IF xfer_case THEN
                output.suggestion := search.symspell_transfer_casing(output.input, entry.prefix_key);
            ELSE
                output.suggestion := entry.prefix_key;
            END IF;
            output.norm_input := entry.prefix_key;
            output.qwerty_kb_match := 1;
            output.pg_trgm_sim := 1;
            output.soundex_sim := 1;
            RETURN NEXT output;
            RETURN;
        END IF;
    END IF;

    <<word_loop>>
    FOREACH word IN ARRAY word_list LOOP
        w_pos := w_pos + 1;
        input := evergreen.lowercase(word);
        i_len := CHARACTER_LENGTH(input);
        l_maxED := maxED;

        IF CHARACTER_LENGTH(input) > prefix_length THEN
            prefix_key := SUBSTRING(input FROM 1 FOR prefix_length);
            edit_list := ARRAY[input,prefix_key] || search.symspell_generate_edits(prefix_key, 1, l_maxED);
        ELSE
            edit_list := input || search.symspell_generate_edits(input, 1, l_maxED);
        END IF;

        SELECT ARRAY_AGG(x ORDER BY CHARACTER_LENGTH(x) DESC) INTO edit_list FROM UNNEST(edit_list) x;

        output_list := '{}';
        seen_list := '{}';
        global_ed := NULL;

        <<entry_key_loop>>
        FOREACH entry_key IN ARRAY edit_list LOOP
            smallest_ed := -1;
            IF global_ed IS NOT NULL THEN
                smallest_ed := global_ed;
            END IF;

            FOR entry IN EXECUTE
                'SELECT  '||search_class||'_suggestions AS suggestions,
                         '||search_class||'_count AS count,
                         prefix_key
                   FROM  search.symspell_dictionary
                   WHERE prefix_key = $1
                         AND '||search_class||'_suggestions IS NOT NULL'
                USING entry_key
            LOOP

                SELECT  HSTORE(
                            ARRAY_AGG(
                                ARRAY[s, evergreen.levenshtein_damerau_edistance(input,s,l_maxED)::TEXT]
                                    ORDER BY evergreen.levenshtein_damerau_edistance(input,s,l_maxED) DESC
                            )
                        )
                  INTO  good_suggs
                  FROM  UNNEST(entry.suggestions) s
                  WHERE (ABS(CHARACTER_LENGTH(s) - i_len) <= maxEd AND evergreen.levenshtein_damerau_edistance(input,s,l_maxED) BETWEEN 0 AND l_maxED)
                        AND NOT seen_list @> ARRAY[s];

                CONTINUE WHEN good_suggs IS NULL;

                FOR sugg, output.suggestion_count IN EXECUTE
                    'SELECT  prefix_key, '||search_class||'_count
                       FROM  search.symspell_dictionary
                       WHERE prefix_key = ANY ($1)
                             AND '||search_class||'_count >= $2'
                    USING AKEYS(good_suggs), COALESCE(count_threshold,1)
                LOOP

                    output.lev_distance := good_suggs->sugg;
                    seen_list := seen_list || sugg;

                    -- Track the smallest edit distance among suggestions from this prefix key.
                    IF smallest_ed = -1 OR output.lev_distance < smallest_ed THEN
                        smallest_ed := output.lev_distance;
                    END IF;

                    -- Track the smallest edit distance for all prefix keys for this word.
                    IF global_ed IS NULL OR smallest_ed < global_ed THEN
                        global_ed = smallest_ed;
                        -- And if low verbosity, ignore suggs with a larger distance from here on.
                        IF verbosity <= 1 THEN
                            l_maxED := global_ed;
                        END IF;
                    END IF;

                    -- Lev distance is our main similarity measure. While
                    -- trgm or soundex similarity could be the main filter,
                    -- Lev is both language agnostic and faster.
                    --
                    -- Here we will skip suggestions that have a longer edit distance
                    -- than the shortest we've already found. This is simply an
                    -- optimization that allows us to avoid further processing
                    -- of this entry. It would be filtered out later.
                    CONTINUE WHEN output.lev_distance > global_ed AND verbosity <= 1;

                    -- If we have an exact match on the suggestion key we can also avoid
                    -- some function calls.
                    IF output.lev_distance = 0 THEN
                        output.qwerty_kb_match := 1;
                        output.pg_trgm_sim := 1;
                        output.soundex_sim := 1;
                    ELSE
                        IF kbdist_weight THEN
                            output.qwerty_kb_match := evergreen.qwerty_keyboard_distance_match(input, sugg);
                        ELSE
                            output.qwerty_kb_match := 0;
                        END IF;
                        IF pg_trgm_weight THEN
                            output.pg_trgm_sim := similarity(input, sugg);
                        ELSE
                            output.pg_trgm_sim := 0;
                        END IF;
                        IF soundex_weight THEN
                            output.soundex_sim := difference(input, sugg) / 4.0;
                        ELSE
                            output.soundex_sim := 0;
                        END IF;
                    END IF;

                    -- Fill in some fields
                    IF xfer_case AND input <> word THEN
                        output.suggestion := search.symspell_transfer_casing(word, sugg);
                    ELSE
                        output.suggestion := sugg;
                    END IF;
                    output.prefix_key := entry.prefix_key;
                    output.prefix_key_count := entry.count;
                    output.input := word;
                    output.norm_input := input;
                    output.word_pos := w_pos;

                    -- We can't "cache" a set of generated records directly, so
                    -- here we build up an array of search.symspell_lookup_output
                    -- records that we can revivicate later as a table using UNNEST().
                    output_list := output_list || output;

                    EXIT entry_key_loop WHEN smallest_ed = 0 AND verbosity = 0; -- exact match early exit
                    CONTINUE entry_key_loop WHEN smallest_ed = 0 AND verbosity = 1; -- exact match early jump to the next key

                END LOOP; -- loop over suggestions
            END LOOP; -- loop over entries
        END LOOP; -- loop over entry_keys

        -- Now we're done examining this word
        IF verbosity = 0 THEN
            -- Return the "best" suggestion from the smallest edit
            -- distance group.  We define best based on the weighting
            -- of the non-lev similarity measures and use the suggestion
            -- use count to break ties.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC
                        LIMIT 1;
        ELSIF verbosity = 1 THEN
            -- Return all suggestions from the smallest
            -- edit distance group.
            RETURN QUERY
                SELECT * FROM UNNEST(output_list) WHERE lev_distance = smallest_ed
                    ORDER BY (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        ELSIF verbosity = 2 THEN
            -- Return everything we find, along with relevant stats
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        ELSIF verbosity = 3 THEN
            -- Return everything we find from the two smallest edit distance groups
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        ELSIF verbosity = 4 THEN
            -- Return everything we find from the two smallest edit distance groups that are NOT 0 distance
            RETURN QUERY
                SELECT * FROM UNNEST(output_list)
                    WHERE lev_distance IN (SELECT DISTINCT lev_distance FROM UNNEST(output_list) WHERE lev_distance > 0 ORDER BY 1 LIMIT 2)
                    ORDER BY lev_distance,
                        (soundex_sim * COALESCE(soundex_weight,0))
                            + (pg_trgm_sim * COALESCE(pg_trgm_weight,0))
                            + (qwerty_kb_match * COALESCE(kbdist_weight,0)) DESC,
                        suggestion_count DESC;
        END IF;
    END LOOP; -- loop over words
END;
$function$;



SELECT evergreen.upgrade_deps_block_check('1283', :eg_version); -- rhamby/ehardy/jboyer

UPDATE asset.call_number SET record = -1 WHERE id = -1 AND record != -1;

CREATE RULE protect_bre_id_neg1 AS ON UPDATE TO biblio.record_entry WHERE OLD.id = -1 DO INSTEAD NOTHING;
CREATE RULE protect_acl_id_1 AS ON UPDATE TO asset.copy_location WHERE OLD.id = 1 DO INSTEAD NOTHING;
CREATE RULE protect_acn_id_neg1 AS ON UPDATE TO asset.call_number WHERE OLD.id = -1 DO INSTEAD NOTHING;

CREATE OR REPLACE FUNCTION asset.merge_record_assets( target_record BIGINT, source_record BIGINT ) RETURNS INT AS $func$
DECLARE
    moved_objects INT := 0;
    source_cn     asset.call_number%ROWTYPE;
    target_cn     asset.call_number%ROWTYPE;
    metarec       metabib.metarecord%ROWTYPE;
    hold          action.hold_request%ROWTYPE;
    ser_rec       serial.record_entry%ROWTYPE;
    ser_sub       serial.subscription%ROWTYPE;
    acq_lineitem  acq.lineitem%ROWTYPE;
    acq_request   acq.user_request%ROWTYPE;
    booking       booking.resource_type%ROWTYPE;
    source_part   biblio.monograph_part%ROWTYPE;
    target_part   biblio.monograph_part%ROWTYPE;
    multi_home    biblio.peer_bib_copy_map%ROWTYPE;
    uri_count     INT := 0;
    counter       INT := 0;
    uri_datafield TEXT;
    uri_text      TEXT := '';
BEGIN

    -- we don't merge bib -1 
    IF target_record = -1 OR source_record = -1 THEN 
       RETURN 0;
    END IF;

    -- move any 856 entries on records that have at least one MARC-mapped URI entry
    SELECT  INTO uri_count COUNT(*)
      FROM  asset.uri_call_number_map m
            JOIN asset.call_number cn ON (m.call_number = cn.id)
      WHERE cn.record = source_record;

    IF uri_count > 0 THEN
        
        -- This returns more nodes than you might expect:
        -- 7 instead of 1 for an 856 with $u $y $9
        SELECT  COUNT(*) INTO counter
          FROM  oils_xpath_table(
                    'id',
                    'marc',
                    'biblio.record_entry',
                    '//*[@tag="856"]',
                    'id=' || source_record
                ) as t(i int,c text);
    
        FOR i IN 1 .. counter LOOP
            SELECT  '<datafield xmlns="http://www.loc.gov/MARC21/slim"' || 
            ' tag="856"' ||
            ' ind1="' || FIRST(ind1) || '"'  ||
            ' ind2="' || FIRST(ind2) || '">' ||
                        STRING_AGG(
                            '<subfield code="' || subfield || '">' ||
                            regexp_replace(
                                regexp_replace(
                                    regexp_replace(data,'&','&amp;','g'),
                                    '>', '&gt;', 'g'
                                ),
                                '<', '&lt;', 'g'
                            ) || '</subfield>', ''
                        ) || '</datafield>' INTO uri_datafield
              FROM  oils_xpath_table(
                        'id',
                        'marc',
                        'biblio.record_entry',
                        '//*[@tag="856"][position()=' || i || ']/@ind1|' ||
                        '//*[@tag="856"][position()=' || i || ']/@ind2|' ||
                        '//*[@tag="856"][position()=' || i || ']/*/@code|' ||
                        '//*[@tag="856"][position()=' || i || ']/*[@code]',
                        'id=' || source_record
                    ) as t(id int,ind1 text, ind2 text,subfield text,data text);

            -- As most of the results will be NULL, protect against NULLifying
            -- the valid content that we do generate
            uri_text := uri_text || COALESCE(uri_datafield, '');
        END LOOP;

        IF uri_text <> '' THEN
            UPDATE  biblio.record_entry
              SET   marc = regexp_replace(marc,'(</[^>]*record>)', uri_text || E'\\1')
              WHERE id = target_record;
        END IF;

    END IF;

    -- Find and move metarecords to the target record
    SELECT    INTO metarec *
      FROM    metabib.metarecord
      WHERE    master_record = source_record;

    IF FOUND THEN
        UPDATE    metabib.metarecord
          SET    master_record = target_record,
            mods = NULL
          WHERE    id = metarec.id;

        moved_objects := moved_objects + 1;
    END IF;

    -- Find call numbers attached to the source ...
    FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

        SELECT    INTO target_cn *
          FROM    asset.call_number
          WHERE    label = source_cn.label
            AND prefix = source_cn.prefix
            AND suffix = source_cn.suffix
            AND owning_lib = source_cn.owning_lib
            AND record = target_record
            AND NOT deleted;

        -- ... and if there's a conflicting one on the target ...
        IF FOUND THEN

            -- ... move the copies to that, and ...
            UPDATE    asset.copy
              SET    call_number = target_cn.id
              WHERE    call_number = source_cn.id;

            -- ... move V holds to the move-target call number
            FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
        
                UPDATE    action.hold_request
                  SET    target = target_cn.id
                  WHERE    id = hold.id;
        
                moved_objects := moved_objects + 1;
            END LOOP;
        
            UPDATE asset.call_number SET deleted = TRUE WHERE id = source_cn.id;

        -- ... if not ...
        ELSE
            -- ... just move the call number to the target record
            UPDATE    asset.call_number
              SET    record = target_record
              WHERE    id = source_cn.id;
        END IF;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find T holds targeting the source record ...
    FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

        -- ... and move them to the target record
        UPDATE    action.hold_request
          SET    target = target_record
          WHERE    id = hold.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find serial records targeting the source record ...
    FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
        -- ... and move them to the target record
        UPDATE    serial.record_entry
          SET    record = target_record
          WHERE    id = ser_rec.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find serial subscriptions targeting the source record ...
    FOR ser_sub IN SELECT * FROM serial.subscription WHERE record_entry = source_record LOOP
        -- ... and move them to the target record
        UPDATE    serial.subscription
          SET    record_entry = target_record
          WHERE    id = ser_sub.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find booking resource types targeting the source record ...
    FOR booking IN SELECT * FROM booking.resource_type WHERE record = source_record LOOP
        -- ... and move them to the target record
        UPDATE    booking.resource_type
          SET    record = target_record
          WHERE    id = booking.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find acq lineitems targeting the source record ...
    FOR acq_lineitem IN SELECT * FROM acq.lineitem WHERE eg_bib_id = source_record LOOP
        -- ... and move them to the target record
        UPDATE    acq.lineitem
          SET    eg_bib_id = target_record
          WHERE    id = acq_lineitem.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find acq user purchase requests targeting the source record ...
    FOR acq_request IN SELECT * FROM acq.user_request WHERE eg_bib = source_record LOOP
        -- ... and move them to the target record
        UPDATE    acq.user_request
          SET    eg_bib = target_record
          WHERE    id = acq_request.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find parts attached to the source ...
    FOR source_part IN SELECT * FROM biblio.monograph_part WHERE record = source_record LOOP

        SELECT    INTO target_part *
          FROM    biblio.monograph_part
          WHERE    label = source_part.label
            AND record = target_record;

        -- ... and if there's a conflicting one on the target ...
        IF FOUND THEN

            -- ... move the copy-part maps to that, and ...
            UPDATE    asset.copy_part_map
              SET    part = target_part.id
              WHERE    part = source_part.id;

            -- ... move P holds to the move-target part
            FOR hold IN SELECT * FROM action.hold_request WHERE target = source_part.id AND hold_type = 'P' LOOP
        
                UPDATE    action.hold_request
                  SET    target = target_part.id
                  WHERE    id = hold.id;
        
                moved_objects := moved_objects + 1;
            END LOOP;

        -- ... if not ...
        ELSE
            -- ... just move the part to the target record
            UPDATE    biblio.monograph_part
              SET    record = target_record
              WHERE    id = source_part.id;
        END IF;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- Find multi_home items attached to the source ...
    FOR multi_home IN SELECT * FROM biblio.peer_bib_copy_map WHERE peer_record = source_record LOOP
        -- ... and move them to the target record
        UPDATE    biblio.peer_bib_copy_map
          SET    peer_record = target_record
          WHERE    id = multi_home.id;

        moved_objects := moved_objects + 1;
    END LOOP;

    -- And delete mappings where the item's home bib was merged with the peer bib
    DELETE FROM biblio.peer_bib_copy_map WHERE peer_record = (
        SELECT (SELECT record FROM asset.call_number WHERE id = call_number)
        FROM asset.copy WHERE id = target_copy
    );

    -- Apply merge tracking
    UPDATE biblio.record_entry 
        SET merge_date = NOW() WHERE id = target_record;

    UPDATE biblio.record_entry
        SET merge_date = NOW(), merged_to = target_record
        WHERE id = source_record;

    -- replace book bag entries of source_record with target_record
    UPDATE container.biblio_record_entry_bucket_item
        SET target_biblio_record_entry = target_record
        WHERE bucket IN (SELECT id FROM container.biblio_record_entry_bucket WHERE btype = 'bookbag')
        AND target_biblio_record_entry = source_record;

    -- Finally, "delete" the source record
    UPDATE biblio.record_entry SET active = FALSE WHERE id = source_record;
    DELETE FROM biblio.record_entry WHERE id = source_record;

    -- That's all, folks!
    RETURN moved_objects;
END;
$func$ LANGUAGE plpgsql;




SELECT evergreen.upgrade_deps_block_check('1284', :eg_version); -- blake / terranm / jboyer

INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.void_item_deposit', 'circ',
    oils_i18n_gettext('circ.void_item_deposit',
        'Void item deposit fee on checkin',
        'coust', 'label'),
    oils_i18n_gettext('circ.void_item_deposit',
        'If a deposit was charged when checking out an item, void it when the item is returned',
        'coust', 'description'),
    'bool', null);



SELECT evergreen.upgrade_deps_block_check('1285', :eg_version);

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'circ.primary_item_value_field',
        'circ',
        oils_i18n_gettext(
            'circ.primary_item_value_field',
            'Use Item Price or Cost as Primary Item Value',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.primary_item_value_field',
            'Expects "price" or "cost" and defaults to price.  This refers to the corresponding field on the item record and gets used in such contexts as notices, max fine values when using item price caps (setting or fine rules), and long overdue, damaged, and lost billings.',
            'coust',
            'description'
        ),
        'string'
    );

INSERT into config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES (
        'circ.secondary_item_value_field',
        'circ',
        oils_i18n_gettext(
            'circ.secondary_item_value_field',
            'Use Item Price or Cost as Backup Item Value',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'circ.secondary_item_value_field',
            'Expects "price" or "cost", but defaults to neither.  This refers to the corresponding field on the item record and is used as a second-pass fall-through value when determining an item value.  If needed, Evergreen will still look at the "Default Item Price" setting as a final fallback.',
            'coust',
            'description'
        ),
        'string'
    );


SELECT evergreen.upgrade_deps_block_check('1286', :eg_version);

INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype )
VALUES
( 'eg.staffcat.search_filters', 'gui',
  oils_i18n_gettext(
    'eg.staffcat.search_filters',
    'Staff Catalog Search Filters',
    'coust', 'label'),
  oils_i18n_gettext(
    'eg.staffcat.search_filters',
    'Array of advanced search filters to display, e.g. ["item_lang","audience","lit_form"]',
    'coust', 'description'),
  'array' );





SELECT evergreen.upgrade_deps_block_check('1287', :eg_version);

 INSERT into config.org_unit_setting_type
 ( name, grp, label, description, datatype, fm_class ) VALUES
 ( 'lib.my_account_url', 'lib',
     oils_i18n_gettext('lib.my_account_url',
         'My Account URL (such as "https://example.com/eg/opac/login")',
         'coust', 'label'),
     oils_i18n_gettext('lib.my_account_url',
         'URL for a My Account link. Use a complete URL, such as "https://example.com/eg/opac/login".',
         'coust', 'description'),
     'string', null)
 ;


SELECT evergreen.upgrade_deps_block_check('1288', :eg_version);

-- stage a copy of notes, temporarily setting
-- the id to the negative value for later ausp
-- id munging
CREATE TABLE actor.XXXX_penalty_notes AS
    SELECT id * -1 AS id, usr, org_unit, set_date, note
    FROM actor.usr_standing_penalty
    WHERE NULLIF(BTRIM(note),'') IS NOT NULL;

ALTER TABLE actor.usr_standing_penalty ALTER COLUMN id SET DEFAULT nextval('actor.usr_message_id_seq'::regclass);
ALTER TABLE actor.usr_standing_penalty ADD COLUMN usr_message BIGINT REFERENCES actor.usr_message(id);
CREATE INDEX usr_standing_penalty_usr_message_idx ON actor.usr_standing_penalty (usr_message);
ALTER TABLE actor.usr_standing_penalty DROP COLUMN note;

-- munge ausp IDs and aum IDs so that they're disjoint sets
UPDATE actor.usr_standing_penalty SET id = id * -1; -- move them out of the way to avoid mid-statement collisions

WITH messages AS ( SELECT COALESCE(MAX(id), 0) AS max_id FROM actor.usr_message )
UPDATE actor.usr_standing_penalty SET id = id * -1 + messages.max_id FROM messages;

-- doing the same thing to the staging table because
-- we had to grab a copy of ausp.note first. We had
-- to grab that copy first because we're both ALTERing
-- and UPDATEing ausp, and all of the ALTER TABLEs
-- have to be done before we can modify data in the table
-- lest ALTER TABLE gets blocked by a pending trigger
-- event
WITH messages AS ( SELECT COALESCE(MAX(id), 0) AS max_id FROM actor.usr_message )
UPDATE actor.XXXX_penalty_notes SET id = id * -1 + messages.max_id FROM messages;

SELECT SETVAL('actor.usr_message_id_seq'::regclass, COALESCE((SELECT MAX(id) FROM actor.usr_standing_penalty) + 1, 1), FALSE);

ALTER TABLE actor.usr_message ADD COLUMN pub BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE actor.usr_message ADD COLUMN stop_date TIMESTAMP WITH TIME ZONE;
ALTER TABLE actor.usr_message ADD COLUMN editor	BIGINT REFERENCES actor.usr (id);
ALTER TABLE actor.usr_message ADD COLUMN edit_date TIMESTAMP WITH TIME ZONE;

DROP VIEW actor.usr_message_limited;
CREATE VIEW actor.usr_message_limited
AS SELECT * FROM actor.usr_message WHERE pub AND NOT deleted;

-- alright, let's set all existing user messages to public

UPDATE actor.usr_message SET pub = TRUE;

-- alright, let's migrate penalty notes to usr_messages and link the messages back to the penalties:

-- here is our staging table which will be shaped exactly like
-- actor.usr_message and use the same id sequence
CREATE TABLE actor.XXXX_usr_message_for_penalty_notes (
    LIKE actor.usr_message INCLUDING DEFAULTS 
);

INSERT INTO actor.XXXX_usr_message_for_penalty_notes (
    usr,
    title,
    message,
    create_date,
    sending_lib,
    pub
) SELECT
    usr,
    'Penalty Note ID ' || id,
    note,
    set_date,
    org_unit,
    FALSE
FROM
    actor.XXXX_penalty_notes
;

-- so far so good, let's push this into production

INSERT INTO actor.usr_message
    SELECT * FROM actor.XXXX_usr_message_for_penalty_notes;

-- and link the production penalties to these new user messages

UPDATE actor.usr_standing_penalty p SET usr_message = m.id
    FROM actor.XXXX_usr_message_for_penalty_notes m
    WHERE m.title = 'Penalty Note ID ' || p.id;

-- and remove the temporary overloading of the message title we used for this:

UPDATE
    actor.usr_message
SET
    title = message
WHERE
    id IN (SELECT id FROM actor.XXXX_usr_message_for_penalty_notes)
;

-- probably redundant here, but the spec calls for an assertion before removing
-- the note column from actor.usr_standing_penalty, so being extra cautious:
/*
do $$ begin
    assert (
        select count(*)
        from actor.XXXX_usr_message_for_penalty_notes
        where id not in (
            select id from actor.usr_message
        )
    ) = 0, 'failed migrating to actor.usr_message';
end; $$;
*/

-- combined view of actor.usr_standing_penalty and actor.usr_message for populating
-- staff Notes (formerly Messages) interface

CREATE VIEW actor.usr_message_penalty AS
SELECT -- ausp with or without messages
    ausp.id AS "id",
    ausp.id AS "ausp_id",
    aum.id AS "aum_id",
    ausp.org_unit AS "org_unit",
    ausp.org_unit AS "ausp_org_unit",
    aum.sending_lib AS "aum_sending_lib",
    ausp.usr AS "usr",
    ausp.usr as "ausp_usr",
    aum.usr as "aum_usr",
    ausp.standing_penalty AS "standing_penalty",
    ausp.staff AS "staff",
    ausp.set_date AS "create_date",
    ausp.set_date AS "ausp_set_date",
    aum.create_date AS "aum_create_date",
    ausp.stop_date AS "stop_date",
    ausp.stop_date AS "ausp_stop_date",
    aum.stop_date AS "aum_stop_date",
    ausp.usr_message AS "ausp_usr_message",
    aum.title AS "title",
    aum.message AS "message",
    aum.deleted AS "deleted",
    aum.read_date AS "read_date",
    aum.pub AS "pub",
    aum.editor AS "editor",
    aum.edit_date AS "edit_date"
FROM
    actor.usr_standing_penalty ausp
    LEFT JOIN actor.usr_message aum ON (ausp.usr_message = aum.id)
        UNION ALL
SELECT -- aum without penalties
    aum.id AS "id",
    NULL::INT AS "ausp_id",
    aum.id AS "aum_id",
    aum.sending_lib AS "org_unit",
    NULL::INT AS "ausp_org_unit",
    aum.sending_lib AS "aum_sending_lib",
    aum.usr AS "usr",
    NULL::INT as "ausp_usr",
    aum.usr as "aum_usr",
    NULL::INT AS "standing_penalty",
    NULL::INT AS "staff",
    aum.create_date AS "create_date",
    NULL::TIMESTAMPTZ AS "ausp_set_date",
    aum.create_date AS "aum_create_date",
    aum.stop_date AS "stop_date",
    NULL::TIMESTAMPTZ AS "ausp_stop_date",
    aum.stop_date AS "aum_stop_date",
    NULL::INT AS "ausp_usr_message",
    aum.title AS "title",
    aum.message AS "message",
    aum.deleted AS "deleted",
    aum.read_date AS "read_date",
    aum.pub AS "pub",
    aum.editor AS "editor",
    aum.edit_date AS "edit_date"
FROM
    actor.usr_message aum
    LEFT JOIN actor.usr_standing_penalty ausp ON (ausp.usr_message = aum.id)
WHERE NOT aum.deleted AND ausp.id IS NULL
;

-- fun part where we migrate the following alert messages:

CREATE TABLE actor.XXXX_note_and_message_consolidation AS
    SELECT id, home_ou, alert_message
    FROM actor.usr
    WHERE NOT deleted AND NULLIF(BTRIM(alert_message),'') IS NOT NULL;

-- here is our staging table which will be shaped exactly like
-- actor.usr_message and use the same id sequence
CREATE TABLE actor.XXXX_usr_message (
    LIKE actor.usr_message INCLUDING DEFAULTS 
);

INSERT INTO actor.XXXX_usr_message (
    usr,
    title,
    message,
    create_date,
    sending_lib,
    pub
) SELECT
    id,
    'converted Alert Message, real date unknown',
    alert_message,
    NOW(), -- best we can do
    1, -- it's this or home_ou
    FALSE
FROM
    actor.XXXX_note_and_message_consolidation
;

-- another staging table, but for actor.usr_standing_penalty
CREATE TABLE actor.XXXX_usr_standing_penalty (
    LIKE actor.usr_standing_penalty INCLUDING DEFAULTS 
);

INSERT INTO actor.XXXX_usr_standing_penalty (
    org_unit,
    usr,
    standing_penalty,
    staff,
    set_date,
    usr_message
) SELECT
    sending_lib,
    usr,
    20, -- ALERT_NOTE
    1, -- admin user, usually; best we can do
    create_date,
    id
FROM
    actor.XXXX_usr_message
;

-- so far so good, let's push these into production

INSERT INTO actor.usr_message
    SELECT * FROM actor.XXXX_usr_message;
INSERT INTO actor.usr_standing_penalty
    SELECT * FROM actor.XXXX_usr_standing_penalty;

-- probably redundant here, but the spec calls for an assertion before removing
-- the alert message column from actor.usr, so being extra cautious:
/*
do $$ begin
    assert (
        select count(*)
        from actor.XXXX_usr_message
        where id not in (
            select id from actor.usr_message
        )
    ) = 0, 'failed migrating to actor.usr_message';
end; $$;

do $$ begin
    assert (
        select count(*)
        from actor.XXXX_usr_standing_penalty
        where id not in (
            select id from actor.usr_standing_penalty
        )
    ) = 0, 'failed migrating to actor.usr_standing_penalty';
end; $$;
*/

-- WARNING: we're going to lose the history of alert_message
ALTER TABLE actor.usr DROP COLUMN alert_message CASCADE;
SELECT auditor.update_auditors();

-- fun part where we migrate actor.usr_notes as penalties to preserve
-- their creator, and then the private ones to private user messages.
-- For public notes, we try to link to existing user messages if we
-- can, but if we can't, we'll create new, but archived, user messages
-- for the note contents.

CREATE TABLE actor.XXXX_usr_message_for_private_notes (
    LIKE actor.usr_message INCLUDING DEFAULTS 
);
ALTER TABLE actor.XXXX_usr_message_for_private_notes ADD COLUMN orig_id BIGINT;
CREATE INDEX ON actor.XXXX_usr_message_for_private_notes (orig_id);

INSERT INTO actor.XXXX_usr_message_for_private_notes (
    orig_id,
    usr,
    title,
    message,
    create_date,
    sending_lib,
    pub
) SELECT
    id,
    usr,
    title,
    value,
    create_date,
    (select home_ou from actor.usr where id = creator), -- best we can do
    FALSE
FROM
    actor.usr_note
WHERE
    NOT pub
;

CREATE TABLE actor.XXXX_usr_message_for_unmatched_public_notes (
    LIKE actor.usr_message INCLUDING DEFAULTS 
);
ALTER TABLE actor.XXXX_usr_message_for_unmatched_public_notes ADD COLUMN orig_id BIGINT;
CREATE INDEX ON actor.XXXX_usr_message_for_unmatched_public_notes (orig_id);

INSERT INTO actor.XXXX_usr_message_for_unmatched_public_notes (
    orig_id,
    usr,
    title,
    message,
    create_date,
    deleted,
    sending_lib,
    pub
) SELECT
    id,
    usr,
    title,
    value,
    create_date,
    TRUE, -- the patron has likely already seen and deleted the corresponding usr_message
    (select home_ou from actor.usr where id = creator), -- best we can do
    FALSE
FROM
    actor.usr_note n
WHERE
    pub AND NOT EXISTS (SELECT 1 FROM actor.usr_message m WHERE n.usr = m.usr AND n.create_date = m.create_date)
;

-- now, in order to preserve the creator from usr_note, we want to create standing SILENT_NOTE penalties for
--  1) actor.XXXX_usr_message_for_private_notes and associated usr_note entries
--  2) actor.XXXX_usr_message_for_unmatched_public_notes and associated usr_note entries, but archive these
--  3) usr_note and usr_message entries that can be matched

CREATE TABLE actor.XXXX_usr_standing_penalties_for_notes (
    LIKE actor.usr_standing_penalty INCLUDING DEFAULTS 
);

--  1) actor.XXXX_usr_message_for_private_notes and associated usr_note entries
INSERT INTO actor.XXXX_usr_standing_penalties_for_notes (
    org_unit,
    usr,
    standing_penalty,
    staff,
    set_date,
    stop_date,
    usr_message
) SELECT
    m.sending_lib,
    m.usr,
    21, -- SILENT_NOTE
    n.creator,
    m.create_date,
    m.stop_date,
    m.id
FROM
    actor.usr_note n,
    actor.XXXX_usr_message_for_private_notes m
WHERE
    n.usr = m.usr AND n.id = m.orig_id AND NOT n.pub AND NOT m.pub
;

--  2) actor.XXXX_usr_message_for_unmatched_public_notes and associated usr_note entries, but archive these
INSERT INTO actor.XXXX_usr_standing_penalties_for_notes (
    org_unit,
    usr,
    standing_penalty,
    staff,
    set_date,
    stop_date,
    usr_message
) SELECT
    m.sending_lib,
    m.usr,
    21, -- SILENT_NOTE
    n.creator,
    m.create_date,
    m.stop_date,
    m.id
FROM
    actor.usr_note n,
    actor.XXXX_usr_message_for_unmatched_public_notes m
WHERE
    n.usr = m.usr AND n.id = m.orig_id AND n.pub AND m.pub
;

--  3) usr_note and usr_message entries that can be matched
INSERT INTO actor.XXXX_usr_standing_penalties_for_notes (
    org_unit,
    usr,
    standing_penalty,
    staff,
    set_date,
    stop_date,
    usr_message
) SELECT
    m.sending_lib,
    m.usr,
    21, -- SILENT_NOTE
    n.creator,
    m.create_date,
    m.stop_date,
    m.id
FROM
    actor.usr_note n
    JOIN actor.usr_message m ON (n.usr = m.usr AND n.id = m.id)
WHERE
    NOT EXISTS ( SELECT 1 FROM actor.XXXX_usr_message_for_private_notes WHERE id = m.id )
    AND NOT EXISTS ( SELECT 1 FROM actor.XXXX_usr_message_for_unmatched_public_notes WHERE id = m.id )
;

-- so far so good, let's push these into production

INSERT INTO actor.usr_message
    SELECT id, usr, title, message, create_date, deleted, read_date, sending_lib, pub, stop_date, editor, edit_date FROM actor.XXXX_usr_message_for_private_notes
    UNION SELECT id, usr, title, message, create_date, deleted, read_date, sending_lib, pub, stop_date, editor, edit_date FROM actor.XXXX_usr_message_for_unmatched_public_notes;
INSERT INTO actor.usr_standing_penalty
    SELECT * FROM actor.XXXX_usr_standing_penalties_for_notes;

-- probably redundant here, but the spec calls for an assertion before dropping
-- the actor.usr_note table, so being extra cautious:
/*
do $$ begin
    assert (
        select count(*)
        from actor.XXXX_usr_message_for_private_notes
        where id not in (
            select id from actor.usr_message
        )
    ) = 0, 'failed migrating to actor.usr_message';
end; $$;
*/

DROP TABLE actor.usr_note CASCADE;

-- preserve would-be collisions for migrating
-- ui.staff.require_initials.patron_info_notes
-- to ui.staff.require_initials.patron_standing_penalty

\o ui.staff.require_initials.patron_info_notes.collisions.txt
SELECT a.*
FROM actor.org_unit_setting a
WHERE
        a.name = 'ui.staff.require_initials.patron_info_notes'
    -- hits on org_unit
    AND a.org_unit IN (
        SELECT b.org_unit
        FROM actor.org_unit_setting b
        WHERE b.name = 'ui.staff.require_initials.patron_standing_penalty'
    )
    -- but doesn't hit on org_unit + value
    AND CONCAT_WS('|',a.org_unit::TEXT,a.value::TEXT) NOT IN (
        SELECT CONCAT_WS('|',b.org_unit::TEXT,b.value::TEXT)
        FROM actor.org_unit_setting b
        WHERE b.name = 'ui.staff.require_initials.patron_standing_penalty'
    );
\o

-- and preserve the _log data

\o ui.staff.require_initials.patron_info_notes.log_data.txt
SELECT *
FROM config.org_unit_setting_type_log
WHERE field_name = 'ui.staff.require_initials.patron_info_notes';
\o

-- migrate the non-collisions

INSERT INTO actor.org_unit_setting (org_unit, name, value)
SELECT a.org_unit, 'ui.staff.require_initials.patron_standing_penalty', a.value
FROM actor.org_unit_setting a
WHERE
        a.name = 'ui.staff.require_initials.patron_info_notes'
    AND a.org_unit NOT IN (
        SELECT b.org_unit
        FROM actor.org_unit_setting b
        WHERE b.name = 'ui.staff.require_initials.patron_standing_penalty'
    )
;

-- and now delete the old patron_info_notes settings

DELETE FROM actor.org_unit_setting
    WHERE name = 'ui.staff.require_initials.patron_info_notes';
DELETE FROM config.org_unit_setting_type_log
    WHERE field_name = 'ui.staff.require_initials.patron_info_notes';
DELETE FROM config.org_unit_setting_type
    WHERE name = 'ui.staff.require_initials.patron_info_notes';

-- relabel the org unit setting type

UPDATE config.org_unit_setting_type
SET
    label = oils_i18n_gettext('ui.staff.require_initials.patron_standing_penalty',
        'Require staff initials for entry/edit of patron standing penalties and notes.',
        'coust', 'label'),
    description = oils_i18n_gettext('ui.staff.require_initials.patron_standing_penalty',
        'Require staff initials for entry/edit of patron standing penalties and notes.',
        'coust', 'description')
WHERE
    name = 'ui.staff.require_initials.patron_standing_penalty'
;

-- preserve _log data for some different settings on their way out

\o ui.patron.edit.au.alert_message.show_suggest.log_data.txt
SELECT *
FROM config.org_unit_setting_type_log
WHERE field_name IN (
    'ui.patron.edit.au.alert_message.show',
    'ui.patron.edit.au.alert_message.suggest'
);
\o

-- remove patron editor alert message settings

DELETE FROM actor.org_unit_setting
    WHERE name = 'ui.patron.edit.au.alert_message.show';
DELETE FROM config.org_unit_setting_type_log
    WHERE field_name = 'ui.patron.edit.au.alert_message.show';
DELETE FROM config.org_unit_setting_type
    WHERE name = 'ui.patron.edit.au.alert_message.show';

DELETE FROM actor.org_unit_setting
    WHERE name = 'ui.patron.edit.au.alert_message.suggest';
DELETE FROM config.org_unit_setting_type_log
    WHERE field_name = 'ui.patron.edit.au.alert_message.suggest';
DELETE FROM config.org_unit_setting_type
    WHERE name = 'ui.patron.edit.au.alert_message.suggest';

-- comment these out if you want the staging tables to stick around
DROP TABLE actor.XXXX_note_and_message_consolidation;
DROP TABLE actor.XXXX_penalty_notes;
DROP TABLE actor.XXXX_usr_message_for_penalty_notes;
DROP TABLE actor.XXXX_usr_message;
DROP TABLE actor.XXXX_usr_standing_penalty;
DROP TABLE actor.XXXX_usr_message_for_private_notes;
DROP TABLE actor.XXXX_usr_message_for_unmatched_public_notes;
DROP TABLE actor.XXXX_usr_standing_penalties_for_notes;



SELECT evergreen.upgrade_deps_block_check('1289', :eg_version);


ALTER TABLE biblio.record_note ADD COLUMN deleted BOOLEAN DEFAULT FALSE;

INSERT INTO permission.perm_list ( id, code, description ) VALUES
( 633, 'CREATE_RECORD_NOTE', oils_i18n_gettext(633,
   'Allow the user to create a record note', 'ppl', 'description')),
( 634, 'UPDATE_RECORD_NOTE', oils_i18n_gettext(634,
   'Allow the user to update a record note', 'ppl', 'description')),
( 635, 'DELETE_RECORD_NOTE', oils_i18n_gettext(635,
   'Allow the user to delete a record note', 'ppl', 'description'));

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record.notes', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record.notes',
        'Grid Config: eg.grid.catalog.record.notes',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1290', :eg_version);

-- Add an active flag column

ALTER TABLE acq.funding_source ADD COLUMN active BOOL;

UPDATE acq.funding_source SET active = 't';

ALTER TABLE acq.funding_source ALTER COLUMN active SET DEFAULT TRUE;
ALTER TABLE acq.funding_source ALTER COLUMN active SET NOT NULL;


SELECT evergreen.upgrade_deps_block_check('1291', :eg_version);

--    context_usr_path        TEXT, -- for optimizing action_trigger.event
--    context_library_path    TEXT, -- '''
--    context_bib_path        TEXT, -- '''
ALTER TABLE action_trigger.event_definition ADD COLUMN context_usr_path TEXT;
ALTER TABLE action_trigger.event_definition ADD COLUMN context_library_path TEXT;
ALTER TABLE action_trigger.event_definition ADD COLUMN context_bib_path TEXT;

--    context_user    INT         REFERENCES actor.usr (id),
--    context_library INT         REFERENCES actor.org_unit (id),
--    context_bib     BIGINT      REFERENCES biblio.record_entry (id)
ALTER TABLE action_trigger.event ADD COLUMN context_user INT REFERENCES actor.usr (id);
ALTER TABLE action_trigger.event ADD COLUMN context_library INT REFERENCES actor.org_unit (id);
ALTER TABLE action_trigger.event ADD COLUMN context_bib BIGINT REFERENCES biblio.record_entry (id);
CREATE INDEX atev_context_user ON action_trigger.event (context_user);
CREATE INDEX atev_context_library ON action_trigger.event (context_library);

UPDATE
    action_trigger.event_definition
SET
    context_usr_path = 'usr',
    context_library_path = 'circ_lib',
    context_bib_path = 'target_copy.call_number.record'
WHERE
    hook IN (
        SELECT key FROM action_trigger.hook WHERE core_type = 'circ'
    )
;

UPDATE
    action_trigger.event_definition
SET
    context_usr_path = 'usr',
    context_library_path = 'pickup_lib',
    context_bib_path = 'bib_rec'
WHERE
    hook IN (
        SELECT key FROM action_trigger.hook WHERE core_type = 'ahr'
    )
;

-- Retroactively setting context_user and context_library on existing rows in action_trigger.event:
-- This is not done by default because it'll likely take a long time depending on the Evergreen
-- installation.  You may want to do this out-of-band with the upgrade if you want to do this at all.
--
-- \pset format unaligned
-- \t
-- \o update_action_trigger_events_for_circs.sql
-- SELECT 'UPDATE action_trigger.event e SET context_user = c.usr, context_library = c.circ_lib, context_bib = cn.record FROM action.circulation c, asset.copy i, asset.call_number cn WHERE c.id = e.target AND c.target_copy = i.id AND i.call_number = cn.id AND e.id = ' || e.id || ' RETURNING ' || e.id || ';' FROM action_trigger.event e, action.circulation c WHERE e.target = c.id AND e.event_def IN (SELECT id FROM action_trigger.event_definition WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'circ')) ORDER BY e.id DESC;
-- \o
-- \o update_action_trigger_events_for_holds.sql
-- SELECT 'UPDATE action_trigger.event e SET context_user = h.usr, context_library = h.pickup_lib, context_bib = r.bib_record FROM action.hold_request h, reporter.hold_request_record r WHERE h.id = e.target AND h.id = r.id AND e.id = ' || e.id || ' RETURNING ' || e.id || ';' FROM action_trigger.event e, action.hold_request h WHERE e.target = h.id AND e.event_def IN (SELECT id FROM action_trigger.event_definition WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'ahr')) ORDER BY e.id DESC;
-- \o



SELECT evergreen.upgrade_deps_block_check('1292', :eg_version);

CREATE OR REPLACE FUNCTION action.age_circ_on_delete () RETURNS TRIGGER AS $$
DECLARE
found char := 'N';
BEGIN

    -- If there are any renewals for this circulation, don't archive or delete
    -- it yet.   We'll do so later, when we archive and delete the renewals.

    SELECT 'Y' INTO found
    FROM action.circulation
    WHERE parent_circ = OLD.id
    LIMIT 1;

    IF found = 'Y' THEN
        RETURN NULL;  -- don't delete
	END IF;

    -- Archive a copy of the old row to action.aged_circulation

    INSERT INTO action.aged_circulation
        (id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining)
      SELECT
        id,usr_post_code, usr_home_ou, usr_profile, usr_birth_year, copy_call_number, copy_location,
        copy_owning_lib, copy_circ_lib, copy_bib_record, xact_start, xact_finish, target_copy,
        circ_lib, circ_staff, checkin_staff, checkin_lib, renewal_remaining, grace_period, due_date,
        stop_fines_time, checkin_time, create_time, duration, fine_interval, recurring_fine,
        max_fine, phone_renewal, desk_renewal, opac_renewal, duration_rule, recurring_fine_rule,
        max_fine_rule, stop_fines, workstation, checkin_workstation, checkin_scan_time, parent_circ,
        auto_renewal, auto_renewal_remaining
        FROM action.all_circulation WHERE id = OLD.id;

    -- Migrate billings and payments to aged tables

    SELECT 'Y' INTO found FROM config.global_flag 
        WHERE name = 'history.money.age_with_circs' AND enabled;

    IF found = 'Y' THEN
        PERFORM money.age_billings_and_payments_for_xact(OLD.id);
    END IF;

    -- Break the link with the user in action_trigger.event (warning: event_output may essentially have this information)
    UPDATE
        action_trigger.event e
    SET
        context_user = NULL
    FROM
        action.all_circulation c
    WHERE
            c.id = OLD.id
        AND e.context_user = c.usr
        AND e.target = c.id
        AND e.event_def IN (
            SELECT id
            FROM action_trigger.event_definition
            WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'circ')
        )
    ;

    RETURN OLD;
END;
$$ LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION actor.usr_purge_data(
	src_usr  IN INTEGER,
	specified_dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	renamable_row RECORD;
	dest_usr INTEGER;
BEGIN

	IF specified_dest_usr IS NULL THEN
		dest_usr := 1; -- Admin user on stock installs
	ELSE
		dest_usr := specified_dest_usr;
	END IF;

    -- action_trigger.event (even doing this, event_output may--and probably does--contain PII and should have a retention/removal policy)
    UPDATE action_trigger.event SET context_user = dest_usr WHERE context_user = src_usr;

	-- acq.*
	UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.lineitem SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.lineitem SET selector = dest_usr WHERE selector = src_usr;
	UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;
	DELETE FROM acq.lineitem_usr_attr_definition WHERE usr = src_usr;

	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE acq.picklist SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.picklist SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
	UPDATE acq.purchase_order SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.purchase_order SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.claim_event SET creator = dest_usr WHERE creator = src_usr;

	-- action.*
	DELETE FROM action.circulation WHERE usr = src_usr;
	UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
	UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
	UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;
	UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
	UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
	DELETE FROM action.hold_request WHERE usr = src_usr;
	UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
	UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.non_cataloged_circulation WHERE patron = src_usr;
	UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.survey_response WHERE usr = src_usr;
	UPDATE action.fieldset SET owner = dest_usr WHERE owner = src_usr;
	DELETE FROM action.usr_circ_history WHERE usr = src_usr;

	-- actor.*
	DELETE FROM actor.card WHERE usr = src_usr;
	DELETE FROM actor.stat_cat_entry_usr_map WHERE target_usr = src_usr;
	DELETE FROM actor.usr_privacy_waiver WHERE usr = src_usr;

	-- The following update is intended to avoid transient violations of a foreign
	-- key constraint, whereby actor.usr_address references itself.  It may not be
	-- necessary, but it does no harm.
	UPDATE actor.usr_address SET replaces = NULL
		WHERE usr = src_usr AND replaces IS NOT NULL;
	DELETE FROM actor.usr_address WHERE usr = src_usr;
	DELETE FROM actor.usr_note WHERE usr = src_usr;
	UPDATE actor.usr_note SET creator = dest_usr WHERE creator = src_usr;
	DELETE FROM actor.usr_org_unit_opt_in WHERE usr = src_usr;
	UPDATE actor.usr_org_unit_opt_in SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM actor.usr_setting WHERE usr = src_usr;
	DELETE FROM actor.usr_standing_penalty WHERE usr = src_usr;
	UPDATE actor.usr_standing_penalty SET staff = dest_usr WHERE staff = src_usr;

	-- asset.*
	UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;

	-- auditor.*
	DELETE FROM auditor.actor_usr_address_history WHERE id = src_usr;
	DELETE FROM auditor.actor_usr_history WHERE id = src_usr;
	UPDATE auditor.asset_call_number_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_call_number_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.asset_copy_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_copy_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.biblio_record_entry_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.biblio_record_entry_history SET editor  = dest_usr WHERE editor  = src_usr;

	-- biblio.*
	UPDATE biblio.record_entry SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_entry SET editor = dest_usr WHERE editor = src_usr;
	UPDATE biblio.record_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_note SET editor = dest_usr WHERE editor = src_usr;

	-- container.*
	-- Update buckets with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	DELETE FROM container.user_bucket_item WHERE target_user = src_usr;

	-- money.*
	DELETE FROM money.billable_xact WHERE usr = src_usr;
	DELETE FROM money.collections_tracker WHERE usr = src_usr;
	UPDATE money.collections_tracker SET collector = dest_usr WHERE collector = src_usr;

	-- permission.*
	DELETE FROM permission.usr_grp_map WHERE usr = src_usr;
	DELETE FROM permission.usr_object_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_work_ou_map WHERE usr = src_usr;

	-- reporter.*
	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
	-- do nothing
	END;

	-- vandelay.*
	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- NULL-ify addresses last so other cleanup (e.g. circ anonymization)
    -- can access the information before deletion.
	UPDATE actor.usr SET
		active = FALSE,
		card = NULL,
		mailing_address = NULL,
		billing_address = NULL
	WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;


SELECT evergreen.upgrade_deps_block_check('1293', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.item.event_grid', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.item.event_grid',
    'Grid Config: item.event_grid',
    'cwst', 'label')
), (
    'eg.grid.patron.event_grid', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.patron.event_grid',
    'Grid Config: patron.event_grid',
    'cwst', 'label')
);

DROP TRIGGER IF EXISTS action_trigger_event_context_item_trig ON action_trigger.event;

-- Create a NULLABLE version of the fake-copy-fkey trigger function.
CREATE OR REPLACE FUNCTION evergreen.fake_fkey_tgr () RETURNS TRIGGER AS $F$
DECLARE
    copy_id BIGINT;
BEGIN
    EXECUTE 'SELECT ($1).' || quote_ident(TG_ARGV[0]) INTO copy_id USING NEW;
    IF copy_id IS NOT NULL THEN
        PERFORM * FROM asset.copy WHERE id = copy_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Key (%.%=%) does not exist in asset.copy', TG_TABLE_SCHEMA, TG_TABLE_NAME, copy_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$F$ LANGUAGE PLPGSQL;


--    context_item_path        TEXT, -- for optimizing action_trigger.event
ALTER TABLE action_trigger.event_definition ADD COLUMN context_item_path TEXT;

--    context_item     BIGINT      REFERENCES asset.copy (id)
ALTER TABLE action_trigger.event ADD COLUMN context_item BIGINT;
CREATE INDEX atev_context_item ON action_trigger.event (context_item);

UPDATE
    action_trigger.event_definition
SET
    context_item_path = 'target_copy'
WHERE
    hook IN (
        SELECT key FROM action_trigger.hook WHERE core_type = 'circ'
    )
;

UPDATE
    action_trigger.event_definition
SET
    context_item_path = 'current_copy'
WHERE
    hook IN (
        SELECT key FROM action_trigger.hook WHERE core_type = 'ahr'
    )
;

-- Retroactively setting context_item on existing rows in action_trigger.event:
-- This is not done by default because it'll likely take a long time depending on the Evergreen
-- installation.  You may want to do this out-of-band with the upgrade if you want to do this at all.
--
-- \pset format unaligned
-- \t
-- \o update_action_trigger_events_for_circs.sql
-- SELECT 'UPDATE action_trigger.event e SET context_item = c.target_copy FROM action.circulation c WHERE c.id = e.target AND e.id = ' || e.id || ' RETURNING ' || e.id || ';' FROM action_trigger.event e, action.circulation c WHERE e.target = c.id AND e.event_def IN (SELECT id FROM action_trigger.event_definition WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'circ')) ORDER BY e.id DESC;
-- \o
-- \o update_action_trigger_events_for_holds.sql
-- SELECT 'UPDATE action_trigger.event e SET context_item = h.current_copy FROM action.hold_request h WHERE h.id = e.target AND e.id = ' || e.id || ' RETURNING ' || e.id || ';' FROM action_trigger.event e, action.hold_request h WHERE e.target = h.id AND e.event_def IN (SELECT id FROM action_trigger.event_definition WHERE hook in (SELECT key FROM action_trigger.hook WHERE core_type = 'ahr')) ORDER BY e.id DESC;
-- \o


CREATE TRIGGER action_trigger_event_context_item_trig
  AFTER INSERT OR UPDATE ON action_trigger.event
  FOR EACH ROW EXECUTE PROCEDURE evergreen.fake_fkey_tgr('context_item');


SELECT evergreen.upgrade_deps_block_check('1294', :eg_version); -- mmorgan / tlittle / JBoyer

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.container.carousel_org_unit', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.container.carousel_org_unit',
        'Grid Config: eg.grid.admin.local.container.carousel_org_unit',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.container.carousel', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.container.carousel',
        'Grid Config: eg.grid.admin.container.carousel',
        'cwst', 'label'
    )
), (
    'eg.grid.admin.server.config.carousel_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.server.config.carousel_type',
        'Grid Config: eg.grid.admin.server.config.carousel_type',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1295', :eg_version);

ALTER TABLE vandelay.merge_profile
    ADD COLUMN update_bib_editor BOOLEAN NOT NULL DEFAULT FALSE;

-- By default, updating bib source means updating the editor.
UPDATE vandelay.merge_profile SET update_bib_editor = update_bib_source;

CREATE OR REPLACE FUNCTION vandelay.overlay_bib_record 
    ( import_id BIGINT, eg_id BIGINT, merge_profile_id INT ) RETURNS BOOL AS $$
DECLARE
    editor_string   TEXT;
    editor_id       INT;
    v_marc          TEXT;
    v_bib_source    INT;
    update_fields   TEXT[];
    update_query    TEXT;
    update_bib_source BOOL;
    update_bib_editor BOOL;
BEGIN

    SELECT  q.marc, q.bib_source INTO v_marc, v_bib_source
      FROM  vandelay.queued_bib_record q
            JOIN vandelay.bib_match m ON (m.queued_record = q.id AND q.id = import_id)
      LIMIT 1;

    IF v_marc IS NULL THEN
        -- RAISE NOTICE 'no marc for vandelay or bib record';
        RETURN FALSE;
    END IF;

    IF NOT vandelay.template_overlay_bib_record( v_marc, eg_id, merge_profile_id) THEN
        -- no update happened, get outta here.
        RETURN FALSE;
    END IF;

    UPDATE  vandelay.queued_bib_record
      SET   imported_as = eg_id,
            import_time = NOW()
      WHERE id = import_id;

    SELECT q.update_bib_source INTO update_bib_source 
        FROM vandelay.merge_profile q where q.id = merge_profile_Id;

    IF update_bib_source AND v_bib_source IS NOT NULL THEN
        update_fields := ARRAY_APPEND(update_fields, 'source = ' || v_bib_source);
    END IF;

    SELECT q.update_bib_editor INTO update_bib_editor 
        FROM vandelay.merge_profile q where q.id = merge_profile_Id;

    IF update_bib_editor THEN

        editor_string := (oils_xpath('//*[@tag="905"]/*[@code="u"]/text()',v_marc))[1];

        IF editor_string IS NOT NULL AND editor_string <> '' THEN
            SELECT usr INTO editor_id FROM actor.card WHERE barcode = editor_string;

            IF editor_id IS NULL THEN
                SELECT id INTO editor_id FROM actor.usr WHERE usrname = editor_string;
            END IF;

            IF editor_id IS NOT NULL THEN
                --only update the edit date if we have a valid editor
                update_fields := ARRAY_APPEND(
                    update_fields, 'editor = ' || editor_id || ', edit_date = NOW()');
            END IF;
        END IF;
    END IF;

    IF ARRAY_LENGTH(update_fields, 1) > 0 THEN
        update_query := 'UPDATE biblio.record_entry SET ' || 
            ARRAY_TO_STRING(update_fields, ',') || ' WHERE id = ' || eg_id || ';';
        EXECUTE update_query;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('1296', :eg_version);

CREATE OR REPLACE VIEW reporter.demographic AS
SELECT  u.id,
    u.dob,
    CASE
        WHEN u.dob IS NULL
            THEN 'Adult'
        WHEN AGE(u.dob) > '18 years'::INTERVAL
            THEN 'Adult'
        ELSE 'Juvenile'
    END AS general_division,
    CASE
        WHEN u.dob IS NULL
            THEN 'No Date of Birth Entered'::text
        WHEN age(u.dob::timestamp with time zone) >= '0 years'::interval and age(u.dob::timestamp with time zone) < '6 years'::interval
            THEN 'Child 0-5 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '6 years'::interval and age(u.dob::timestamp with time zone) < '13 years'::interval
            THEN 'Child 6-12 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '13 years'::interval and age(u.dob::timestamp with time zone) < '18 years'::interval
            THEN 'Teen 13-17 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '18 years'::interval and age(u.dob::timestamp with time zone) < '26 years'::interval
            THEN 'Adult 18-25 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '26 years'::interval and age(u.dob::timestamp with time zone) < '50 years'::interval
            THEN 'Adult 26-49 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '50 years'::interval and age(u.dob::timestamp with time zone) < '60 years'::interval
            THEN 'Adult 50-59 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '60 years'::interval and age(u.dob::timestamp with time zone) < '70  years'::interval
            THEN 'Adult 60-69 Years Old'::text
        WHEN age(u.dob::timestamp with time zone) >= '70 years'::interval
            THEN 'Adult 70+'::text
        ELSE NULL::text
    END AS age_division
    FROM actor.usr u;


SELECT evergreen.upgrade_deps_block_check('1297', :eg_version);

INSERT INTO config.org_unit_setting_type (
    name, grp, label, description, datatype
) VALUES (
    'circ.staff_placed_holds_default_to_ws_ou',
    'circ',
    oils_i18n_gettext(
        'circ.staff_placed_holds_default_to_ws_ou',
        'Workstation OU is the default for staff-placed holds',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.staff_placed_holds_default_to_ws_ou',
        'For staff-placed holds, regardless of the patron preferred pickup location, the staff workstation OU is the default pickup location',
        'coust',
        'description'
    ),
    'bool'
);


SELECT evergreen.upgrade_deps_block_check('1298', :eg_version);

ALTER TYPE metabib.field_entry_template ADD ATTRIBUTE browse_nocase BOOL CASCADE;

ALTER TABLE config.metabib_field ADD COLUMN browse_nocase BOOL NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry (
    rid BIGINT,
    default_joiner TEXT,
    field_types TEXT[],
    only_fields INT[]
) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    display_text TEXT;
    browse_text TEXT;
    sort_value  TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    authority_text TEXT;
    authority_link BIGINT;
    output_row  metabib.field_entry_template%ROWTYPE;
    process_idx BOOL;
BEGIN

    -- Start out with no field-use bools set
    output_row.browse_nocase = FALSE;
    output_row.browse_field = FALSE;
    output_row.facet_field = FALSE;
    output_row.display_field = FALSE;
    output_row.search_field = FALSE;

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field WHERE id = ANY (only_fields) ORDER BY format LOOP
        CONTINUE WHEN idx.xpath IS NULL OR idx.xpath = ''; -- pure virtual field

        process_idx := FALSE;
        IF idx.display_field AND 'display' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.browse_field AND 'browse' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.search_field AND 'search' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.facet_field AND 'facet' = ANY (field_types) THEN process_idx = TRUE; END IF;
        CONTINUE WHEN process_idx = FALSE; -- disabled for all types

        joiner := COALESCE(idx.joiner, default_joiner);

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(bib.marc,xfrm.xslt);
            ELSE
                transformed_xml := bib.marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        raw_text := NULL;
        FOR xml_node IN SELECT x FROM unnest(xml_node_list) AS x LOOP
            CONTINUE WHEN xml_node !~ E'^\\s*<';

            -- XXX much of this should be moved into oils_xpath_string...
            curr_text := ARRAY_TO_STRING(evergreen.array_remove_item_by_value(evergreen.array_remove_item_by_value(
                oils_xpath( '//text()', -- get the content of all the nodes within the main selected node
                    REGEXP_REPLACE( xml_node, E'\\s+', ' ', 'g' ) -- Translate adjacent whitespace to a single space
                ), ' '), ''),  -- throw away morally empty (bankrupt?) strings
                joiner
            );

            CONTINUE WHEN curr_text IS NULL OR curr_text = '';

            IF raw_text IS NOT NULL THEN
                raw_text := raw_text || joiner;
            END IF;

            raw_text := COALESCE(raw_text,'') || curr_text;

            -- autosuggest/metabib.browse_entry
            IF idx.browse_field THEN
                output_row.browse_nocase = idx.browse_nocase;

                IF idx.browse_xpath IS NOT NULL AND idx.browse_xpath <> '' THEN
                    browse_text := oils_xpath_string( idx.browse_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    browse_text := curr_text;
                END IF;

                IF idx.browse_sort_xpath IS NOT NULL AND
                    idx.browse_sort_xpath <> '' THEN

                    sort_value := oils_xpath_string(
                        idx.browse_sort_xpath, xml_node, joiner,
                        ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                    );
                ELSE
                    sort_value := browse_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(browse_text, E'\\s+', ' ', 'g'));
                output_row.sort_value :=
                    public.naco_normalize(sort_value);

                output_row.authority := NULL;

                IF idx.authority_xpath IS NOT NULL AND idx.authority_xpath <> '' THEN
                    authority_text := oils_xpath_string(
                        idx.authority_xpath, xml_node, joiner,
                        ARRAY[
                            ARRAY[xfrm.prefix, xfrm.namespace_uri],
                            ARRAY['xlink','http://www.w3.org/1999/xlink']
                        ]
                    );

                    IF authority_text ~ '^\d+$' THEN
                        authority_link := authority_text::BIGINT;
                        PERFORM * FROM authority.record_entry WHERE id = authority_link;
                        IF FOUND THEN
                            output_row.authority := authority_link;
                        END IF;
                    END IF;

                END IF;

                output_row.browse_field = TRUE;
                -- Returning browse rows with search_field = true for search+browse
                -- configs allows us to retain granularity of being able to search
                -- browse fields with "starts with" type operators (for example, for
                -- titles of songs in music albums)
                IF idx.search_field THEN
                    output_row.search_field = TRUE;
                END IF;
                RETURN NEXT output_row;
                output_row.browse_nocase = FALSE;
                output_row.browse_field = FALSE;
                output_row.search_field = FALSE;
                output_row.sort_value := NULL;
            END IF;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                IF idx.facet_xpath IS NOT NULL AND idx.facet_xpath <> '' THEN
                    facet_text := oils_xpath_string( idx.facet_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    facet_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(facet_text, E'\\s+', ' ', 'g'));

                output_row.facet_field = TRUE;
                RETURN NEXT output_row;
                output_row.facet_field = FALSE;
            END IF;

            -- insert raw node text for display
            IF idx.display_field THEN

                IF idx.display_xpath IS NOT NULL AND idx.display_xpath <> '' THEN
                    display_text := oils_xpath_string( idx.display_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    display_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(display_text, E'\\s+', ' ', 'g'));

                output_row.display_field = TRUE;
                RETURN NEXT output_row;
                output_row.display_field = FALSE;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            output_row.search_field = TRUE;
            RETURN NEXT output_row;
            output_row.search_field = FALSE;
        END IF;

    END LOOP;

END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION metabib.reingest_metabib_field_entries( 
    bib_id BIGINT,
    skip_facet BOOL DEFAULT FALSE, 
    skip_display BOOL DEFAULT FALSE,
    skip_browse BOOL DEFAULT FALSE, 
    skip_search BOOL DEFAULT FALSE,
    only_fields INT[] DEFAULT '{}'::INT[]
) RETURNS VOID AS $func$
DECLARE
    fclass          RECORD;
    ind_data        metabib.field_entry_template%ROWTYPE;
    mbe_row         metabib.browse_entry%ROWTYPE;
    mbe_id          BIGINT;
    b_skip_facet    BOOL;
    b_skip_display    BOOL;
    b_skip_browse   BOOL;
    b_skip_search   BOOL;
    value_prepped   TEXT;
    field_list      INT[] := only_fields;
    field_types     TEXT[] := '{}'::TEXT[];
BEGIN

    IF field_list = '{}'::INT[] THEN
        SELECT ARRAY_AGG(id) INTO field_list FROM config.metabib_field;
    END IF;

    SELECT COALESCE(NULLIF(skip_facet, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_facet_indexing' AND enabled)) INTO b_skip_facet;
    SELECT COALESCE(NULLIF(skip_display, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_display_indexing' AND enabled)) INTO b_skip_display;
    SELECT COALESCE(NULLIF(skip_browse, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_browse_indexing' AND enabled)) INTO b_skip_browse;
    SELECT COALESCE(NULLIF(skip_search, FALSE), EXISTS (SELECT enabled FROM config.internal_flag WHERE name =  'ingest.skip_search_indexing' AND enabled)) INTO b_skip_search;

    IF NOT b_skip_facet THEN field_types := field_types || '{facet}'; END IF;
    IF NOT b_skip_display THEN field_types := field_types || '{display}'; END IF;
    IF NOT b_skip_browse THEN field_types := field_types || '{browse}'; END IF;
    IF NOT b_skip_search THEN field_types := field_types || '{search}'; END IF;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.assume_inserts_only' AND enabled;
    IF NOT FOUND THEN
        IF NOT b_skip_search THEN
            FOR fclass IN SELECT * FROM config.metabib_class LOOP
                -- RAISE NOTICE 'Emptying out %', fclass.name;
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_display THEN
            DELETE FROM metabib.display_entry WHERE source = bib_id;
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id;
        END IF;
    END IF;

    FOR ind_data IN SELECT * FROM biblio.extract_metabib_field_entry( bib_id, ' ', field_types, field_list ) LOOP

	-- don't store what has been normalized away
        CONTINUE WHEN ind_data.value IS NULL;

        IF ind_data.field < 0 THEN
            ind_data.field = -1 * ind_data.field;
        END IF;

        IF ind_data.facet_field AND NOT b_skip_facet THEN
            INSERT INTO metabib.facet_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;

        IF ind_data.display_field AND NOT b_skip_display THEN
            INSERT INTO metabib.display_entry (field, source, value)
                VALUES (ind_data.field, ind_data.source, ind_data.value);
        END IF;


        IF ind_data.browse_field AND NOT b_skip_browse THEN
            -- A caveat about this SELECT: this should take care of replacing
            -- old mbe rows when data changes, but not if normalization (by
            -- which I mean specifically the output of
            -- evergreen.oils_tsearch2()) changes.  It may or may not be
            -- expensive to add a comparison of index_vector to index_vector
            -- to the WHERE clause below.

            CONTINUE WHEN ind_data.sort_value IS NULL;

            value_prepped := metabib.browse_normalize(ind_data.value, ind_data.field);
            IF ind_data.browse_nocase THEN
                SELECT INTO mbe_row * FROM metabib.browse_entry
                    WHERE evergreen.lowercase(value) = evergreen.lowercase(value_prepped) AND sort_value = ind_data.sort_value
                    ORDER BY sort_value, value LIMIT 1; -- gotta pick something, I guess
            ELSE
                SELECT INTO mbe_row * FROM metabib.browse_entry
                    WHERE value = value_prepped AND sort_value = ind_data.sort_value;
            END IF;

            IF FOUND THEN
                mbe_id := mbe_row.id;
            ELSE
                INSERT INTO metabib.browse_entry
                    ( value, sort_value ) VALUES
                    ( value_prepped, ind_data.sort_value );

                mbe_id := CURRVAL('metabib.browse_entry_id_seq'::REGCLASS);
            END IF;

            INSERT INTO metabib.browse_entry_def_map (entry, def, source, authority)
                VALUES (mbe_id, ind_data.field, ind_data.source, ind_data.authority);
        END IF;

        IF ind_data.search_field AND NOT b_skip_search THEN
            -- Avoid inserting duplicate rows
            EXECUTE 'SELECT 1 FROM metabib.' || ind_data.field_class ||
                '_field_entry WHERE field = $1 AND source = $2 AND value = $3'
                INTO mbe_id USING ind_data.field, ind_data.source, ind_data.value;
                -- RAISE NOTICE 'Search for an already matching row returned %', mbe_id;
            IF mbe_id IS NULL THEN
                EXECUTE $$
                INSERT INTO metabib.$$ || ind_data.field_class || $$_field_entry (field, source, value)
                    VALUES ($$ ||
                        quote_literal(ind_data.field) || $$, $$ ||
                        quote_literal(ind_data.source) || $$, $$ ||
                        quote_literal(ind_data.value) ||
                    $$);$$;
            END IF;
        END IF;

    END LOOP;

    IF NOT b_skip_search THEN
        PERFORM metabib.update_combined_index_vectors(bib_id);
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('1299', :eg_version);

CREATE OR REPLACE FUNCTION vandelay.strip_field(xml text, field text) RETURNS text AS $f$

    use MARC::Record;
    use MARC::File::XML (BinaryEncoding => 'UTF-8');
    use MARC::Charset;
    use strict;

    MARC::Charset->assume_unicode(1);

    my $xml = shift;
    my $r = MARC::Record->new_from_xml( $xml );

    return $xml unless ($r);

    my $field_spec = shift;
    my @field_list = split(',', $field_spec);

    my %fields;
    for my $f (@field_list) {
        $f =~ s/^\s*//; $f =~ s/\s*$//;
        if ($f =~ /^(.{3})(\w*)(?:\[([^]]*)\])?$/) {
            my $field = $1;
            $field =~ s/\s+//;
            my $sf = $2;
            $sf =~ s/\s+//;
            my $matches = $3;
            $matches =~ s/^\s*//; $matches =~ s/\s*$//;
            $fields{$field} = { sf => [ split('', $sf) ] };
            if ($matches) {
                for my $match (split('&&', $matches)) {
                    $match =~ s/^\s*//; $match =~ s/\s*$//;
                    my ($msf,$mre) = split('~', $match);
                    if (length($msf) > 0 and length($mre) > 0) {
                        $msf =~ s/^\s*//; $msf =~ s/\s*$//;
                        $mre =~ s/^\s*//; $mre =~ s/\s*$//;
                        $fields{$field}{match}{$msf} = qr/$mre/;
                    }
                }
            }
        }
    }

    for my $f ( keys %fields) {
        for my $to_field ($r->field( $f )) {
            if (exists($fields{$f}{match})) {
                my @match_list = grep { $to_field->subfield($_) =~ $fields{$f}{match}{$_} } keys %{$fields{$f}{match}};
                next unless (scalar(@match_list) == scalar(keys %{$fields{$f}{match}}));
            }

            if ( @{$fields{$f}{sf}} ) {
                $to_field->delete_subfield(code => $fields{$f}{sf});
            } else {
                $r->delete_field( $to_field );
            }
        }
    }

    $xml = $r->as_xml_record;
    $xml =~ s/^<\?.+?\?>$//mo;
    $xml =~ s/\n//sgo;
    $xml =~ s/>\s+</></sgo;

    return $xml;

$f$ LANGUAGE plperlu;




SELECT evergreen.upgrade_deps_block_check('1300', :eg_version);

-- NOTE: If the template ID requires changing, beware it appears in
-- 3 places below.

INSERT INTO config.print_template 
    (id, name, locale, active, owner, label, template) 
VALUES (
    4, 'hold_pull_list', 'en-US', TRUE,
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    oils_i18n_gettext(4, 'Hold Pull List ', 'cpt', 'label'),
    ''
);

UPDATE config.print_template SET template = 
$TEMPLATE$
[%-
    USE date;
    SET holds = template_data;
    # template_data is an arry of wide_hold hashes.
-%]
<div>
  <style>
    #holds-pull-list-table td { 
      padding: 5px; 
      border: 1px solid rgba(0,0,0,.05);
    }
  </style>
  <table id="holds-pull-list-table">
    <thead>
      <tr>
        <th>Type</th>
        <th>Title</th>
        <th>Author</th>
        <th>Shelf Location</th>
        <th>Call Number</th>
        <th>Barcode/Part</th>
      </tr>
    </thead>
    <tbody>
      [% FOR hold IN holds %]
      <tr>
        <td>[% hold.hold_type %]</td>
        <td style="width: 30%">[% hold.title %]</td>
        <td style="width: 25%">[% hold.author %]</td>
        <td>[% hold.acpl_name %]</td>
        <td>[% hold.cn_full_label %]</td>
        <td>[% hold.cp_barcode %][% IF hold.p_label %]/[% hold.p_label %][% END %]</td>
      </tr>
      [% END %]
    </tbody>
  </table>
</div>
$TEMPLATE$ WHERE id = 4;

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.circ.holds.pull_list', 'gui', 'object', 
    oils_i18n_gettext(
        'circ.holds.pull_list',
        'Hold Pull List Grid Settings',
        'cwst', 'label'
    )
), (
    'circ.holds.pull_list.prefetch', 'gui', 'bool', 
    oils_i18n_gettext(
        'circ.holds.pull_list.prefetch',
        'Hold Pull List Prefetch Preference',
        'cwst', 'label'
    )
);



SELECT evergreen.upgrade_deps_block_check('1301', :eg_version);

CREATE OR REPLACE FUNCTION biblio.extract_metabib_field_entry (
    rid BIGINT,
    default_joiner TEXT,
    field_types TEXT[],
    only_fields INT[]
) RETURNS SETOF metabib.field_entry_template AS $func$
DECLARE
    bib     biblio.record_entry%ROWTYPE;
    idx     config.metabib_field%ROWTYPE;
    xfrm        config.xml_transform%ROWTYPE;
    prev_xfrm   TEXT;
    transformed_xml TEXT;
    xml_node    TEXT;
    xml_node_list   TEXT[];
    facet_text  TEXT;
    display_text TEXT;
    browse_text TEXT;
    sort_value  TEXT;
    raw_text    TEXT;
    curr_text   TEXT;
    joiner      TEXT := default_joiner; -- XXX will index defs supply a joiner?
    authority_text TEXT;
    authority_link BIGINT;
    output_row  metabib.field_entry_template%ROWTYPE;
    process_idx BOOL;
BEGIN

    -- Start out with no field-use bools set
    output_row.browse_nocase = FALSE;
    output_row.browse_field = FALSE;
    output_row.facet_field = FALSE;
    output_row.display_field = FALSE;
    output_row.search_field = FALSE;

    -- Get the record
    SELECT INTO bib * FROM biblio.record_entry WHERE id = rid;

    -- Loop over the indexing entries
    FOR idx IN SELECT * FROM config.metabib_field WHERE id = ANY (only_fields) ORDER BY format LOOP
        CONTINUE WHEN idx.xpath IS NULL OR idx.xpath = ''; -- pure virtual field

        process_idx := FALSE;
        IF idx.display_field AND 'display' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.browse_field AND 'browse' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.search_field AND 'search' = ANY (field_types) THEN process_idx = TRUE; END IF;
        IF idx.facet_field AND 'facet' = ANY (field_types) THEN process_idx = TRUE; END IF;
        CONTINUE WHEN process_idx = FALSE; -- disabled for all types

        joiner := COALESCE(idx.joiner, default_joiner);

        SELECT INTO xfrm * from config.xml_transform WHERE name = idx.format;

        -- See if we can skip the XSLT ... it's expensive
        IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
            -- Can't skip the transform
            IF xfrm.xslt <> '---' THEN
                transformed_xml := oils_xslt_process(bib.marc,xfrm.xslt);
            ELSE
                transformed_xml := bib.marc;
            END IF;

            prev_xfrm := xfrm.name;
        END IF;

        xml_node_list := oils_xpath( idx.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );

        raw_text := NULL;
        FOR xml_node IN SELECT x FROM unnest(xml_node_list) AS x LOOP
            CONTINUE WHEN xml_node !~ E'^\\s*<';

            -- XXX much of this should be moved into oils_xpath_string...
            curr_text := ARRAY_TO_STRING(array_remove(array_remove(
                oils_xpath( '//text()', -- get the content of all the nodes within the main selected node
                    REGEXP_REPLACE( xml_node, E'\\s+', ' ', 'g' ) -- Translate adjacent whitespace to a single space
                ), ' '), ''),  -- throw away morally empty (bankrupt?) strings
                joiner
            );

            CONTINUE WHEN curr_text IS NULL OR curr_text = '';

            IF raw_text IS NOT NULL THEN
                raw_text := raw_text || joiner;
            END IF;

            raw_text := COALESCE(raw_text,'') || curr_text;

            -- autosuggest/metabib.browse_entry
            IF idx.browse_field THEN
                output_row.browse_nocase = idx.browse_nocase;

                IF idx.browse_xpath IS NOT NULL AND idx.browse_xpath <> '' THEN
                    browse_text := oils_xpath_string( idx.browse_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    browse_text := curr_text;
                END IF;

                IF idx.browse_sort_xpath IS NOT NULL AND
                    idx.browse_sort_xpath <> '' THEN

                    sort_value := oils_xpath_string(
                        idx.browse_sort_xpath, xml_node, joiner,
                        ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                    );
                ELSE
                    sort_value := browse_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(browse_text, E'\\s+', ' ', 'g'));
                output_row.sort_value :=
                    public.naco_normalize(sort_value);

                output_row.authority := NULL;

                IF idx.authority_xpath IS NOT NULL AND idx.authority_xpath <> '' THEN
                    authority_text := oils_xpath_string(
                        idx.authority_xpath, xml_node, joiner,
                        ARRAY[
                            ARRAY[xfrm.prefix, xfrm.namespace_uri],
                            ARRAY['xlink','http://www.w3.org/1999/xlink']
                        ]
                    );

                    IF authority_text ~ '^\d+$' THEN
                        authority_link := authority_text::BIGINT;
                        PERFORM * FROM authority.record_entry WHERE id = authority_link;
                        IF FOUND THEN
                            output_row.authority := authority_link;
                        END IF;
                    END IF;

                END IF;

                output_row.browse_field = TRUE;
                -- Returning browse rows with search_field = true for search+browse
                -- configs allows us to retain granularity of being able to search
                -- browse fields with "starts with" type operators (for example, for
                -- titles of songs in music albums)
                IF idx.search_field THEN
                    output_row.search_field = TRUE;
                END IF;
                RETURN NEXT output_row;
                output_row.browse_nocase = FALSE;
                output_row.browse_field = FALSE;
                output_row.search_field = FALSE;
                output_row.sort_value := NULL;
            END IF;

            -- insert raw node text for faceting
            IF idx.facet_field THEN

                IF idx.facet_xpath IS NOT NULL AND idx.facet_xpath <> '' THEN
                    facet_text := oils_xpath_string( idx.facet_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    facet_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(facet_text, E'\\s+', ' ', 'g'));

                output_row.facet_field = TRUE;
                RETURN NEXT output_row;
                output_row.facet_field = FALSE;
            END IF;

            -- insert raw node text for display
            IF idx.display_field THEN

                IF idx.display_xpath IS NOT NULL AND idx.display_xpath <> '' THEN
                    display_text := oils_xpath_string( idx.display_xpath, xml_node, joiner, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]] );
                ELSE
                    display_text := curr_text;
                END IF;

                output_row.field_class = idx.field_class;
                output_row.field = -1 * idx.id;
                output_row.source = rid;
                output_row.value = BTRIM(REGEXP_REPLACE(display_text, E'\\s+', ' ', 'g'));

                output_row.display_field = TRUE;
                RETURN NEXT output_row;
                output_row.display_field = FALSE;
            END IF;

        END LOOP;

        CONTINUE WHEN raw_text IS NULL OR raw_text = '';

        -- insert combined node text for searching
        IF idx.search_field THEN
            output_row.field_class = idx.field_class;
            output_row.field = idx.id;
            output_row.source = rid;
            output_row.value = BTRIM(REGEXP_REPLACE(raw_text, E'\\s+', ' ', 'g'));

            output_row.search_field = TRUE;
            RETURN NEXT output_row;
            output_row.search_field = FALSE;
        END IF;

    END LOOP;

END;
$func$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('1302', :eg_version);

UPDATE config.org_unit_setting_type
    SET description = oils_i18n_gettext(
        'ui.circ.items_out.longoverdue',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.longoverdue';

UPDATE config.org_unit_setting_type
    set description = oils_i18n_gettext(
        'ui.circ.items_out.lost',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.lost';

UPDATE config.org_unit_setting_type
    set description = oils_i18n_gettext(
        'ui.circ.items_out.claimsreturned',
        'Value is a numeric code, describing: A. In which tab ("Items Checked Out", '||
        'or "Other/Special Circulations") the circulation '||
        'should appear while checked out, and B. Whether the circulation should '||
        'continue to appear in the "Other" tab when checked in with '||
        'outstanding fines.  '||
        '1 = (A) "Items", (B) "Other".  2 = (A) "Other", (B) "Other".  ' ||
        '5 = (A) "Items", (B) do not display.  6 = (A) "Other", (B) do not display.',
        'coust',
        'description'
    )
    WHERE name = 'ui.circ.items_out.claimsreturned';

SELECT evergreen.upgrade_deps_block_check('1303', :eg_version);

DROP INDEX authority.authority_full_rec_value_index;
CREATE INDEX authority_full_rec_value_index ON authority.full_rec (SUBSTRING(value FOR 1024));

DROP INDEX authority.authority_full_rec_value_tpo_index;
CREATE INDEX authority_full_rec_value_tpo_index ON authority.full_rec (SUBSTRING(value FOR 1024) text_pattern_ops);

SELECT evergreen.upgrade_deps_block_check('1304', :eg_version);

CREATE OR REPLACE FUNCTION actor.usr_purge_data(
	src_usr  IN INTEGER,
	specified_dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	renamable_row RECORD;
	dest_usr INTEGER;
BEGIN

	IF specified_dest_usr IS NULL THEN
		dest_usr := 1; -- Admin user on stock installs
	ELSE
		dest_usr := specified_dest_usr;
	END IF;

    -- action_trigger.event (even doing this, event_output may--and probably does--contain PII and should have a retention/removal policy)
    UPDATE action_trigger.event SET context_user = dest_usr WHERE context_user = src_usr;

	-- acq.*
	UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.lineitem SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.lineitem SET selector = dest_usr WHERE selector = src_usr;
	UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;
	DELETE FROM acq.lineitem_usr_attr_definition WHERE usr = src_usr;

	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE acq.picklist SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.picklist SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
	UPDATE acq.purchase_order SET creator = dest_usr WHERE creator = src_usr;
	UPDATE acq.purchase_order SET editor = dest_usr WHERE editor = src_usr;
	UPDATE acq.claim_event SET creator = dest_usr WHERE creator = src_usr;

	-- action.*
	DELETE FROM action.circulation WHERE usr = src_usr;
	UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
	UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
	UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;
	UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
	UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
	DELETE FROM action.hold_request WHERE usr = src_usr;
	UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
	UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.non_cataloged_circulation WHERE patron = src_usr;
	UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM action.survey_response WHERE usr = src_usr;
	UPDATE action.fieldset SET owner = dest_usr WHERE owner = src_usr;
	DELETE FROM action.usr_circ_history WHERE usr = src_usr;

	-- actor.*
	DELETE FROM actor.card WHERE usr = src_usr;
	DELETE FROM actor.stat_cat_entry_usr_map WHERE target_usr = src_usr;
	DELETE FROM actor.usr_privacy_waiver WHERE usr = src_usr;

	-- The following update is intended to avoid transient violations of a foreign
	-- key constraint, whereby actor.usr_address references itself.  It may not be
	-- necessary, but it does no harm.
	UPDATE actor.usr_address SET replaces = NULL
		WHERE usr = src_usr AND replaces IS NOT NULL;
	DELETE FROM actor.usr_address WHERE usr = src_usr;
	DELETE FROM actor.usr_org_unit_opt_in WHERE usr = src_usr;
	UPDATE actor.usr_org_unit_opt_in SET staff = dest_usr WHERE staff = src_usr;
	DELETE FROM actor.usr_setting WHERE usr = src_usr;
	DELETE FROM actor.usr_standing_penalty WHERE usr = src_usr;
	UPDATE actor.usr_message SET title = 'purged', message = 'purged', read_date = NOW() WHERE usr = src_usr;
	DELETE FROM actor.usr_message WHERE usr = src_usr;
	UPDATE actor.usr_standing_penalty SET staff = dest_usr WHERE staff = src_usr;
	UPDATE actor.usr_message SET editor = dest_usr WHERE editor = src_usr;

	-- asset.*
	UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
	UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
	UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;

	-- auditor.*
	DELETE FROM auditor.actor_usr_address_history WHERE id = src_usr;
	DELETE FROM auditor.actor_usr_history WHERE id = src_usr;
	UPDATE auditor.asset_call_number_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_call_number_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.asset_copy_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.asset_copy_history SET editor  = dest_usr WHERE editor  = src_usr;
	UPDATE auditor.biblio_record_entry_history SET creator = dest_usr WHERE creator = src_usr;
	UPDATE auditor.biblio_record_entry_history SET editor  = dest_usr WHERE editor  = src_usr;

	-- biblio.*
	UPDATE biblio.record_entry SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_entry SET editor = dest_usr WHERE editor = src_usr;
	UPDATE biblio.record_note SET creator = dest_usr WHERE creator = src_usr;
	UPDATE biblio.record_note SET editor = dest_usr WHERE editor = src_usr;

	-- container.*
	-- Update buckets with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR renamable_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	DELETE FROM container.user_bucket_item WHERE target_user = src_usr;

	-- money.*
	DELETE FROM money.billable_xact WHERE usr = src_usr;
	DELETE FROM money.collections_tracker WHERE usr = src_usr;
	UPDATE money.collections_tracker SET collector = dest_usr WHERE collector = src_usr;

	-- permission.*
	DELETE FROM permission.usr_grp_map WHERE usr = src_usr;
	DELETE FROM permission.usr_object_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_perm_map WHERE usr = src_usr;
	DELETE FROM permission.usr_work_ou_map WHERE usr = src_usr;

	-- reporter.*
	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	BEGIN
		UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
	EXCEPTION WHEN undefined_table THEN
		-- do nothing
	END;

	-- Update with a rename to avoid collisions
	BEGIN
		FOR renamable_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = renamable_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
	EXCEPTION WHEN undefined_table THEN
	-- do nothing
	END;

	-- vandelay.*
	-- Update with a rename to avoid collisions
	FOR renamable_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = renamable_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- NULL-ify addresses last so other cleanup (e.g. circ anonymization)
    -- can access the information before deletion.
	UPDATE actor.usr SET
		active = FALSE,
		card = NULL,
		mailing_address = NULL,
		billing_address = NULL
	WHERE id = src_usr;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION actor.usr_delete(
	src_usr  IN INTEGER,
	dest_usr IN INTEGER
) RETURNS VOID AS $$
DECLARE
	old_profile actor.usr.profile%type;
	old_home_ou actor.usr.home_ou%type;
	new_profile actor.usr.profile%type;
	new_home_ou actor.usr.home_ou%type;
	new_name    text;
	new_dob     actor.usr.dob%type;
BEGIN
	SELECT
		id || '-PURGED-' || now(),
		profile,
		home_ou,
		dob
	INTO
		new_name,
		old_profile,
		old_home_ou,
		new_dob
	FROM
		actor.usr
	WHERE
		id = src_usr;
	--
	-- Quit if no such user
	--
	IF old_profile IS NULL THEN
		RETURN;
	END IF;
	--
	perform actor.usr_purge_data( src_usr, dest_usr );
	--
	-- Find the root grp_tree and the root org_unit.  This would be simpler if we 
	-- could assume that there is only one root.  Theoretically, someday, maybe,
	-- there could be multiple roots, so we take extra trouble to get the right ones.
	--
	SELECT
		id
	INTO
		new_profile
	FROM
		permission.grp_ancestors( old_profile )
	WHERE
		parent is null;
	--
	SELECT
		id
	INTO
		new_home_ou
	FROM
		actor.org_unit_ancestors( old_home_ou )
	WHERE
		parent_ou is null;
	--
	-- Truncate date of birth
	--
	IF new_dob IS NOT NULL THEN
		new_dob := date_trunc( 'year', new_dob );
	END IF;
	--
	UPDATE
		actor.usr
		SET
			card = NULL,
			profile = new_profile,
			usrname = new_name,
			email = NULL,
			passwd = random()::text,
			standing = DEFAULT,
			ident_type = 
			(
				SELECT MIN( id )
				FROM config.identification_type
			),
			ident_value = NULL,
			ident_type2 = NULL,
			ident_value2 = NULL,
			net_access_level = DEFAULT,
			photo_url = NULL,
			prefix = NULL,
			first_given_name = new_name,
			second_given_name = NULL,
			family_name = new_name,
			suffix = NULL,
			alias = NULL,
            guardian = NULL,
			day_phone = NULL,
			evening_phone = NULL,
			other_phone = NULL,
			mailing_address = NULL,
			billing_address = NULL,
			home_ou = new_home_ou,
			dob = new_dob,
			active = FALSE,
			master_account = DEFAULT, 
			super_user = DEFAULT,
			barred = FALSE,
			deleted = TRUE,
			juvenile = DEFAULT,
			usrgroup = 0,
			claims_returned_count = DEFAULT,
			credit_forward_balance = DEFAULT,
			last_xact_id = DEFAULT,
			pref_prefix = NULL,
			pref_first_given_name = NULL,
			pref_second_given_name = NULL,
			pref_family_name = NULL,
			pref_suffix = NULL,
			name_keywords = NULL,
			create_date = now(),
			expire_date = now()
	WHERE
		id = src_usr;
END;
$$ LANGUAGE plpgsql;

SELECT evergreen.upgrade_deps_block_check('1305', :eg_version);

CREATE OR REPLACE FUNCTION actor.usr_merge( src_usr INT, dest_usr INT, del_addrs BOOLEAN, del_cards BOOLEAN, deactivate_cards BOOLEAN ) RETURNS VOID AS $$
DECLARE
	suffix TEXT;
	bucket_row RECORD;
	picklist_row RECORD;
	queue_row RECORD;
	folder_row RECORD;
BEGIN

    -- Bail if src_usr equals dest_usr because the result of merging a
    -- user with itself is not what you want.
    IF src_usr = dest_usr THEN
        RETURN;
    END IF;

    -- do some initial cleanup 
    UPDATE actor.usr SET card = NULL WHERE id = src_usr;
    UPDATE actor.usr SET mailing_address = NULL WHERE id = src_usr;
    UPDATE actor.usr SET billing_address = NULL WHERE id = src_usr;

    -- actor.*
    IF del_cards THEN
        DELETE FROM actor.card where usr = src_usr;
    ELSE
        IF deactivate_cards THEN
            UPDATE actor.card SET active = 'f' WHERE usr = src_usr;
        END IF;
        UPDATE actor.card SET usr = dest_usr WHERE usr = src_usr;
    END IF;


    IF del_addrs THEN
        DELETE FROM actor.usr_address WHERE usr = src_usr;
    ELSE
        UPDATE actor.usr_address SET usr = dest_usr WHERE usr = src_usr;
    END IF;

    UPDATE actor.usr_message SET usr = dest_usr WHERE usr = src_usr;
    -- dupes are technically OK in actor.usr_standing_penalty, should manually delete them...
    UPDATE actor.usr_standing_penalty SET usr = dest_usr WHERE usr = src_usr;
    PERFORM actor.usr_merge_rows('actor.usr_org_unit_opt_in', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('actor.usr_setting', 'usr', src_usr, dest_usr);

    -- permission.*
    PERFORM actor.usr_merge_rows('permission.usr_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_object_perm_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_grp_map', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('permission.usr_work_ou_map', 'usr', src_usr, dest_usr);


    -- container.*
	
	-- For each *_bucket table: transfer every bucket belonging to src_usr
	-- into the custody of dest_usr.
	--
	-- In order to avoid colliding with an existing bucket owned by
	-- the destination user, append the source user's id (in parenthesese)
	-- to the name.  If you still get a collision, add successive
	-- spaces to the name and keep trying until you succeed.
	--
	FOR bucket_row in
		SELECT id, name
		FROM   container.biblio_record_entry_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.biblio_record_entry_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.call_number_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.call_number_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.copy_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.copy_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	FOR bucket_row in
		SELECT id, name
		FROM   container.user_bucket
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  container.user_bucket
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = bucket_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

	UPDATE container.user_bucket_item SET target_user = dest_usr WHERE target_user = src_usr;

    -- vandelay.*
	-- transfer queues the same way we transfer buckets (see above)
	FOR queue_row in
		SELECT id, name
		FROM   vandelay.queue
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  vandelay.queue
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = queue_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE vandelay.session_tracker SET usr = dest_usr WHERE usr = src_usr;

    -- money.*
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'usr', src_usr, dest_usr);
    PERFORM actor.usr_merge_rows('money.collections_tracker', 'collector', src_usr, dest_usr);
    UPDATE money.billable_xact SET usr = dest_usr WHERE usr = src_usr;
    UPDATE money.billing SET voider = dest_usr WHERE voider = src_usr;
    UPDATE money.bnm_payment SET accepting_usr = dest_usr WHERE accepting_usr = src_usr;

    -- action.*
    UPDATE action.circulation SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.circulation SET circ_staff = dest_usr WHERE circ_staff = src_usr;
    UPDATE action.circulation SET checkin_staff = dest_usr WHERE checkin_staff = src_usr;
    UPDATE action.usr_circ_history SET usr = dest_usr WHERE usr = src_usr;

    UPDATE action.hold_request SET usr = dest_usr WHERE usr = src_usr;
    UPDATE action.hold_request SET fulfillment_staff = dest_usr WHERE fulfillment_staff = src_usr;
    UPDATE action.hold_request SET requestor = dest_usr WHERE requestor = src_usr;
    UPDATE action.hold_notification SET notify_staff = dest_usr WHERE notify_staff = src_usr;

    UPDATE action.in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.non_cataloged_circulation SET patron = dest_usr WHERE patron = src_usr;
    UPDATE action.non_cat_in_house_use SET staff = dest_usr WHERE staff = src_usr;
    UPDATE action.survey_response SET usr = dest_usr WHERE usr = src_usr;

    -- acq.*
    UPDATE acq.fund_allocation SET allocator = dest_usr WHERE allocator = src_usr;
	UPDATE acq.fund_transfer SET transfer_user = dest_usr WHERE transfer_user = src_usr;
    UPDATE acq.invoice SET closed_by = dest_usr WHERE closed_by = src_usr;

	-- transfer picklists the same way we transfer buckets (see above)
	FOR picklist_row in
		SELECT id, name
		FROM   acq.picklist
		WHERE  owner = src_usr
	LOOP
		suffix := ' (' || src_usr || ')';
		LOOP
			BEGIN
				UPDATE  acq.picklist
				SET     owner = dest_usr, name = name || suffix
				WHERE   id = picklist_row.id;
			EXCEPTION WHEN unique_violation THEN
				suffix := suffix || ' ';
				CONTINUE;
			END;
			EXIT;
		END LOOP;
	END LOOP;

    UPDATE acq.purchase_order SET owner = dest_usr WHERE owner = src_usr;
    UPDATE acq.po_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.po_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.provider_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.provider_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE acq.lineitem_note SET editor = dest_usr WHERE editor = src_usr;
    UPDATE acq.lineitem_usr_attr_definition SET usr = dest_usr WHERE usr = src_usr;

    -- asset.*
    UPDATE asset.copy SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.copy SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.copy_note SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET creator = dest_usr WHERE creator = src_usr;
    UPDATE asset.call_number SET editor = dest_usr WHERE editor = src_usr;
    UPDATE asset.call_number_note SET creator = dest_usr WHERE creator = src_usr;

    -- serial.*
    UPDATE serial.record_entry SET creator = dest_usr WHERE creator = src_usr;
    UPDATE serial.record_entry SET editor = dest_usr WHERE editor = src_usr;

    -- reporter.*
    -- It's not uncommon to define the reporter schema in a replica 
    -- DB only, so don't assume these tables exist in the write DB.
    BEGIN
    	UPDATE reporter.template SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.report SET owner = dest_usr WHERE owner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
    	UPDATE reporter.schedule SET runner = dest_usr WHERE runner = src_usr;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.template_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.template_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.report_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.report_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;
    BEGIN
		-- transfer folders the same way we transfer buckets (see above)
		FOR folder_row in
			SELECT id, name
			FROM   reporter.output_folder
			WHERE  owner = src_usr
		LOOP
			suffix := ' (' || src_usr || ')';
			LOOP
				BEGIN
					UPDATE  reporter.output_folder
					SET     owner = dest_usr, name = name || suffix
					WHERE   id = folder_row.id;
				EXCEPTION WHEN unique_violation THEN
					suffix := suffix || ' ';
					CONTINUE;
				END;
				EXIT;
			END LOOP;
		END LOOP;
    EXCEPTION WHEN undefined_table THEN
        -- do nothing
    END;

    -- propagate preferred name values from the source user to the
    -- destination user, but only when values are not being replaced.
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr)
    UPDATE actor.usr SET 
        pref_prefix = 
            COALESCE(pref_prefix, (SELECT pref_prefix FROM susr)),
        pref_first_given_name = 
            COALESCE(pref_first_given_name, (SELECT pref_first_given_name FROM susr)),
        pref_second_given_name = 
            COALESCE(pref_second_given_name, (SELECT pref_second_given_name FROM susr)),
        pref_family_name = 
            COALESCE(pref_family_name, (SELECT pref_family_name FROM susr)),
        pref_suffix = 
            COALESCE(pref_suffix, (SELECT pref_suffix FROM susr))
    WHERE id = dest_usr;

    -- Copy and deduplicate name keywords
    -- String -> array -> rows -> DISTINCT -> array -> string
    WITH susr AS (SELECT * FROM actor.usr WHERE id = src_usr),
         dusr AS (SELECT * FROM actor.usr WHERE id = dest_usr)
    UPDATE actor.usr SET name_keywords = (
        WITH keywords AS (
            SELECT DISTINCT UNNEST(
                REGEXP_SPLIT_TO_ARRAY(
                    COALESCE((SELECT name_keywords FROM susr), '') || ' ' ||
                    COALESCE((SELECT name_keywords FROM dusr), ''),  E'\\s+'
                )
            ) AS parts
        ) SELECT ARRAY_TO_STRING(ARRAY_AGG(kw.parts), ' ') FROM keywords kw
    ) WHERE id = dest_usr;

    -- Finally, delete the source user
    PERFORM actor.usr_delete(src_usr,dest_usr);

END;
$$ LANGUAGE plpgsql;

SELECT evergreen.upgrade_deps_block_check('1306', :eg_version);

-- We don't pass this function arrays with nulls, so we save 5% not testing for that
CREATE OR REPLACE FUNCTION evergreen.text_array_merge_unique (
    TEXT[], TEXT[]
) RETURNS TEXT[] AS $F$
    SELECT NULLIF(ARRAY(
        SELECT * FROM UNNEST($1) x
            UNION
        SELECT * FROM UNNEST($2) y
    ),'{}');
$F$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION search.symspell_build_raw_entry (
    raw_input       TEXT,
    source_class    TEXT,
    no_limit        BOOL DEFAULT FALSE,
    prefix_length   INT DEFAULT 6,
    maxED           INT DEFAULT 3
) RETURNS SETOF search.symspell_dictionary AS $F$
DECLARE
    key         TEXT;
    del_key     TEXT;
    key_list    TEXT[];
    entry       search.symspell_dictionary%ROWTYPE;
BEGIN
    key := raw_input;

    IF NOT no_limit AND CHARACTER_LENGTH(raw_input) > prefix_length THEN
        key := SUBSTRING(key FROM 1 FOR prefix_length);
        key_list := ARRAY[raw_input, key];
    ELSE
        key_list := ARRAY[key];
    END IF;

    FOREACH del_key IN ARRAY key_list LOOP
        -- skip empty keys
        CONTINUE WHEN del_key IS NULL OR CHARACTER_LENGTH(del_key) = 0;

        entry.prefix_key := del_key;

        entry.keyword_count := 0;
        entry.title_count := 0;
        entry.author_count := 0;
        entry.subject_count := 0;
        entry.series_count := 0;
        entry.identifier_count := 0;

        entry.keyword_suggestions := '{}';
        entry.title_suggestions := '{}';
        entry.author_suggestions := '{}';
        entry.subject_suggestions := '{}';
        entry.series_suggestions := '{}';
        entry.identifier_suggestions := '{}';

        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'title' THEN entry.title_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'author' THEN entry.author_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'subject' THEN entry.subject_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'series' THEN entry.series_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'identifier' THEN entry.identifier_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;

        IF del_key = raw_input THEN
            IF source_class = 'keyword' THEN entry.keyword_count := 1; END IF;
            IF source_class = 'title' THEN entry.title_count := 1; END IF;
            IF source_class = 'author' THEN entry.author_count := 1; END IF;
            IF source_class = 'subject' THEN entry.subject_count := 1; END IF;
            IF source_class = 'series' THEN entry.series_count := 1; END IF;
            IF source_class = 'identifier' THEN entry.identifier_count := 1; END IF;
        END IF;

        RETURN NEXT entry;
    END LOOP;

    FOR del_key IN SELECT x FROM UNNEST(search.symspell_generate_edits(key, 1, maxED)) x LOOP

        -- skip empty keys
        CONTINUE WHEN del_key IS NULL OR CHARACTER_LENGTH(del_key) = 0;
        -- skip suggestions that are already too long for the prefix key
        CONTINUE WHEN CHARACTER_LENGTH(del_key) <= (prefix_length - maxED) AND CHARACTER_LENGTH(raw_input) > prefix_length;

        entry.keyword_suggestions := '{}';
        entry.title_suggestions := '{}';
        entry.author_suggestions := '{}';
        entry.subject_suggestions := '{}';
        entry.series_suggestions := '{}';
        entry.identifier_suggestions := '{}';

        IF source_class = 'keyword' THEN entry.keyword_count := 0; END IF;
        IF source_class = 'title' THEN entry.title_count := 0; END IF;
        IF source_class = 'author' THEN entry.author_count := 0; END IF;
        IF source_class = 'subject' THEN entry.subject_count := 0; END IF;
        IF source_class = 'series' THEN entry.series_count := 0; END IF;
        IF source_class = 'identifier' THEN entry.identifier_count := 0; END IF;

        entry.prefix_key := del_key;

        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'title' THEN entry.title_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'author' THEN entry.author_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'subject' THEN entry.subject_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'series' THEN entry.series_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'identifier' THEN entry.identifier_suggestions := ARRAY[raw_input]; END IF;
        IF source_class = 'keyword' THEN entry.keyword_suggestions := ARRAY[raw_input]; END IF;

        RETURN NEXT entry;
    END LOOP;

END;
$F$ LANGUAGE PLPGSQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION search.symspell_build_entries (
    full_input      TEXT,
    source_class    TEXT,
    old_input       TEXT DEFAULT NULL,
    include_phrases BOOL DEFAULT FALSE
) RETURNS SETOF search.symspell_dictionary AS $F$
DECLARE
    prefix_length   INT;
    maxED           INT;
    word_list   TEXT[];
    input       TEXT;
    word        TEXT;
    entry       search.symspell_dictionary;
BEGIN
    IF full_input IS NOT NULL THEN
        SELECT value::INT INTO prefix_length FROM config.internal_flag WHERE name = 'symspell.prefix_length' AND enabled;
        prefix_length := COALESCE(prefix_length, 6);

        SELECT value::INT INTO maxED FROM config.internal_flag WHERE name = 'symspell.max_edit_distance' AND enabled;
        maxED := COALESCE(maxED, 3);

        input := evergreen.lowercase(full_input);
        word_list := ARRAY_AGG(x) FROM search.symspell_parse_words_distinct(input) x;
        IF word_list IS NULL THEN
            RETURN;
        END IF;
    
        IF CARDINALITY(word_list) > 1 AND include_phrases THEN
            RETURN QUERY SELECT * FROM search.symspell_build_raw_entry(input, source_class, TRUE, prefix_length, maxED);
        END IF;

        FOREACH word IN ARRAY word_list LOOP
            -- Skip words that have runs of 5 or more digits (I'm looking at you, ISxNs)
            CONTINUE WHEN CHARACTER_LENGTH(word) > 4 AND word ~ '\d{5,}';
            RETURN QUERY SELECT * FROM search.symspell_build_raw_entry(word, source_class, FALSE, prefix_length, maxED);
        END LOOP;
    END IF;

    IF old_input IS NOT NULL THEN
        input := evergreen.lowercase(old_input);

        FOR word IN SELECT x FROM search.symspell_parse_words_distinct(input) x LOOP
            -- similarly skip words that have 5 or more digits here to
            -- avoid adding erroneous prefix deletion entries to the dictionary
            CONTINUE WHEN CHARACTER_LENGTH(word) > 4 AND word ~ '\d{5,}';
            entry.prefix_key := word;

            entry.keyword_count := 0;
            entry.title_count := 0;
            entry.author_count := 0;
            entry.subject_count := 0;
            entry.series_count := 0;
            entry.identifier_count := 0;

            entry.keyword_suggestions := '{}';
            entry.title_suggestions := '{}';
            entry.author_suggestions := '{}';
            entry.subject_suggestions := '{}';
            entry.series_suggestions := '{}';
            entry.identifier_suggestions := '{}';

            IF source_class = 'keyword' THEN entry.keyword_count := -1; END IF;
            IF source_class = 'title' THEN entry.title_count := -1; END IF;
            IF source_class = 'author' THEN entry.author_count := -1; END IF;
            IF source_class = 'subject' THEN entry.subject_count := -1; END IF;
            IF source_class = 'series' THEN entry.series_count := -1; END IF;
            IF source_class = 'identifier' THEN entry.identifier_count := -1; END IF;

            RETURN NEXT entry;
        END LOOP;
    END IF;
END;
$F$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION search.symspell_build_and_merge_entries (
    full_input      TEXT,
    source_class    TEXT,
    old_input       TEXT DEFAULT NULL,
    include_phrases BOOL DEFAULT FALSE
) RETURNS SETOF search.symspell_dictionary AS $F$
DECLARE
    new_entry       RECORD;
    conflict_entry  RECORD;
BEGIN

    IF full_input = old_input THEN -- neither NULL, and are the same
        RETURN;
    END IF;

    FOR new_entry IN EXECUTE $q$
        SELECT  count,
                prefix_key,
                s AS suggestions
          FROM  (SELECT prefix_key,
                        ARRAY_AGG(DISTINCT $q$ || source_class || $q$_suggestions[1]) s,
                        SUM($q$ || source_class || $q$_count) count
                  FROM  search.symspell_build_entries($1, $2, $3, $4)
                  GROUP BY 1) x
        $q$ USING full_input, source_class, old_input, include_phrases
    LOOP
        EXECUTE $q$
            SELECT  prefix_key,
                    $q$ || source_class || $q$_suggestions suggestions,
                    $q$ || source_class || $q$_count count
              FROM  search.symspell_dictionary
              WHERE prefix_key = $1 $q$
            INTO conflict_entry
            USING new_entry.prefix_key;

        IF new_entry.count <> 0 THEN -- Real word, and count changed
            IF conflict_entry.prefix_key IS NOT NULL THEN -- we'll be updating
                IF conflict_entry.count > 0 THEN -- it's a real word
                    RETURN QUERY EXECUTE $q$
                        UPDATE  search.symspell_dictionary
                           SET  $q$ || source_class || $q$_count = $2
                          WHERE prefix_key = $1
                          RETURNING * $q$
                        USING new_entry.prefix_key, GREATEST(0, new_entry.count + conflict_entry.count);
                ELSE -- it was a prefix key or delete-emptied word before
                    IF conflict_entry.suggestions @> new_entry.suggestions THEN -- already have all suggestions here...
                        RETURN QUERY EXECUTE $q$
                            UPDATE  search.symspell_dictionary
                               SET  $q$ || source_class || $q$_count = $2
                              WHERE prefix_key = $1
                              RETURNING * $q$
                            USING new_entry.prefix_key, GREATEST(0, new_entry.count);
                    ELSE -- new suggestion!
                        RETURN QUERY EXECUTE $q$
                            UPDATE  search.symspell_dictionary
                               SET  $q$ || source_class || $q$_count = $2,
                                    $q$ || source_class || $q$_suggestions = $3
                              WHERE prefix_key = $1
                              RETURNING * $q$
                            USING new_entry.prefix_key, GREATEST(0, new_entry.count), evergreen.text_array_merge_unique(conflict_entry.suggestions,new_entry.suggestions);
                    END IF;
                END IF;
            ELSE
                -- We keep the on-conflict clause just in case...
                RETURN QUERY EXECUTE $q$
                    INSERT INTO search.symspell_dictionary AS d (
                        $q$ || source_class || $q$_count,
                        prefix_key,
                        $q$ || source_class || $q$_suggestions
                    ) VALUES ( $1, $2, $3 ) ON CONFLICT (prefix_key) DO
                        UPDATE SET  $q$ || source_class || $q$_count = d.$q$ || source_class || $q$_count + EXCLUDED.$q$ || source_class || $q$_count,
                                    $q$ || source_class || $q$_suggestions = evergreen.text_array_merge_unique(d.$q$ || source_class || $q$_suggestions, EXCLUDED.$q$ || source_class || $q$_suggestions)
                        RETURNING * $q$
                    USING new_entry.count, new_entry.prefix_key, new_entry.suggestions;
            END IF;
        ELSE -- key only, or no change
            IF conflict_entry.prefix_key IS NOT NULL THEN -- we'll be updating
                IF NOT conflict_entry.suggestions @> new_entry.suggestions THEN -- There are new suggestions
                    RETURN QUERY EXECUTE $q$
                        UPDATE  search.symspell_dictionary
                           SET  $q$ || source_class || $q$_suggestions = $2
                          WHERE prefix_key = $1
                          RETURNING * $q$
                        USING new_entry.prefix_key, evergreen.text_array_merge_unique(conflict_entry.suggestions,new_entry.suggestions);
                END IF;
            ELSE
                RETURN QUERY EXECUTE $q$
                    INSERT INTO search.symspell_dictionary AS d (
                        $q$ || source_class || $q$_count,
                        prefix_key,
                        $q$ || source_class || $q$_suggestions
                    ) VALUES ( $1, $2, $3 ) ON CONFLICT (prefix_key) DO -- key exists, suggestions may be added due to this entry
                        UPDATE SET  $q$ || source_class || $q$_suggestions = evergreen.text_array_merge_unique(d.$q$ || source_class || $q$_suggestions, EXCLUDED.$q$ || source_class || $q$_suggestions)
                    RETURNING * $q$
                    USING new_entry.count, new_entry.prefix_key, new_entry.suggestions;
            END IF;
        END IF;
    END LOOP;
END;
$F$ LANGUAGE PLPGSQL;

COMMIT;

\qecho ''
\qecho 'The following should be run at the end of the upgrade before any'
\qecho 'reingest occurs.  Because new triggers are installed already,'
\qecho 'updates to indexed strings will cause zero-count dictionary entries'
\qecho 'to be recorded which will require updating every row again (or'
\qecho 'starting from scratch) so best to do this before other batch'
\qecho 'changes.  A later reingest that does not significantly change'
\qecho 'indexed strings will /not/ cause table bloat here, and will be'
\qecho 'as fast as normal.  A copy of the SQL in a ready-to-use, non-escaped'
\qecho 'form is available inside a comment at the end of this upgrade sub-'
\qecho 'script so you do not need to copy this comment from the psql ouptut.'
\qecho ''
\qecho '\\a'
\qecho '\\t'
\qecho ''
\qecho '\\o title'
\qecho 'select value from metabib.title_field_entry where source in (select id from biblio.record_entry where not deleted);'
\qecho '\\o author'
\qecho 'select value from metabib.author_field_entry where source in (select id from biblio.record_entry where not deleted);'
\qecho '\\o subject'
\qecho 'select value from metabib.subject_field_entry where source in (select id from biblio.record_entry where not deleted);'
\qecho '\\o series'
\qecho 'select value from metabib.series_field_entry where source in (select id from biblio.record_entry where not deleted);'
\qecho '\\o identifier'
\qecho 'select value from metabib.identifier_field_entry where source in (select id from biblio.record_entry where not deleted);'
\qecho '\\o keyword'
\qecho 'select value from metabib.keyword_field_entry where source in (select id from biblio.record_entry where not deleted);'
\qecho ''
\qecho '\\o'
\qecho '\\a'
\qecho '\\t'
\qecho ''
\qecho '// Then, at the command line:'
\qecho ''
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl title > title.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl author > author.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl subject > subject.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl series > series.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl identifier > identifier.sql'
\qecho '$ ~/EG-src-path/Open-ILS/src/support-scripts/symspell-sideload.pl keyword > keyword.sql'
\qecho ''
\qecho '// And, back in psql'
\qecho ''
\qecho 'ALTER TABLE search.symspell_dictionary SET UNLOGGED;'
\qecho 'TRUNCATE search.symspell_dictionary;'
\qecho ''
\qecho '\\i identifier.sql'
\qecho '\\i author.sql'
\qecho '\\i title.sql'
\qecho '\\i subject.sql'
\qecho '\\i series.sql'
\qecho '\\i keyword.sql'
\qecho ''
\qecho 'CLUSTER search.symspell_dictionary USING symspell_dictionary_pkey;'
\qecho 'REINDEX TABLE search.symspell_dictionary;'
\qecho 'ALTER TABLE search.symspell_dictionary SET LOGGED;'
\qecho 'VACUUM ANALYZE search.symspell_dictionary;'
\qecho ''
\qecho 'DROP TABLE search.symspell_dictionary_partial_title;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_author;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_subject;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_series;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_identifier;'
\qecho 'DROP TABLE search.symspell_dictionary_partial_keyword;'

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
