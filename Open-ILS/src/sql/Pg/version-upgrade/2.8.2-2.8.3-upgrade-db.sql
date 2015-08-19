--Upgrade Script for 2.8.2 to 2.8.3
\set eg_version '''2.8.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.8.3', :eg_version);
-- Evergreen DB patch 0924.schema.rank_cp_visibility.sql
--
-- rank_cp() is meant to return the most-available copies, so it needs to
-- factor in the opac_visible flag on the copies themselves
--

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0924', :eg_version);

-- function is being expanded and renamed, so drop the old version
DROP FUNCTION IF EXISTS evergreen.rank_cp_status(INT);

-- this version exists mainly to accommodate JSON query transform limitations
-- (the transform argument must be an IDL field, not an entire row/object)
-- XXX is there another way?
CREATE OR REPLACE FUNCTION evergreen.rank_cp(copy_id BIGINT)
RETURNS INTEGER AS $$
DECLARE
    copy asset.copy%ROWTYPE;
BEGIN
    SELECT * INTO copy FROM asset.copy WHERE id = copy_id;
    RETURN evergreen.rank_cp(copy);
END;
$$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.rank_cp(copy asset.copy)
RETURNS INTEGER AS $$
DECLARE
    rank INT;
BEGIN
    WITH totally_available AS (
        SELECT id, 0 AS avail_rank
        FROM config.copy_status
        WHERE opac_visible IS TRUE
            AND copy_active IS TRUE
            AND id != 1 -- "Checked out"
    ), almost_available AS (
        SELECT id, 10 AS avail_rank
        FROM config.copy_status
        WHERE holdable IS TRUE
            AND opac_visible IS TRUE
            AND copy_active IS FALSE
            OR id = 1 -- "Checked out"
    )
    SELECT COALESCE(
        CASE WHEN NOT copy.opac_visible THEN 100 END,
        (SELECT avail_rank FROM totally_available WHERE copy.status IN (id)),
        CASE WHEN copy.holdable THEN
            (SELECT avail_rank FROM almost_available WHERE copy.status IN (id))
        END,
        100
    ) INTO rank;

    RETURN rank;
END;
$$ LANGUAGE PLPGSQL STABLE;

CREATE OR REPLACE FUNCTION evergreen.ranked_volumes(
    bibid BIGINT[], 
    ouid INT,
    depth INT DEFAULT NULL,
    slimit HSTORE DEFAULT NULL,
    soffset HSTORE DEFAULT NULL,
    pref_lib INT DEFAULT NULL,
    includes TEXT[] DEFAULT NULL::TEXT[]
) RETURNS TABLE(id BIGINT, name TEXT, label_sortkey TEXT, rank BIGINT) AS $$
    WITH RECURSIVE ou_depth AS (
        SELECT COALESCE(
            $3,
            (
                SELECT depth
                FROM actor.org_unit_type aout
                    INNER JOIN actor.org_unit ou ON ou_type = aout.id
                WHERE ou.id = $2
            )
        ) AS depth
    ), descendant_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ad ON (ad.id = ou.id),
                ou_depth
        WHERE ad.depth = ou_depth.depth
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN descendant_depth ot ON (ot.id = ou.parent_ou)
    ), anscestor_depth AS (
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
        WHERE ou.id = $2
            UNION ALL
        SELECT  ou.id,
                ou.parent_ou,
                out.depth
        FROM  actor.org_unit ou
                JOIN actor.org_unit_type out ON (out.id = ou.ou_type)
                JOIN anscestor_depth ot ON (ot.parent_ou = ou.id)
    ), descendants as (
        SELECT ou.* FROM actor.org_unit ou JOIN descendant_depth USING (id)
    )

    SELECT ua.id, ua.name, ua.label_sortkey, MIN(ua.rank) AS rank FROM (
        SELECT acn.id, aou.name, acn.label_sortkey,
            evergreen.rank_cp(acp),
            RANK() OVER w
        FROM asset.call_number acn
            JOIN asset.copy acp ON (acn.id = acp.call_number)
            JOIN descendants AS aou ON (acp.circ_lib = aou.id)
        WHERE acn.record = ANY ($1)
            AND acn.deleted IS FALSE
            AND acp.deleted IS FALSE
            AND CASE WHEN ('exclude_invisible_acn' = ANY($7)) THEN 
                EXISTS (
                    SELECT 1 
                    FROM asset.opac_visible_copies 
                    WHERE copy_id = acp.id AND record = acn.record
                ) ELSE TRUE END
        GROUP BY acn.id, evergreen.rank_cp(acp), aou.name, acn.label_sortkey, aou.id
        WINDOW w AS (
            ORDER BY 
                COALESCE(
                    CASE WHEN aou.id = $2 THEN -20000 END,
                    CASE WHEN aou.id = $6 THEN -10000 END,
                    (SELECT distance - 5000
                        FROM actor.org_unit_descendants_distance($6) as x
                        WHERE x.id = aou.id AND $6 IN (
                            SELECT q.id FROM actor.org_unit_descendants($2) as q)),
                    (SELECT e.distance FROM actor.org_unit_descendants_distance($2) as e WHERE e.id = aou.id),
                    1000
                ),
                evergreen.rank_cp(acp)
        )
    ) AS ua
    GROUP BY ua.id, ua.name, ua.label_sortkey
    ORDER BY rank, ua.name, ua.label_sortkey
    LIMIT ($4 -> 'acn')::INT
    OFFSET ($5 -> 'acn')::INT;
$$ LANGUAGE SQL STABLE ROWS 10;

CREATE OR REPLACE FUNCTION unapi.acn ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name volume,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/holdings/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@acn/' || acn.id AS id,
                        acn.id AS vol_id, o.shortname AS lib,
                        o.opac_visible AS opac_visible,
                        deleted, label, label_sortkey, label_class, record
                    ),
                    unapi.aou( owning_lib, $2, 'owning_lib', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8),
                    CASE 
                        WHEN ('acp' = ANY ($4)) THEN
                            CASE WHEN $6 IS NOT NULL THEN
                                XMLELEMENT( name copies,
                                    (SELECT XMLAGG(acp ORDER BY rank_avail) FROM (
                                        SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                                            evergreen.rank_cp(cp) AS rank_avail
                                          FROM  asset.copy cp
                                                JOIN actor.org_unit_descendants( (SELECT id FROM actor.org_unit WHERE shortname = $5), $6) aoud ON (cp.circ_lib = aoud.id)
                                          WHERE cp.call_number = acn.id
                                              AND cp.deleted IS FALSE
                                          ORDER BY rank_avail, COALESCE(cp.copy_number,0), cp.barcode
                                          LIMIT ($7 -> 'acp')::INT
                                          OFFSET ($8 -> 'acp')::INT
                                    )x)
                                )
                            ELSE
                                XMLELEMENT( name copies,
                                    (SELECT XMLAGG(acp ORDER BY rank_avail) FROM (
                                        SELECT  unapi.acp( cp.id, 'xml', 'copy', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                                            evergreen.rank_cp(cp) AS rank_avail
                                          FROM  asset.copy cp
                                                JOIN actor.org_unit_descendants( (SELECT id FROM actor.org_unit WHERE shortname = $5) ) aoud ON (cp.circ_lib = aoud.id)
                                          WHERE cp.call_number = acn.id
                                              AND cp.deleted IS FALSE
                                          ORDER BY rank_avail, COALESCE(cp.copy_number,0), cp.barcode
                                          LIMIT ($7 -> 'acp')::INT
                                          OFFSET ($8 -> 'acp')::INT
                                    )x)
                                )
                            END
                        ELSE NULL
                    END,
                    XMLELEMENT(
                        name uris,
                        (SELECT XMLAGG(auri) FROM (SELECT unapi.auri(uri,'xml','uri', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) FROM asset.uri_call_number_map WHERE call_number = acn.id)x)
                    ),
                    unapi.acnp( acn.prefix, 'marcxml', 'prefix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                    unapi.acns( acn.suffix, 'marcxml', 'suffix', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE),
                    CASE WHEN ('bre' = ANY ($4)) THEN unapi.bre( acn.record, 'marcxml', 'record', evergreen.array_remove_item_by_value($4,'acn'), $5, $6, $7, $8, FALSE) ELSE NULL END
                ) AS x
          FROM  asset.call_number acn
                JOIN actor.org_unit o ON (o.id = acn.owning_lib)
          WHERE acn.id = $1
              AND acn.deleted IS FALSE
          GROUP BY acn.id, o.shortname, o.opac_visible, deleted, label, label_sortkey, label_class, owning_lib, record, acn.prefix, acn.suffix;
$F$ LANGUAGE SQL STABLE;


SELECT evergreen.upgrade_deps_block_check('0925', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.limit_oustl() RETURNS TRIGGER AS $oustl_limit$
    BEGIN
        -- Only keeps the most recent five settings changes.
        DELETE FROM config.org_unit_setting_type_log WHERE field_name = NEW.field_name AND org = NEW.org AND date_applied NOT IN 
        (SELECT date_applied FROM config.org_unit_setting_type_log WHERE field_name = NEW.field_name AND org = NEW.org ORDER BY date_applied DESC LIMIT 4);
        
        IF (TG_OP = 'UPDATE') THEN
            RETURN NEW;
        ELSIF (TG_OP = 'INSERT') THEN
            RETURN NEW;
        END IF;
        RETURN NULL;
    END;
$oustl_limit$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS limit_logs_oust ON config.org_unit_setting_type_log;

CREATE TRIGGER limit_logs_oust
    BEFORE INSERT OR UPDATE ON config.org_unit_setting_type_log
    FOR EACH ROW EXECUTE PROCEDURE limit_oustl();


SELECT evergreen.upgrade_deps_block_check('0926', :eg_version);

CREATE OR REPLACE FUNCTION acq.copy_fund_tags(
        old_fund_id INTEGER,
        new_fund_id INTEGER
) RETURNS VOID AS $$
DECLARE
fund_tag_rec	RECORD;
BEGIN
       
	FOR fund_tag_rec IN SELECT * FROM acq.fund_tag_map WHERE fund=old_fund_id LOOP
                BEGIN
		     INSERT INTO acq.fund_tag_map(fund, tag) VALUES(new_fund_id, fund_tag_rec.tag);
                EXCEPTION
			WHEN unique_violation THEN
			--    RAISE NOTICE 'Fund tag already propagated', old_fund.id;
			CONTINUE;
		END;
	END LOOP;
	RETURN;
END;
$$ LANGUAGE plpgsql;

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
roll_distrib_forms BOOL;
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

		        PERFORM acq.copy_fund_tags(roll_fund.id,new_fund);

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

		-- Rollover distribution formulae funds
		SELECT INTO roll_distrib_forms value::BOOL FROM
			actor.org_unit_ancestor_setting(
				'acq.fund.rollover_distrib_forms', org_unit_id
			);

		IF roll_distrib_forms THEN
			UPDATE acq.distribution_formula_entry 
				SET fund = roll_fund.new_fund_id
				WHERE fund = roll_fund.old_fund;
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

		PERFORM acq.copy_fund_tags(old_fund.id,new_id);

		--RAISE NOTICE 'Propagating fund % to fund %',
		--	old_fund.code, new_id;
	END LOOP;
END;
$$ LANGUAGE plpgsql;




SELECT evergreen.upgrade_deps_block_check('0927', :eg_version);

CREATE OR REPLACE VIEW extend_reporter.full_circ_count AS
   SELECT cp.id,
   COALESCE((SELECT circ_count FROM extend_reporter.legacy_circ_count WHERE id = cp.id), 0)
   + (SELECT COUNT(*) FROM action.circulation WHERE target_copy = cp.id)
   + (SELECT COUNT(*) FROM action.aged_circulation WHERE target_copy = cp.id) AS circ_count
   FROM asset.copy cp;

-- make record attributes definitions that use xpath to extract values 
-- work


SELECT evergreen.upgrade_deps_block_check('0936', :eg_version);

CREATE OR REPLACE FUNCTION metabib.reingest_record_attributes (rid BIGINT, pattr_list TEXT[] DEFAULT NULL, prmarc TEXT DEFAULT NULL, rdeleted BOOL DEFAULT TRUE) RETURNS VOID AS $func$
DECLARE
    transformed_xml TEXT;
    rmarc           TEXT := prmarc;
    tmp_val         TEXT;
    prev_xfrm       TEXT;
    normalizer      RECORD;
    xfrm            config.xml_transform%ROWTYPE;
    attr_vector     INT[] := '{}'::INT[];
    attr_vector_tmp INT[];
    attr_list       TEXT[] := pattr_list;
    attr_value      TEXT[];
    norm_attr_value TEXT[];
    tmp_xml         TEXT;
    attr_def        config.record_attr_definition%ROWTYPE;
    ccvm_row        config.coded_value_map%ROWTYPE;
BEGIN

    IF attr_list IS NULL OR rdeleted THEN -- need to do the full dance on INSERT or undelete
        SELECT ARRAY_AGG(name) INTO attr_list FROM config.record_attr_definition;
    END IF;

    IF rmarc IS NULL THEN
        SELECT marc INTO rmarc FROM biblio.record_entry WHERE id = rid;
    END IF;

    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE NOT composite AND name = ANY( attr_list ) ORDER BY format LOOP

        attr_value := '{}'::TEXT[];
        norm_attr_value := '{}'::TEXT[];
        attr_vector_tmp := '{}'::INT[];

        SELECT * INTO ccvm_row FROM config.coded_value_map c WHERE c.ctype = attr_def.name LIMIT 1; 

        -- tag+sf attrs only support SVF
        IF attr_def.tag IS NOT NULL THEN -- tag (and optional subfield list) selection
            SELECT  ARRAY[ARRAY_TO_STRING(ARRAY_AGG(value), COALESCE(attr_def.joiner,' '))] INTO attr_value
              FROM  (SELECT * FROM metabib.full_rec ORDER BY tag, subfield) AS x
              WHERE record = rid
                    AND tag LIKE attr_def.tag
                    AND CASE
                        WHEN attr_def.sf_list IS NOT NULL 
                            THEN POSITION(subfield IN attr_def.sf_list) > 0
                        ELSE TRUE
                    END
              GROUP BY tag
              ORDER BY tag
              LIMIT 1;

        ELSIF attr_def.fixed_field IS NOT NULL THEN -- a named fixed field, see config.marc21_ff_pos_map.fixed_field
            attr_value := vandelay.marc21_extract_fixed_field_list(rmarc, attr_def.fixed_field);

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        ELSIF attr_def.xpath IS NOT NULL THEN -- and xpath expression

            SELECT INTO xfrm * FROM config.xml_transform WHERE name = attr_def.format;
        
            -- See if we can skip the XSLT ... it's expensive
            IF prev_xfrm IS NULL OR prev_xfrm <> xfrm.name THEN
                -- Can't skip the transform
                IF xfrm.xslt <> '---' THEN
                    transformed_xml := oils_xslt_process(rmarc,xfrm.xslt);
                ELSE
                    transformed_xml := rmarc;
                END IF;
    
                prev_xfrm := xfrm.name;
            END IF;

            IF xfrm.name IS NULL THEN
                -- just grab the marcxml (empty) transform
                SELECT INTO xfrm * FROM config.xml_transform WHERE xslt = '---' LIMIT 1;
                prev_xfrm := xfrm.name;
            END IF;

            FOR tmp_xml IN SELECT UNNEST(oils_xpath(attr_def.xpath, transformed_xml, ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]])) LOOP
                tmp_val := oils_xpath_string(
                                '//*',
                                tmp_xml,
                                COALESCE(attr_def.joiner,' '),
                                ARRAY[ARRAY[xfrm.prefix, xfrm.namespace_uri]]
                            );
                IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                    attr_value := attr_value || tmp_val;
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END LOOP;

        ELSIF attr_def.phys_char_sf IS NOT NULL THEN -- a named Physical Characteristic, see config.marc21_physical_characteristic_*_map
            SELECT  ARRAY_AGG(m.value) INTO attr_value
              FROM  vandelay.marc21_physical_characteristics(rmarc) v
                    LEFT JOIN config.marc21_physical_characteristic_value_map m ON (m.id = v.value)
              WHERE v.subfield = attr_def.phys_char_sf AND (m.value IS NOT NULL AND BTRIM(m.value) <> '')
                    AND ( ccvm_row.id IS NULL OR ( ccvm_row.id IS NOT NULL AND v.id IS NOT NULL) );

            IF NOT attr_def.multi THEN
                attr_value := ARRAY[attr_value[1]];
            END IF;

        END IF;

                -- apply index normalizers to attr_value
        FOR tmp_val IN SELECT value FROM UNNEST(attr_value) x(value) LOOP
            FOR normalizer IN
                SELECT  n.func AS func,
                        n.param_count AS param_count,
                        m.params AS params
                  FROM  config.index_normalizer n
                        JOIN config.record_attr_index_norm_map m ON (m.norm = n.id)
                  WHERE attr = attr_def.name
                  ORDER BY m.pos LOOP
                    EXECUTE 'SELECT ' || normalizer.func || '(' ||
                    COALESCE( quote_literal( tmp_val ), 'NULL' ) ||
                        CASE
                            WHEN normalizer.param_count > 0
                                THEN ',' || REPLACE(REPLACE(BTRIM(normalizer.params,'[]'),E'\'',E'\\\''),E'"',E'\'')
                                ELSE ''
                            END ||
                    ')' INTO tmp_val;

            END LOOP;
            IF tmp_val IS NOT NULL AND tmp_val <> '' THEN
                -- note that a string that contains only blanks
                -- is a valid value for some attributes
                norm_attr_value := norm_attr_value || tmp_val;
            END IF;
        END LOOP;
        
        IF attr_def.filter THEN
            -- Create unknown uncontrolled values and find the IDs of the values
            IF ccvm_row.id IS NULL THEN
                FOR tmp_val IN SELECT value FROM UNNEST(norm_attr_value) x(value) LOOP
                    IF tmp_val IS NOT NULL AND BTRIM(tmp_val) <> '' THEN
                        BEGIN -- use subtransaction to isolate unique constraint violations
                            INSERT INTO metabib.uncontrolled_record_attr_value ( attr, value ) VALUES ( attr_def.name, tmp_val );
                        EXCEPTION WHEN unique_violation THEN END;
                    END IF;
                END LOOP;

                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM metabib.uncontrolled_record_attr_value WHERE attr = attr_def.name AND value = ANY( norm_attr_value );
            ELSE
                SELECT ARRAY_AGG(id) INTO attr_vector_tmp FROM config.coded_value_map WHERE ctype = attr_def.name AND code = ANY( norm_attr_value );
            END IF;

            -- Add the new value to the vector
            attr_vector := attr_vector || attr_vector_tmp;
        END IF;

        IF attr_def.sorter AND norm_attr_value[1] IS NOT NULL THEN
            DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
            INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, norm_attr_value[1]);
        END IF;

    END LOOP;

/* We may need to rewrite the vlist to contain
   the intersection of new values for requested
   attrs and old values for ignored attrs. To
   do this, we take the old attr vlist and
   subtract any values that are valid for the
   requested attrs, and then add back the new
   set of attr values. */

    IF ARRAY_LENGTH(pattr_list, 1) > 0 THEN 
        SELECT vlist INTO attr_vector_tmp FROM metabib.record_attr_vector_list WHERE source = rid;
        SELECT attr_vector_tmp - ARRAY_AGG(id::INT) INTO attr_vector_tmp FROM metabib.full_attr_id_map WHERE attr = ANY (pattr_list);
        attr_vector := attr_vector || attr_vector_tmp;
    END IF;

    -- On to composite attributes, now that the record attrs have been pulled.  Processed in name order, so later composite
    -- attributes can depend on earlier ones.
    PERFORM metabib.compile_composite_attr_cache_init();
    FOR attr_def IN SELECT * FROM config.record_attr_definition WHERE composite AND name = ANY( attr_list ) ORDER BY name LOOP

        FOR ccvm_row IN SELECT * FROM config.coded_value_map c WHERE c.ctype = attr_def.name ORDER BY value LOOP

            tmp_val := metabib.compile_composite_attr( ccvm_row.id );
            CONTINUE WHEN tmp_val IS NULL OR tmp_val = ''; -- nothing to do

            IF attr_def.filter THEN
                IF attr_vector @@ tmp_val::query_int THEN
                    attr_vector = attr_vector + intset(ccvm_row.id);
                    EXIT WHEN NOT attr_def.multi;
                END IF;
            END IF;

            IF attr_def.sorter THEN
                IF attr_vector @@ tmp_val THEN
                    DELETE FROM metabib.record_sorter WHERE source = rid AND attr = attr_def.name;
                    INSERT INTO metabib.record_sorter (source, attr, value) VALUES (rid, attr_def.name, ccvm_row.code);
                END IF;
            END IF;

        END LOOP;

    END LOOP;

    IF ARRAY_LENGTH(attr_vector, 1) > 0 THEN
        IF rdeleted THEN -- initial insert OR revivication
            DELETE FROM metabib.record_attr_vector_list WHERE source = rid;
            INSERT INTO metabib.record_attr_vector_list (source, vlist) VALUES (rid, attr_vector);
        ELSE
            UPDATE metabib.record_attr_vector_list SET vlist = attr_vector WHERE source = rid;
        END IF;
    END IF;

END;

$func$ LANGUAGE PLPGSQL;


SELECT evergreen.upgrade_deps_block_check('0940', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.pg_statistics (tab TEXT, col TEXT) RETURNS TABLE(element TEXT, frequency INT) AS $$
BEGIN
    -- This query will die on PG < 9.2, but the function can be created. We just won't use it where we can't.
    RETURN QUERY
        SELECT  e,
                f
          FROM  (SELECT ROW_NUMBER() OVER (),
                        (f * 100)::INT AS f
                  FROM  (SELECT UNNEST(most_common_elem_freqs) AS f
                          FROM  pg_stats
                          WHERE tablename = tab
                                AND attname = col
                        )x
                ) AS f
                JOIN (SELECT ROW_NUMBER() OVER (),
                             e
                       FROM (SELECT UNNEST(most_common_elems::text::text[]) AS e
                              FROM  pg_stats 
                              WHERE tablename = tab
                                    AND attname = col
                            )y
                ) AS elems USING (row_number);
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION evergreen.query_int_wrapper (INT[],TEXT) RETURNS BOOL AS $$
BEGIN
    RETURN $1 @@ $2::query_int;
END;
$$ LANGUAGE PLPGSQL STABLE;


COMMIT;
