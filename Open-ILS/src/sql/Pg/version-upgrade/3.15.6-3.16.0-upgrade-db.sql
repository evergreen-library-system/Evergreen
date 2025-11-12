--Upgrade Script for 3.15.6 to 3.16.0
\set eg_version '''3.16.0'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.16.0', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1469', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES ('eg.circ.in_house.do_inventory_update', 'circ', 'bool',
    oils_i18n_gettext (
        'eg.circ.in_house.do_inventory_update',
        'In-House Use: Update Inventory',
        'cwst', 'label'
    )
);


SELECT evergreen.upgrade_deps_block_check('1470', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 688, 'UPDATE_HARD_DUE_DATE', oils_i18n_gettext(688,
     'Allow update hard due dates', 'ppl', 'description')),
 ( 689, 'CREATE_HARD_DUE_DATE', oils_i18n_gettext(689,
     'Allow create hard due dates', 'ppl', 'description')),
 ( 690, 'DELETE_HARD_DUE_DATE', oils_i18n_gettext(690,
     'Allow delete hard due dates', 'ppl', 'description')),
 ( 691, 'UPDATE_HARD_DUE_DATE_VALUE', oils_i18n_gettext(691,
     'Allow update hard due date values', 'ppl', 'description')),
 ( 692, 'CREATE_HARD_DUE_DATE_VALUE', oils_i18n_gettext(692,
     'Allow create hard due date values', 'ppl', 'description')),
 ( 693, 'DELETE_HARD_DUE_DATE_VALUE', oils_i18n_gettext(693,
     'Allow delete hard due date values', 'ppl', 'description'));

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Circulation Administrator' AND
		aout.name = 'System' AND
		perm.code IN (
			'CREATE_HARD_DUE_DATE',
			'DELETE_HARD_DUE_DATE',
			'UPDATE_HARD_DUE_DATE',
			'CREATE_HARD_DUE_DATE_VALUE',
			'DELETE_HARD_DUE_DATE_VALUE',
			'UPDATE_HARD_DUE_DATE_VALUE'
		);


SELECT evergreen.upgrade_deps_block_check('1473', :eg_version);

-- Basically the same thing as using cascade update, but the stat_cat_entry isn't a foreign key as it can be freetext
CREATE OR REPLACE FUNCTION actor.stat_cat_entry_usr_map_cascade_update() RETURNS TRIGGER AS $$
BEGIN
    UPDATE actor.stat_cat_entry_usr_map
    SET stat_cat_entry = NEW.value
    WHERE stat_cat_entry = OLD.value
        AND stat_cat = OLD.stat_cat;
        
    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;


DROP TRIGGER IF EXISTS actor_stat_cat_entry_update_trigger ON actor.stat_cat_entry;
CREATE TRIGGER actor_stat_cat_entry_update_trigger
    BEFORE UPDATE ON actor.stat_cat_entry FOR EACH ROW
    EXECUTE FUNCTION actor.stat_cat_entry_usr_map_cascade_update();


-- Basically the same thing as using cascade delete, but the stat_cat_entry isn't a foreign key as it can be freetext
CREATE OR REPLACE FUNCTION actor.stat_cat_entry_usr_map_cascade_delete() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM actor.stat_cat_entry_usr_map
    WHERE stat_cat_entry = OLD.value
        AND stat_cat = OLD.stat_cat;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

DROP TRIGGER IF EXISTS actor_stat_cat_entry_delete_trigger ON actor.stat_cat_entry;
CREATE TRIGGER actor_stat_cat_entry_delete_trigger
    AFTER DELETE ON actor.stat_cat_entry FOR EACH ROW
    EXECUTE FUNCTION actor.stat_cat_entry_usr_map_cascade_delete();



SELECT evergreen.upgrade_deps_block_check('1477', :eg_version);

ALTER TABLE config.hold_matrix_matchpoint ADD COLUMN copy_location INT REFERENCES asset.copy_location (id) DEFERRABLE INITIALLY DEFERRED;

DROP INDEX config.chmm_once_per_paramset;

CREATE UNIQUE INDEX chmm_once_per_paramset ON config.hold_matrix_matchpoint (COALESCE(user_home_ou::TEXT, ''), COALESCE(request_ou::TEXT, ''), COALESCE(pickup_ou::TEXT, ''), COALESCE(item_owning_ou::TEXT, ''), COALESCE(item_circ_ou::TEXT, ''), COALESCE(usr_grp::TEXT, ''), COALESCE(requestor_grp::TEXT, ''), COALESCE(circ_modifier, ''), COALESCE(copy_location::TEXT, ''), COALESCE(marc_type, ''), COALESCE(marc_form, ''), COALESCE(marc_bib_level, ''), COALESCE(marc_vr_format, ''), COALESCE(juvenile_flag::TEXT, ''), COALESCE(ref_flag::TEXT, ''), COALESCE(item_age, '0 seconds')) WHERE active;

CREATE OR REPLACE FUNCTION action.find_hold_matrix_matchpoint(pickup_ou integer, request_ou integer, match_item bigint, match_user integer, match_requestor integer)
  RETURNS integer AS
$func$
DECLARE
    requestor_object    actor.usr%ROWTYPE;
    user_object         actor.usr%ROWTYPE;
    item_object         asset.copy%ROWTYPE;
    item_cn_object      asset.call_number%ROWTYPE;
    my_item_age         INTERVAL;
    rec_descriptor      metabib.rec_descriptor%ROWTYPE;
    matchpoint          config.hold_matrix_matchpoint%ROWTYPE;
    weights             config.hold_matrix_weights%ROWTYPE;
    denominator         NUMERIC(6,2);
    v_pickup_ou         ALIAS FOR pickup_ou;
    v_request_ou         ALIAS FOR request_ou;
BEGIN
    SELECT INTO user_object         * FROM actor.usr                WHERE id = match_user;
    SELECT INTO requestor_object    * FROM actor.usr                WHERE id = match_requestor;
    SELECT INTO item_object         * FROM asset.copy               WHERE id = match_item;
    SELECT INTO item_cn_object      * FROM asset.call_number        WHERE id = item_object.call_number;
    SELECT INTO rec_descriptor      * FROM metabib.rec_descriptor   WHERE record = item_cn_object.record;

    SELECT INTO my_item_age age(coalesce(item_object.active_date, now()));

    -- The item's owner should probably be the one determining if the item is holdable
    -- How to decide that is debatable. Decided to default to the circ library (where the item lives)
    -- This flag will allow for setting it to the owning library (where the call number "lives")
    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.weight_owner_not_circ' AND enabled;

    -- Grab the closest set circ weight setting.
    IF NOT FOUND THEN
        -- Default to circ library
        SELECT INTO weights hw.*
          FROM config.weight_assoc wa
               JOIN config.hold_matrix_weights hw ON (hw.id = wa.hold_weights)
               JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) d ON (wa.org_unit = d.id)
          WHERE active
          ORDER BY d.distance
          LIMIT 1;
    ELSE
        -- Flag is set, use owning library
        SELECT INTO weights hw.*
          FROM config.weight_assoc wa
               JOIN config.hold_matrix_weights hw ON (hw.id = wa.hold_weights)
               JOIN actor.org_unit_ancestors_distance( item_cn_object.owning_lib ) d ON (wa.org_unit = d.id)
          WHERE active
          ORDER BY d.distance
          LIMIT 1;
    END IF;

    -- No weights? Bad admin! Defaults to handle that anyway.
    IF weights.id IS NULL THEN
        weights.user_home_ou    := 5.0;
        weights.request_ou      := 5.0;
        weights.pickup_ou       := 5.0;
        weights.item_owning_ou  := 5.0;
        weights.item_circ_ou    := 5.0;
        weights.usr_grp         := 7.0;
        weights.requestor_grp   := 8.0;
        weights.circ_modifier   := 4.0;
        weights.copy_location   := 4.0;
        weights.marc_type       := 3.0;
        weights.marc_form       := 2.0;
        weights.marc_bib_level  := 1.0;
        weights.marc_vr_format  := 1.0;
        weights.juvenile_flag   := 4.0;
        weights.ref_flag        := 0.0;
        weights.item_age        := 0.0;
    END IF;

    -- Determine the max (expected) depth (+1) of the org tree and max depth of the permisson tree
    -- If you break your org tree with funky parenting this may be wrong
    -- Note: This CTE is duplicated in the find_circ_matrix_matchpoint function, and it may be a good idea to split it off to a function
    -- We use one denominator for all tree-based checks for when permission groups and org units have the same weighting
    WITH all_distance(distance) AS (
            SELECT depth AS distance FROM actor.org_unit_type
        UNION
            SELECT distance AS distance FROM permission.grp_ancestors_distance((SELECT id FROM permission.grp_tree WHERE parent IS NULL))
	)
    SELECT INTO denominator MAX(distance) + 1 FROM all_distance;

    -- To ATTEMPT to make this work like it used to, make it reverse the user/requestor profile ids.
    -- This may be better implemented as part of the upgrade script?
    -- Set usr_grp = requestor_grp, requestor_grp = 1 or something when this flag is already set
    -- Then remove this flag, of course.
    PERFORM * FROM config.internal_flag WHERE name = 'circ.holds.usr_not_requestor' AND enabled;

    IF FOUND THEN
        -- Note: This, to me, is REALLY hacky. I put it in anyway.
        -- If you can't tell, this is a single call swap on two variables.
        SELECT INTO user_object.profile, requestor_object.profile
                    requestor_object.profile, user_object.profile;
    END IF;

    -- Select the winning matchpoint into the matchpoint variable for returning
    SELECT INTO matchpoint m.*
      FROM  config.hold_matrix_matchpoint m
            /*LEFT*/ JOIN permission.grp_ancestors_distance( requestor_object.profile ) rpgad ON m.requestor_grp = rpgad.id
            LEFT JOIN permission.grp_ancestors_distance( user_object.profile ) upgad ON m.usr_grp = upgad.id
            LEFT JOIN actor.org_unit_ancestors_distance( v_pickup_ou ) puoua ON m.pickup_ou = puoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( v_request_ou ) rqoua ON m.request_ou = rqoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_cn_object.owning_lib ) cnoua ON m.item_owning_ou = cnoua.id
            LEFT JOIN actor.org_unit_ancestors_distance( item_object.circ_lib ) iooua ON m.item_circ_ou = iooua.id
            LEFT JOIN actor.org_unit_ancestors_distance( user_object.home_ou  ) uhoua ON m.user_home_ou = uhoua.id
      WHERE m.active
            -- Permission Groups
         -- AND (m.requestor_grp        IS NULL OR upgad.id IS NOT NULL) -- Optional Requestor Group?
            AND (m.usr_grp              IS NULL OR upgad.id IS NOT NULL)
            -- Org Units
            AND (m.pickup_ou            IS NULL OR (puoua.id IS NOT NULL AND (puoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.request_ou           IS NULL OR (rqoua.id IS NOT NULL AND (rqoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.item_owning_ou       IS NULL OR (cnoua.id IS NOT NULL AND (cnoua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.item_circ_ou         IS NULL OR (iooua.id IS NOT NULL AND (iooua.distance = 0 OR NOT m.strict_ou_match)))
            AND (m.user_home_ou         IS NULL OR (uhoua.id IS NOT NULL AND (uhoua.distance = 0 OR NOT m.strict_ou_match)))
            -- Static User Checks
            AND (m.juvenile_flag        IS NULL OR m.juvenile_flag = user_object.juvenile)
            -- Static Item Checks
            AND (m.circ_modifier        IS NULL OR m.circ_modifier = item_object.circ_modifier)
            AND (m.copy_location        IS NULL OR m.copy_location = item_object.location)
            AND (m.marc_type            IS NULL OR m.marc_type = COALESCE(item_object.circ_as_type, rec_descriptor.item_type))
            AND (m.marc_form            IS NULL OR m.marc_form = rec_descriptor.item_form)
            AND (m.marc_bib_level       IS NULL OR m.marc_bib_level = rec_descriptor.bib_level)
            AND (m.marc_vr_format       IS NULL OR m.marc_vr_format = rec_descriptor.vr_format)
            AND (m.ref_flag             IS NULL OR m.ref_flag = item_object.ref)
            AND (m.item_age             IS NULL OR (my_item_age IS NOT NULL AND m.item_age > my_item_age))
      ORDER BY
            -- Permission Groups
            CASE WHEN rpgad.distance    IS NOT NULL THEN 2^(2*weights.requestor_grp - (rpgad.distance/denominator)) ELSE 0.0 END +
            CASE WHEN upgad.distance    IS NOT NULL THEN 2^(2*weights.usr_grp - (upgad.distance/denominator)) ELSE 0.0 END +
            -- Org Units
            CASE WHEN puoua.distance    IS NOT NULL THEN 2^(2*weights.pickup_ou - (puoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN rqoua.distance    IS NOT NULL THEN 2^(2*weights.request_ou - (rqoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN cnoua.distance    IS NOT NULL THEN 2^(2*weights.item_owning_ou - (cnoua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN iooua.distance    IS NOT NULL THEN 2^(2*weights.item_circ_ou - (iooua.distance/denominator)) ELSE 0.0 END +
            CASE WHEN uhoua.distance    IS NOT NULL THEN 2^(2*weights.user_home_ou - (uhoua.distance/denominator)) ELSE 0.0 END +
            -- Static User Checks       -- Note: 4^x is equiv to 2^(2*x)
            CASE WHEN m.juvenile_flag   IS NOT NULL THEN 4^weights.juvenile_flag ELSE 0.0 END +
            -- Static Item Checks
            CASE WHEN m.circ_modifier   IS NOT NULL THEN 4^weights.circ_modifier ELSE 0.0 END +
            CASE WHEN m.copy_location   IS NOT NULL THEN 4^weights.copy_location ELSE 0.0 END +
            CASE WHEN m.marc_type       IS NOT NULL THEN 4^weights.marc_type ELSE 0.0 END +
            CASE WHEN m.marc_form       IS NOT NULL THEN 4^weights.marc_form ELSE 0.0 END +
            CASE WHEN m.marc_vr_format  IS NOT NULL THEN 4^weights.marc_vr_format ELSE 0.0 END +
            CASE WHEN m.ref_flag        IS NOT NULL THEN 4^weights.ref_flag ELSE 0.0 END +
            -- Item age has a slight adjustment to weight based on value.
            -- This should ensure that a shorter age limit comes first when all else is equal.
            -- NOTE: This assumes that intervals will normally be in days.
            CASE WHEN m.item_age            IS NOT NULL THEN 4^weights.item_age - 86400/EXTRACT(EPOCH FROM m.item_age) ELSE 0.0 END DESC,
            -- Final sort on id, so that if two rules have the same sorting in the previous sort they have a defined order
            -- This prevents "we changed the table order by updating a rule, and we started getting different results"
            m.id;

    -- Return just the ID for now
    RETURN matchpoint.id;
END;
$func$ LANGUAGE 'plpgsql';

ALTER TABLE config.hold_matrix_weights ADD COLUMN copy_location NUMERIC(6,2);
-- we need to set some values, so initially, match whatever the weight for circ_modifier is
UPDATE config.hold_matrix_weights SET copy_location = circ_modifier;
ALTER TABLE config.hold_matrix_weights ALTER COLUMN copy_location SET NOT NULL;



SELECT evergreen.upgrade_deps_block_check('1483', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.admin.local.config.copy_alert_type', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.admin.local.config.copy_alert_type',
        'Grid Config: eg.grid.admin.local.config.copy_alert_type',
        'cwst', 'label'
    )
);



SELECT evergreen.upgrade_deps_block_check('1488', :eg_version);

INSERT INTO config.org_unit_setting_type (
name, grp, label, description, datatype
) VALUES (
  'ui.hide_clear_these_holds_button',
  'gui',
  oils_i18n_gettext(
    'ui.hide_clear_these_holds_button',
    'Hide the Clear These Holds button',
    'coust',
    'label'
  ),
  oils_i18n_gettext(
    'ui.hide_clear_these_holds_button',
    'Hide the Clear These Holds button from the Holds Shelf interface.',
    'coust',
    'description'
  ),
  'bool'
);


SELECT evergreen.upgrade_deps_block_check('1490', :eg_version);

CREATE TYPE asset.holdable_part_count AS (id INT, label TEXT, holdable_count BIGINT);
CREATE OR REPLACE FUNCTION asset.count_holdable_parts_on_record (record_id BIGINT, pickup_lib INT DEFAULT NULL) RETURNS SETOF asset.holdable_part_count AS $func$
DECLARE 
    hard_boundary                   INT;
    orgs_within_hard_boundary       INT[];
BEGIN

    SELECT value INTO hard_boundary 
    FROM actor.org_unit_ancestor_setting('circ.hold_boundary.hard', pickup_lib)
    LIMIT 1;

    IF hard_boundary IS NOT NULL THEN
        SELECT ARRAY_AGG(id) INTO orgs_within_hard_boundary
        FROM actor.org_unit_descendants(pickup_lib, hard_boundary);
    END IF;

    RETURN QUERY 
    SELECT 
        bmp.id, 
        bmp.label, 
        COUNT(DISTINCT acp.id) AS holdable_count
    FROM asset.copy_part_map acpm
        JOIN biblio.monograph_part bmp ON acpm.part = bmp.id
        JOIN asset.copy acp ON acpm.target_copy = acp.id
        JOIN asset.call_number acn ON acp.call_number = acn.id
        JOIN biblio.record_entry bre ON acn.record = bre.id
        JOIN config.copy_status ccs ON acp.status = ccs.id
        JOIN asset.copy_location acpl ON acp.location = acpl.id
    WHERE
        NOT bmp.deleted
        AND (NOT acp.deleted AND acp.holdable)
        AND bre.id = record_id
        AND ccs.holdable
        AND acpl.holdable
        -- Check the circ_lib, but only when given a pickup lib for our hold AND we have hard boundary restrictions
        AND CASE WHEN orgs_within_hard_boundary IS NOT NULL THEN 
                acp.circ_lib = ANY(orgs_within_hard_boundary)
            ELSE TRUE 
            END
    GROUP BY 1, 2
    ORDER BY bmp.label_sortkey ASC;
END;
$func$ LANGUAGE plpgsql;


SELECT evergreen.upgrade_deps_block_check('1491', :eg_version);

ALTER TABLE money.aged_payment ADD COLUMN refundable BOOL;

CREATE OR REPLACE VIEW money.payment_view AS
    SELECT  p.*,
            c.relname AS payment_type,
            COALESCE(f.enabled, TRUE) AS refundable
      FROM  money.payment p
            JOIN pg_class c ON (p.tableoid = c.oid)
            LEFT JOIN config.global_flag f ON ( f.name = p.tableoid::regclass||'.is_refundable');

CREATE OR REPLACE VIEW money.non_drawer_payment_view AS
    SELECT  p.*, c.relname AS payment_type, COALESCE(f.enabled, TRUE) AS refundable
      FROM  money.bnm_payment p
            JOIN pg_class c ON p.tableoid = c.oid
            LEFT JOIN config.global_flag f ON ( f.name = p.tableoid::regclass||'.is_refundable')
      WHERE c.relname NOT IN ('cash_payment','check_payment','credit_card_payment','debit_card_payment');

CREATE OR REPLACE VIEW money.cashdrawer_payment_view AS
    SELECT  ou.id AS org_unit,
        ws.id AS cashdrawer,
        t.payment_type AS payment_type,
        p.payment_ts AS payment_ts,
        p.amount AS amount,
        p.voided AS voided,
        p.note AS note,
        t.refundable AS refundable
      FROM  actor.org_unit ou
        JOIN actor.workstation ws ON (ou.id = ws.owning_lib)
        LEFT JOIN money.bnm_desk_payment p ON (ws.id = p.cash_drawer)
        LEFT JOIN money.payment_view t ON (p.id = t.id);

CREATE OR REPLACE VIEW money.desk_payment_view AS
    SELECT  p.*,c.relname AS payment_type,COALESCE(f.enabled, TRUE) AS refundable
      FROM  money.bnm_desk_payment p
        JOIN pg_class c ON (p.tableoid = c.oid)
        LEFT JOIN config.global_flag f ON ( f.name = p.tableoid::regclass||'.is_refundable');

CREATE OR REPLACE VIEW money.bnm_payment_view AS
    SELECT  p.*,c.relname AS payment_type,COALESCE(f.enabled, TRUE) AS refundable
      FROM  money.bnm_payment p
        JOIN pg_class c ON (p.tableoid = c.oid)
        LEFT JOIN config.global_flag f ON ( f.name = p.tableoid::regclass||'.is_refundable');

CREATE OR REPLACE VIEW money.payment_view_for_aging AS
    SELECT p.id,
        p.xact,
        p.payment_ts,
        p.voided,
        p.amount,
        p.note,
        p.payment_type,
        bnm.accepting_usr,
        bnmd.cash_drawer,
        maa.billing,
        p.refundable
    FROM money.payment_view p
    LEFT JOIN money.bnm_payment bnm ON bnm.id = p.id
    LEFT JOIN money.bnm_desk_payment bnmd ON bnmd.id = p.id
    LEFT JOIN money.account_adjustment maa ON maa.id = p.id;

CREATE OR REPLACE FUNCTION money.mbts_refundable_balance_check () RETURNS TRIGGER AS $$
BEGIN
    -- Check if the raw xact balance has gone negative (balance_owed may be adjusted by this very trigger!)
    IF NEW.total_owed - NEW.total_paid < 0.0 THEN

        -- If negative (a refund), we increase it by the non-refundable payment total, but only up to 0.0
        SELECT  LEAST(
                    COALESCE(SUM(amount),0.0) -- non-refundable payment total
                      + (NEW.total_owed - NEW.total_paid), -- raw balance
                    0.0
                ) INTO NEW.balance_owed -- update the NEW record
          FROM  money.payment_view
          WHERE NOT refundable
                AND xact = NEW.id
                AND NOT voided;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER mat_summary_refund_balance_check_tgr BEFORE UPDATE ON money.materialized_billable_xact_summary FOR EACH ROW EXECUTE PROCEDURE money.mbts_refundable_balance_check ();

INSERT INTO config.global_flag (name, label, enabled) VALUES
( 'money.account_adjustment.is_refundable',
  oils_i18n_gettext( 'money.account_adjustment.is_refundable', 'Money: Enable to allow account adjustments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.forgive_payment.is_refundable',
  oils_i18n_gettext( 'money.forgive_payment.is_refundable', 'Money: Enable to allow forgive payments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.work_payment.is_refundable',
  oils_i18n_gettext( 'money.work_payment.is_refundable', 'Money: Enable to allow work payments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.credit_payment.is_refundable',
  oils_i18n_gettext( 'money.credit_payment.is_refundable', 'Money: Enable to allow credit payments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.goods_payment.is_refundable',
  oils_i18n_gettext( 'money.goods_payment.is_refundable', 'Money: Enable to allow goods payments to be refundable to patrons', 'cgf', 'label'),
  FALSE ),
( 'money.credit_card_payment.is_refundable',
  oils_i18n_gettext( 'money.credit_card_payment.is_refundable', 'Money: Enable to allow credit card payments to be refundable to patrons', 'cgf', 'label'),
  TRUE ),
( 'money.cash_payment.is_refundable',
  oils_i18n_gettext( 'money.cash_payment.is_refundable', 'Money: Enable to allow cash payments to be refundable to patrons', 'cgf', 'label'),
  TRUE ),
( 'money.check_payment.is_refundable',
  oils_i18n_gettext( 'money.check_payment.is_refundable', 'Money: Enable to allow check payments to be refundable to patrons', 'cgf', 'label'),
  TRUE ),
( 'money.debit_card_payment.is_refundable',
  oils_i18n_gettext( 'money.debit_card_payment.is_refundable', 'Money: Enable to allow debit card payments to be refundable to patrons', 'cgf', 'label'),
  TRUE )
;



SELECT evergreen.upgrade_deps_block_check('1493', :eg_version);
ALTER TABLE actor.org_lasso ADD COLUMN IF NOT EXISTS opac_visible BOOL NOT NULL DEFAULT TRUE;


-- Bootstrap KPAC Configuration Interface

SELECT evergreen.upgrade_deps_block_check('1494', :eg_version);

CREATE TABLE config.kpac_content_types (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL
);

INSERT INTO config.kpac_content_types
    (id, name)
VALUES
    (1, 'Category'),
    (2, 'Book List'),
    (3, 'URL'),
    (4, 'Search String')
; 

CREATE TABLE config.kpac_topics (
    id              SERIAL PRIMARY KEY,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    parent          INTEGER, -- empty is home / top level entry
    img             TEXT, -- image file name
    name            TEXT NOT NULL,
    description     TEXT,
    content_type    INTEGER NOT NULL REFERENCES config.kpac_content_types (id),
    content_list    INTEGER, -- bookbag id
    content_link    TEXT, -- url
    content_search  TEXT, -- preset search string
    topic_order     INTEGER
);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
   'eg.grid.admin.server.config.kpac_topics', 'gui', 'object',
   oils_i18n_gettext(
       'eg.grid.admin.server.config.kpac_topics',
       'Grid Config: KPAC topics',
       'cwst', 'label')
);

INSERT into config.org_unit_setting_type
	(name, grp, label, description, datatype)
VALUES (
	'opac.show_kpac_link',
	'opac',
	oils_i18n_gettext('opac.show_kpac_link',
    	'Show KPAC Link',
    	'coust', 'label'),
	oils_i18n_gettext('opac.show_kpac_link',
    	'Show the KPAC link in the OPAC. Default is false.',
    	'coust', 'description'),
	'bool'
);

INSERT into permission.perm_list
    (code, description)
VALUES (
    'KPAC_ADMIN',
    'Allow user to configure KPAC category and topic entries'
);

INSERT into config.org_unit_setting_type
	(name, grp, label, description, datatype)
VALUES (
	'opac.kpac_audn_filter',
	'opac',
    oils_i18n_gettext('opac.kpac_audn_filter',
        'KPAC Audience Filter',
        'coust', 'label'),
	oils_i18n_gettext('opac.kpac_audn_filter',
        'Controls which items to display based on MARC Target Audience (Audn) field. Options are: a,b,c,d,j. Default is: a,b,c,j',
        'coust', 'description'),
	'string'
);





SELECT evergreen.upgrade_deps_block_check('1495', :eg_version);

-- NOTE: Perm 627 is SSO_ADMIN
INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype, update_perm )
VALUES
('staff.login.shib_sso.enable',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.enable', 'Enable Shibboleth SSO for the Staff Client', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.enable', 'Enable Shibboleth SSO for the Staff Client', 'coust', 'description'),
 'bool', 627),
('staff.login.shib_sso.entityId',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.entityId', 'Shibboleth Staff SSO Entity ID', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.entityId', 'Which configured Entity ID to use for SSO when there is more than one available to Shibboleth', 'coust', 'description'),
 'string', 627),
('staff.login.shib_sso.logout',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.logout', 'Log out of the Staff Shibboleth IdP', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.logout', 'When logging out of Evergreen, also force a logout of the IdP behind Shibboleth', 'coust', 'description'),
 'bool', 627),
('staff.login.shib_sso.allow_native',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.allow_native', 'Allow both Shibboleth and native Staff Client authentication', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.allow_native', 'When Shibboleth SSO is enabled, also allow native Evergreen authentication', 'coust', 'description'),
 'bool', 627),
('staff.login.shib_sso.evergreen_matchpoint',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.evergreen_matchpoint', 'Evergreen Staff SSO matchpoint', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.evergreen_matchpoint',
  'Evergreen-side field to match a patron against for Shibboleth SSO. Default is usrname.  Other reasonable values would be barcode or email.',
  'coust', 'description'),
 'string', 627),
('staff.login.shib_sso.shib_matchpoint',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.shib_matchpoint', 'Shibboleth Staff SSO matchpoint', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.shib_matchpoint',
  'Shibboleth-side field to match a patron against for Shibboleth SSO. Default is uid; use eppn for Active Directory', 'coust', 'description'),
 'string', 627),
 ('staff.login.shib_sso.shib_path',
 'sec',
 oils_i18n_gettext('staff.login.shib_sso.shib_path', 'Specific Shibboleth Application path. Default /Shibboleth.sso', 'coust', 'label'),
 oils_i18n_gettext('staff.login.shib_sso.shib_path', 'Specific Shibboleth Application path. Default /Shibboleth.sso', 'coust', 'description'),
 'string', 627)
;


SELECT evergreen.upgrade_deps_block_check('1496', :eg_version);

ALTER TABLE actor.org_unit
	ADD COLUMN staff_catalog_visible BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE actor.org_unit
    SET staff_catalog_visible=opac_visible;

CREATE OR REPLACE FUNCTION asset.staff_ou_record_copy_count(org integer, rid bigint)
 RETURNS TABLE(depth integer, org_unit integer, visible bigint, available bigint, unshadow bigint, transcendant integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    ans RECORD;
    trans INT;
BEGIN
    SELECT 1 INTO trans FROM biblio.record_entry b JOIN config.bib_source src ON (b.source = src.id) WHERE src.transcendant AND b.id = rid;

    FOR ans IN SELECT u.id, t.depth FROM actor.org_unit_ancestors(org) AS u JOIN actor.org_unit_type t ON (u.ou_type = t.id) WHERE staff_catalog_visible LOOP
        RETURN QUERY
        WITH available_statuses AS (SELECT ARRAY_AGG(id) AS ids FROM config.copy_status WHERE is_available),
            cp AS(
                SELECT  cp.id,
                        (cp.status = ANY (available_statuses.ids))::INT as available,
                        (cl.opac_visible AND cp.opac_visible)::INT as opac_visible
                  FROM
                        available_statuses,
                        actor.org_unit_descendants(ans.id) d
                        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                        JOIN asset.call_number cn ON (cn.record = rid AND cn.id = cp.call_number AND NOT cn.deleted)
            ),
            peer AS (
                select  cp.id,
                        (cp.status = ANY  (available_statuses.ids))::INT as available,
                        (cl.opac_visible AND cp.opac_visible)::INT as opac_visible
                FROM
                        available_statuses,
                        actor.org_unit_descendants(ans.id) d
                        JOIN asset.copy cp ON (cp.circ_lib = d.id AND NOT cp.deleted)
                        JOIN asset.copy_location cl ON (cp.location = cl.id AND NOT cl.deleted)
                        JOIN biblio.peer_bib_copy_map bp ON (bp.peer_record = rid AND bp.target_copy = cp.id)
            )
        select ans.depth, ans.id, count(id), sum(x.available::int), sum(x.opac_visible::int), trans
        from ((select * from cp) union (select * from peer)) x
        group by 1,2,6;

        IF NOT FOUND THEN
            RETURN QUERY SELECT ans.depth, ans.id, 0::BIGINT, 0::BIGINT, 0::BIGINT, trans;
        END IF;

    END LOOP;
    RETURN;
END;
$function$;


INSERT INTO config.global_flag (name, enabled, label)
    VALUES (
        'staff.search.shelving_location_groups_with_orgs', TRUE,
        oils_i18n_gettext(
            'staff.search.shelving_location_groups_with_orgs',
            'Staff Catalog Search: Display shelving location groups inside the Organizational Unit Selector',
            'cgf',
            'label'
        )
);


SELECT evergreen.upgrade_deps_block_check('1497', :eg_version); -- berick/csharp/Dyrcona/phasefx

-- Thank you, berick :-)
-- Start at 100 to avoid barcodes with long stretches of zeros early on.
-- eCard barcodes have 7 auto-generated digits.
CREATE SEQUENCE actor.auto_barcode_ecard_seq START 100 MAXVALUE 9999999;

CREATE OR REPLACE FUNCTION actor.generate_barcode
    (prefix TEXT, numchars INTEGER, seqname TEXT) RETURNS TEXT AS
$$
    SELECT NEXTVAL($3); -- bump the sequence up 1
    SELECT CASE
        WHEN LENGTH(CURRVAL($3)::TEXT) > $2 THEN NULL
        ELSE $1 || LPAD(CURRVAL($3)::TEXT, $2, '0')
    END;
$$ LANGUAGE SQL;

COMMENT ON FUNCTION actor.generate_barcode(TEXT, INTEGER, TEXT) IS $$
Generate a barcode starting with 'prefix' and followed by 'numchars'
numbers.  The auto portion numbers are generated from the provided
sequence, guaranteeing uniquness across all barcodes generated with
the same sequence.  The number is left-padded with zeros to meet the
numchars size requirement.  Returns NULL if the sequnce value is
higher than numchars can accommodate.
$$;

CREATE OR REPLACE FUNCTION evergreen.json_delta(old_obj JSON, new_obj JSON, only_keys TEXT[] DEFAULT '{}') RETURNS JSONB AS $f$
use JSON;
use List::Util qw/uniq/;

my $old = shift;
my $new = shift;
my $keylist = shift;

$old = from_json($old) if (!ref($old));
$new = from_json($new) if (!ref($new));

my $delta = {};

my @keys = @$keylist;
@keys = (keys(%$old), keys(%$new)) if (!@keys);

for my $key (uniq @keys) {
    $$delta{$key} = [$$old{$key},$$new{$key}] if ((
        ((!exists($$old{$key}) or !exists($$new{$key})) and not (!exists($$old{$key}) and !exists($$new{$key}))) # one exists
        or ((!defined($$old{$key}) or !defined($$new{$key})) and not (!defined($$old{$key}) and !defined($$new{$key}))) # or one is defined
        or ((defined($$old{$key}) and defined($$new{$key})) and $$old{$key} ne $$new{$key}) # or they do not match
    ) and grep {defined} $$old{$key},$$new{$key}); # there is data
}

return to_json($delta);
$f$ LANGUAGE PLPERLU;

CREATE TABLE actor.usr_delta_history (
    id          BIGSERIAL   PRIMARY KEY,
    eg_user     INT         REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE SET NULL,
    eg_ws       INT         REFERENCES actor.workstation (id) ON UPDATE CASCADE ON DELETE SET NULL,
    usr_id      INT         NOT NULL REFERENCES actor.usr (id) ON UPDATE CASCADE ON DELETE CASCADE,
    change_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delta       JSONB       NOT NULL,
    keylist     TEXT[]
);

CREATE OR REPLACE FUNCTION actor.record_usr_delta() RETURNS TRIGGER AS $f$
BEGIN
    INSERT INTO actor.usr_delta_history (eg_user, eg_ws, usr_id, delta, keylist)
        SELECT  a.eg_user,
                a.eg_ws,
                OLD.id,
                evergreen.json_delta(to_json(OLD.*), to_json(NEW.*), TG_ARGV),
                TG_ARGV
          FROM  auditor.get_audit_info() a;
    RETURN NEW;
END;
$f$ LANGUAGE PLPGSQL;

CREATE TRIGGER record_usr_delta
    AFTER UPDATE ON actor.usr
    FOR EACH ROW
    EXECUTE FUNCTION actor.record_usr_delta(last_update_time /* unquoted, literal comma-separated column names to include in the delta */);
ALTER TABLE actor.usr DISABLE TRIGGER record_usr_delta;
ALTER TABLE permission.grp_tree ADD COLUMN erenew BOOL NOT NULL DEFAULT FALSE;
ALTER TABLE permission.grp_tree ADD COLUMN temporary_perm_interval INTERVAL;
ALTER TABLE actor.usr ADD COLUMN guardian_email TEXT;

SELECT auditor.update_auditors(); 

-- for guardian_email
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
			guardian_email = NULL,
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

---


SELECT evergreen.upgrade_deps_block_check('1498', :eg_version); -- berick/csharp/Dyrcona/phasefx

INSERT INTO actor.passwd_type
    (code, name, login, crypt_algo, iter_count)
    VALUES ('ecard_vendor', 'eCard Vendor Password', FALSE, 'bf', 10);

-- Example linking a SIP password to the 'admin' account.
-- SELECT actor.set_passwd(1, 'ecard_vendor', 'ecard_password');

INSERT INTO config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class )
VALUES
( 'opac.ecard_registration_enabled', 'opac',
    oils_i18n_gettext('opac.ecard_registration_enabled',
        'Enable eCard registration feature in the OPAC',
        'coust', 'label'),
    oils_i18n_gettext('opac.ecard_registration_enabled',
        'Enable access to the eCard registration form in the OPAC',
        'coust', 'description'),
    'bool', null)
,( 'opac.ecard_verification_enabled', 'opac',
    oils_i18n_gettext('opac.ecard_verification_enabled',
        'Enable eCard verification feature in the OPAC',
        'coust', 'label'),
    oils_i18n_gettext('opac.ecard_verification_enabled',
        'Enable access to the eCard verification form in the OPAC',
        'coust', 'description'),
    'bool', null)
,( 'opac.ecard_renewal_enabled', 'opac',
    oils_i18n_gettext('opac.ecard_renewal_enabled',
        'Enable eCard request renewal feature in the OPAC',
        'coust', 'label'),
    oils_i18n_gettext('opac.ecard_renewal_enabled',
        'Enable access to the eCard request renewal form in the OPAC',
        'coust', 'description'),
    'bool', null)
,( 'opac.ecard_renewal_offer_interval', 'opac',
    oils_i18n_gettext('opac.ecard_renewal_offer_interval',
        'Number of days before account expiration in which to offer an e-renewal.',
        'coust', 'label'),
    oils_i18n_gettext('opac.ecard_renewal_offer_interval',
        'Number of days before account expiration in which to offer an e-renewal.',
        'coust', 'description'),
    'interval', null)
,( 'vendor.quipu.ecard.account_id', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.account_id',
        'Quipu eCard Customer Account',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.account_id',
        'Quipu Customer Account ID to be used for eCard registration',
        'coust', 'description'),
    'integer', null)
,( 'vendor.quipu.ecard.hostname', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.hostname',
        'Quipu eCard/eRenew Fully Qualified Domain Name',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.hostname',
        'Quipu ecard/eRenew Fully Qualified Domain Name is the external hostname for the Quipu server. Defaults to ecard.quipugroup.net',
        'coust', 'description'),
    'string', null)
,( 'vendor.quipu.ecard.shared_secret', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.shared_secret',
        'Quipu eCard Shared Secret',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.shared_secret',
        'Quipu Customer Account shared secret to be used for eCard authentication',
        'coust', 'description'),
    'string', null)
,( 'vendor.quipu.ecard.barcode_prefix', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.barcode_prefix',
        'Barcode prefix for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.barcode_prefix',
        'Set the barcode prefix for new Quipu eCard users',
        'coust', 'description'),
    'string', null)
,( 'vendor.quipu.ecard.barcode_length', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.barcode_length',
        'Barcode length for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.barcode_length',
        'Set the barcode length for new Quipu eCard users',
        'coust', 'description'),
    'integer', null)
,( 'vendor.quipu.ecard.calculate_checkdigit', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.calculate_checkdigit',
        'Calculate barcode checkdigit for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.calculate_checkdigit',
        'Calculate the barcode check digit for new Quipu eCard users',
        'coust', 'description'),
    'bool', null)
,( 'vendor.quipu.ecard.patron_profile', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.patron_profile',
        'Patron permission profile for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.patron_profile',
        'Patron permission profile for Quipu eCard feature',
        'coust', 'description'),
    'link', 'pgt')
,( 'vendor.quipu.ecard.patron_profile.verified', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.patron_profile.verified',
        'Patron permission profile after verification for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.patron_profile.verified',
        'Patron permission profile after verification for Quipu eCard feature. This is only used if the setting "Enable eCard verification feature in the OPAC" is active.',
        'coust', 'description'),
    'link', 'pgt')
,( 'vendor.quipu.ecard.admin_usrname', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.admin_usrname',
        'Evergreen Admin Username for the Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.admin_usrname',
        'Username of the Evergreen admin account that will create new Quipu eCard users',
        'coust', 'description'),
    'string', null)
,( 'vendor.quipu.ecard.admin_org_unit', 'lib',
    oils_i18n_gettext('vendor.quipu.ecard.admin_org_unit',
        'Admin organizational unit for Quipu eCard feature',
        'coust', 'label'),
    oils_i18n_gettext('vendor.quipu.ecard.admin_org_unit',
        'Organizational unit used by the Evergreen admin user of the Quipu eCard feature',
        'coust', 'description'),
    'link', 'aou')
;

-- A/T seed data
INSERT into action_trigger.hook (key, core_type, description) VALUES
( 'au.create.ecard', 'au', 'A patron has been created via Ecard');

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    'f', 1, 'Send Ecard Verification Email', 'au.create.ecard', 'NOOP_True', 'SendEmail', '00:00:00',
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = target.home_ou -%]
To: [%- params.recipient_email || user_data.email || user_data.0.email || user.email %]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Reply-To: [%- lib.email || params.sender_email || default_sender %]
Subject: Your Library Ecard Verification Code
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],

We will never call to ask you for this code, and make sure you do not share it with anyone calling you directly.

Use this code to verify the Ecard registration for your Evergreen account:

One-Time code: [% user.ident_value2 %]

Sincerely,
[% lib.name %]

Contact your library for more information:

[% lib.name %]
[%- SET addr = lib.mailing_address -%]
[%- IF !addr -%] [%- SET addr = lib.billing_address -%] [%- END %]
[% addr.street1 %] [% addr.street2 %]
[% addr.city %], [% addr.state %]
[% addr.post_code %]
[% lib.phone %]
$$);

INSERT INTO action_trigger.environment (event_def, path)
VALUES (currval('action_trigger.event_definition_id_seq'), 'home_ou'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.mailing_address'),
       (currval('action_trigger.event_definition_id_seq'), 'home_ou.billing_address');

-- ID has to be under 100 in order to prevent it from appearing as a dropdown in the patron editor.
INSERT INTO config.standing_penalty (id, name, label, staff_alert, org_depth) 
VALUES (90, 'PATRON_TEMP_RENEWAL',
	'Patron was given a temporary account renewal. 
	Please archive this message after the account is fully renewed.', TRUE, 0
	);

INSERT into config.org_unit_setting_type (name, label, description, datatype) 
VALUES ( 
    'ui.patron.edit.au.guardian_email.show',
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian_email.show', 
        'GUI: Show guardian email field on patron registration', 
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian_email.show', 
        'The guardian email field will be shown on the patron registration screen. Showing a field makes it appear with required fields even when not required. If the field is required this setting is ignored.', 
        'coust', 'description'
    ),
    'bool'
), (
    'ui.patron.edit.au.guardian_email.suggest',
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian_email.suggest', 
        'GUI: Suggest guardian email field on patron registration', 
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'ui.patron.edit.au.guardian_email.suggest', 
        'The guardian email field will be suggested on the patron registration screen. Suggesting a field makes it appear when suggested fields are shown. If the field is shown or required this setting is ignored.', 
        'coust', 'description'),
    'bool'
);


SELECT evergreen.upgrade_deps_block_check('1499', :eg_version);

CREATE OR REPLACE FUNCTION metabib.disable_browse_entry_reification () RETURNS VOID AS $f$
    INSERT INTO config.internal_flag (name,enabled)
      VALUES ('ingest.disable_browse_entry_reification',TRUE)
    ON CONFLICT (name) DO UPDATE SET enabled = TRUE;
$f$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION metabib.enable_browse_entry_reification () RETURNS VOID AS $f$
    UPDATE config.internal_flag SET enabled = FALSE WHERE name = 'ingest.disable_browse_entry_reification';
$f$ LANGUAGE SQL;


-- INSERT-only table that catches browse entry updates to be reconciled
CREATE UNLOGGED TABLE metabib.browse_entry_updates (
    transaction_id  BIGINT,
    simple_heading  BIGINT,
    source          BIGINT,
    authority       BIGINT,
    def             INT,
    sort_value      TEXT,
    value           TEXT
);
CREATE INDEX browse_entry_updates_tid_idx ON metabib.browse_entry_updates (transaction_id);

CREATE OR REPLACE FUNCTION metabib.browse_entry_reify (full_reify BOOLEAN DEFAULT FALSE) RETURNS INT AS $f$
  WITH new_authority_rows AS ( -- gather provisional authority browse entries
      DELETE FROM metabib.browse_entry_updates
        WHERE simple_heading IS NOT NULL AND (full_reify OR transaction_id = txid_current())
        RETURNING sort_value, value, simple_heading
  ), new_bib_rows AS ( -- gather provisional bib browse entries
      DELETE FROM metabib.browse_entry_updates
        WHERE def IS NOT NULL AND (full_reify OR transaction_id = txid_current())
        RETURNING sort_value, value, def, source, authority
  ), computed_browse_values AS ( -- unique set of to-be-mapped sort_value/value pairs :: sort_value, value, def, cmf.browse_nocase
      SELECT  nbr.sort_value, nbr.value, nbr.def, cmf.browse_nocase
        FROM  new_bib_rows AS nbr JOIN config.metabib_field AS cmf ON (nbr.def = cmf.id)
          UNION
      SELECT  sort_value, value, NULL::INT AS def, FALSE AS browse_nocase
        FROM new_authority_rows
  ), existing_browse_entries AS ( -- find the id of existing sort_value/value pairs, nocase'd if cmf says so :: id, sort_value, value, def (NULL for authority)
      SELECT  mbe.id, cr.sort_value, cr.value, cr.def
        FROM  metabib.browse_entry mbe
              JOIN computed_browse_values cr ON (
                  mbe.sort_value = cr.sort_value
                  AND (
                    (cr.browse_nocase AND evergreen.lowercase(mbe.value) = evergreen.lowercase(cr.value))
                    OR (NOT cr.browse_nocase AND mbe.value = cr.value)
                  )
              )
  ), missing_browse_entries AS ( -- unique set of sort_value/value pairs NOT in the browse_entry table
      SELECT DISTINCT sort_value, value FROM computed_browse_values
          EXCEPT
      SELECT sort_value, value FROM existing_browse_entries
  ), inserted_browse_entries AS ( -- insert missing sort_value/value pairs and get the new id for each
      INSERT INTO metabib.browse_entry (sort_value, value)
          SELECT sort_value, value FROM missing_browse_entries ON CONFLICT DO NOTHING RETURNING id, sort_value, value
  ), computed_browse_entries AS ( -- full set of to-be-mapped sort_value/value pairs with the id for each
      SELECT id, sort_value, value, def FROM existing_browse_entries
          UNION ALL
      SELECT id, sort_value, value, NULL::INT def FROM inserted_browse_entries
  ), new_authority_browse_map AS ( -- insert entry->simple_heading map now that all sort_value/value pairs have an id
      INSERT INTO metabib.browse_entry_simple_heading_map (entry, simple_heading)
          SELECT  cbe.id, nar.simple_heading
            FROM  computed_browse_entries cbe
                  JOIN new_authority_rows nar USING (sort_value, value)
      RETURNING *
  ), new_bib_browse_map AS ( -- insert entry->dev/source/authority map now that all sort_value/value pairs have an id
      INSERT INTO metabib.browse_entry_def_map (entry, def, source, authority)
          SELECT  cbe.id, nbr.def, nbr.source, nbr.authority
            FROM  computed_browse_entries cbe
                  JOIN new_bib_rows nbr USING (sort_value, value, def)
            WHERE cbe.def IS NOT NULL
              UNION
          SELECT  cbe.id, nbr.def, nbr.source, nbr.authority
            FROM  computed_browse_entries cbe
                  JOIN new_bib_rows nbr USING (sort_value, value)
            WHERE cbe.def IS NULL
      RETURNING *
  )
  SELECT  a.row_count + b.row_count
    FROM  (SELECT COUNT(*) AS row_count FROM new_authority_browse_map) AS a,
          (SELECT COUNT(*) AS row_count FROM new_bib_browse_map) AS b;
$f$ LANGUAGE SQL;

-- This version does not constrain itself to just the current transaction.
CREATE OR REPLACE FUNCTION metabib.browse_entry_full_reify () RETURNS INT AS $f$
    SELECT metabib.browse_entry_reify(TRUE);
$f$ LANGUAGE SQL;

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
                EXECUTE $$DELETE FROM metabib.$$ || fclass.name || $$_field_entry WHERE source = $$ || bib_id || $$ AND field = ANY($1)$$ USING field_list;
            END LOOP;
        END IF;
        IF NOT b_skip_facet THEN
            DELETE FROM metabib.facet_entry WHERE source = bib_id AND field = ANY(field_list);
        END IF;
        IF NOT b_skip_display THEN
            DELETE FROM metabib.display_entry WHERE source = bib_id AND field = ANY(field_list);
        END IF;
        IF NOT b_skip_browse THEN
            DELETE FROM metabib.browse_entry_def_map WHERE source = bib_id AND def = ANY(field_list);
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

            CONTINUE WHEN ind_data.sort_value IS NULL;

            INSERT INTO metabib.browse_entry_updates (transaction_id, sort_value, value, def, source, authority)
                VALUES (txid_current(), SUBSTRING(ind_data.sort_value FOR 1000), SUBSTRING(metabib.browse_normalize(ind_data.value, ind_data.field) FOR 1000),
                        ind_data.field, ind_data.source, ind_data.authority);

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
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_symspell_reification' AND enabled;
        IF NOT FOUND THEN
            PERFORM search.symspell_dictionary_reify();
        END IF;
    END IF;

    IF NOT b_skip_browse THEN
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_browse_entry_reification' AND enabled;
        IF NOT FOUND THEN
            PERFORM metabib.browse_entry_reify();
        END IF;
    END IF;

    RETURN;
END;
$func$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION authority.indexing_update (auth authority.record_entry, insert_only BOOL DEFAULT FALSE, old_heading TEXT DEFAULT NULL) RETURNS BOOL AS $func$
DECLARE
    ashs    authority.simple_heading%ROWTYPE;
    mbe_row metabib.browse_entry%ROWTYPE;
    mbe_id  BIGINT;
    ash_id  BIGINT;
    diag_detail     TEXT;
    diag_context    TEXT;
BEGIN

    -- Unless there's a setting stopping us, propagate these updates to any linked bib records when the heading changes
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_auto_update' AND enabled;

    IF NOT FOUND AND auth.heading <> old_heading THEN
        PERFORM authority.propagate_changes(auth.id);
    END IF;

    IF NOT insert_only THEN
        DELETE FROM authority.authority_linking WHERE source = auth.id;
        DELETE FROM authority.simple_heading WHERE record = auth.id;
    END IF;

    INSERT INTO authority.authority_linking (source, target, field)
        SELECT source, target, field FROM authority.calculate_authority_linking(
            auth.id, auth.control_set, auth.marc::XML
        );

    FOR ashs IN SELECT * FROM authority.simple_heading_set(auth.marc) LOOP

        INSERT INTO authority.simple_heading (record,atag,value,sort_value,thesaurus)
            VALUES (ashs.record, ashs.atag, ashs.value, ashs.sort_value, ashs.thesaurus);
            ash_id := CURRVAL('authority.simple_heading_id_seq'::REGCLASS);

        INSERT INTO metabib.browse_entry_updates (transaction_id, sort_value, value, simple_heading)
            VALUES (txid_current(), SUBSTRING(ashs.sort_value FOR 1000), SUBSTRING(ashs.value FOR 1000), ash_id);

    END LOOP;

    -- Flatten and insert the afr data
    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_full_rec' AND enabled;
    IF NOT FOUND THEN
        PERFORM authority.reingest_authority_full_rec(auth.id);
        PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_authority_rec_descriptor' AND enabled;
        IF NOT FOUND THEN
            PERFORM authority.reingest_authority_rec_descriptor(auth.id);
        END IF;
    END IF;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_symspell_reification' AND enabled;
    IF NOT FOUND THEN
        PERFORM search.symspell_dictionary_reify();
    END IF;

    PERFORM * FROM config.internal_flag WHERE name = 'ingest.disable_browse_entry_reification' AND enabled;
    IF NOT FOUND THEN
        PERFORM metabib.browse_entry_reify();
    END IF;

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS diag_detail  = PG_EXCEPTION_DETAIL,
                            diag_context = PG_EXCEPTION_CONTEXT;
    RAISE WARNING '%\n%', diag_detail, diag_context;
    RETURN FALSE;
END;
$func$ LANGUAGE PLPGSQL;



SELECT evergreen.upgrade_deps_block_check('1500', :eg_version);

INSERT INTO config.record_attr_definition (name,label,sorter,filter,tag,sf_list,multi,vocabulary) VALUES
 ('a11yAccessMode',oils_i18n_gettext('a11yAccessMode', 'Content access mode', 'crad', 'label'),FALSE,TRUE,'341','a',TRUE,'https://schema.org/accessMode'),
 ('a11yTextFeatures',oils_i18n_gettext('a11yTextFeatures', 'Textual assistive features', 'crad', 'label'),FALSE,TRUE,'341','b',TRUE,'https://schema.org/accessibilityFeature'),
 ('a11yVisualFeatures',oils_i18n_gettext('a11yVisualFeatures', 'Visual assistive features', 'crad', 'label'),FALSE,TRUE,'341','c',TRUE,'https://schema.org/accessibilityFeature'),
 ('a11yAuditoryFeatures',oils_i18n_gettext('a11yAuditoryFeatures', 'Auditory assistive features', 'crad', 'label'),FALSE,TRUE,'341','d',TRUE,'https://schema.org/accessibilityFeature'),
 ('a11yTactileFeatures',oils_i18n_gettext('a11yTactileFeatures', 'Tactile assistive features', 'crad', 'label'),FALSE,TRUE,'341','e',TRUE,'https://schema.org/accessibilityFeature')
;

INSERT INTO config.coded_value_map (id, opac_visible, ctype, code, value, search_label) VALUES
 (1753,true,'a11yAccessMode','auditory',oils_i18n_gettext('1753','Auditory','ccvm','value'),oils_i18n_gettext('1753','Auditory','ccvm','search_label')),
 (1754,true,'a11yAccessMode','textual',oils_i18n_gettext('1754','Textual','ccvm','value'),oils_i18n_gettext('1754','Textual','ccvm','search_label')),
 (1755,true,'a11yAccessMode','visual',oils_i18n_gettext('1755','Visual','ccvm','value'),oils_i18n_gettext('1755','Visual','ccvm','search_label')),
 (1756,true,'a11yAccessMode','tactile',oils_i18n_gettext('1756','Tactile','ccvm','value'),oils_i18n_gettext('1756','Tactile','ccvm','search_label')),
 (1757,true,'a11yTextFeatures','annotations',oils_i18n_gettext('1757','annotations','ccvm','value'),oils_i18n_gettext('1757','Annotations','ccvm','search_label')),
 (1758,true,'a11yTextFeatures','ARIA',oils_i18n_gettext('1758','ARIA','ccvm','value'),oils_i18n_gettext('1758','ARIA','ccvm','search_label')),
 (1759,true,'a11yTextFeatures','bookmarks',oils_i18n_gettext('1759','bookmarks','ccvm','value'),oils_i18n_gettext('1759','Bookmarks','ccvm','search_label')),
 (1760,true,'a11yTextFeatures','index',oils_i18n_gettext('1760','index','ccvm','value'),oils_i18n_gettext('1760','Index','ccvm','search_label')),
 (1761,true,'a11yTextFeatures','pageBreakMarkers',oils_i18n_gettext('1761','pageBreakMarkers','ccvm','value'),oils_i18n_gettext('1761','Page break markers','ccvm','search_label')),
 (1762,false,'a11yTextFeatures','pageNavigation',oils_i18n_gettext('1762','pageNavigation','ccvm','value'),oils_i18n_gettext('1762','Page navigation','ccvm','search_label')),
 (1763,true,'a11yTextFeatures','readingOrder',oils_i18n_gettext('1763','readingOrder','ccvm','value'),oils_i18n_gettext('1763','Reading order','ccvm','search_label')),
 (1764,true,'a11yTextFeatures','structuralNavigation',oils_i18n_gettext('1764','structuralNavigation','ccvm','value'),oils_i18n_gettext('1764','Structural navigation','ccvm','search_label')),
 (1765,true,'a11yTextFeatures','tableOfContents',oils_i18n_gettext('1765','tableOfContents','ccvm','value'),oils_i18n_gettext('1765','Table of contents','ccvm','search_label')),
 (1766,true,'a11yTextFeatures','taggedPDF',oils_i18n_gettext('1766','taggedPDF','ccvm','value'),oils_i18n_gettext('1766','Tagged PDF','ccvm','search_label')),
 (1767,true,'a11yTextFeatures','alternativeText',oils_i18n_gettext('1767','alternativeText','ccvm','value'),oils_i18n_gettext('1767','Alternative text','ccvm','search_label')),
 (1768,true,'a11yTextFeatures','captions',oils_i18n_gettext('1768','captions','ccvm','value'),oils_i18n_gettext('1768','Captions','ccvm','search_label')),
 (1769,true,'a11yTextFeatures','closedCaptions',oils_i18n_gettext('1769','closedCaptions','ccvm','value'),oils_i18n_gettext('1769','Closed captions','ccvm','search_label')),
 (1770,true,'a11yTextFeatures','describedMath',oils_i18n_gettext('1770','describedMath','ccvm','value'),oils_i18n_gettext('1770','Described math','ccvm','search_label')),
 (1771,true,'a11yTextFeatures','longDescription',oils_i18n_gettext('1771','longDescription','ccvm','value'),oils_i18n_gettext('1771','Long description','ccvm','search_label')),
 (1772,true,'a11yTextFeatures','openCaptions',oils_i18n_gettext('1772','openCaptions','ccvm','value'),oils_i18n_gettext('1772','Open captions','ccvm','search_label')),
 (1773,true,'a11yTextFeatures','transcript',oils_i18n_gettext('1773','transcript','ccvm','value'),oils_i18n_gettext('1773','transcript','ccvm','search_label')),
 (1774,true,'a11yTextFeatures','displayTransformability',oils_i18n_gettext('1774','displayTransformability','ccvm','value'),oils_i18n_gettext('1774','Display transformability','ccvm','search_label')),
 (1775,true,'a11yTextFeatures','ChemML',oils_i18n_gettext('1775','ChemML','ccvm','value'),oils_i18n_gettext('1775','ChemML','ccvm','search_label')),
 (1776,true,'a11yTextFeatures','latex',oils_i18n_gettext('1776','latex','ccvm','value'),oils_i18n_gettext('1776','LaTeX','ccvm','search_label')),
 (1777,false,'a11yTextFeatures','latex-chemistry',oils_i18n_gettext('1777','latex-chemistry','ccvm','value'),oils_i18n_gettext('1777','LaTeX-chemistry','ccvm','search_label')),
 (1778,true,'a11yTextFeatures','MathML',oils_i18n_gettext('1778','MathML','ccvm','value'),oils_i18n_gettext('1778','MathML','ccvm','search_label')),
 (1779,false,'a11yTextFeatures','MathML-chemistry',oils_i18n_gettext('1779','MathML-chemistry','ccvm','value'),oils_i18n_gettext('1779','MathML-chemistry','ccvm','search_label')),
 (1780,true,'a11yTextFeatures','ttsMarkup',oils_i18n_gettext('1780','ttsMarkup','ccvm','value'),oils_i18n_gettext('1780','TTS markup','ccvm','search_label')),
 (1781,true,'a11yTextFeatures','largePrint',oils_i18n_gettext('1781','largePrint','ccvm','value'),oils_i18n_gettext('1781','Large print','ccvm','search_label')),
 (1782,false,'a11yTextFeatures','horizontalWriting',oils_i18n_gettext('1782','horizontalWriting','ccvm','value'),oils_i18n_gettext('1782','Horizontal writing','ccvm','search_label')),
 (1783,false,'a11yTextFeatures','verticalWriting',oils_i18n_gettext('1783','verticalWriting','ccvm','value'),oils_i18n_gettext('1783','VerticalWriting','ccvm','search_label')),
 (1784,false,'a11yTextFeatures','withAdditionalWordSegmentation',oils_i18n_gettext('1784','withAdditionalWordSegmentation','ccvm','value'),oils_i18n_gettext('1784','With additional word segmentation','ccvm','search_label')),
 (1785,false,'a11yTextFeatures','withoutAdditionalWordSegmentation',oils_i18n_gettext('1785','withoutAdditionalWordSegmentation','ccvm','value'),oils_i18n_gettext('1785','Without additional word segmentation','ccvm','search_label')),
 (1786,true,'a11yVisualFeatures','highContrastDisplay',oils_i18n_gettext('1786','highContrastDisplay','ccvm','value'),oils_i18n_gettext('1786','High contrast display','ccvm','search_label')),
 (1787,true,'a11yVisualFeatures','signLanguage',oils_i18n_gettext('1787','signLanguage','ccvm','value'),oils_i18n_gettext('1787','Sign language','ccvm','search_label')),
 (1788,true,'a11yAuditoryFeatures','audioDescription',oils_i18n_gettext('1788','audioDescription','ccvm','value'),oils_i18n_gettext('1788','Audio description','ccvm','search_label')),
 (1789,true,'a11yAuditoryFeatures','highContrastAudio',oils_i18n_gettext('1789','highContrastAudio','ccvm','value'),oils_i18n_gettext('1789','High contrast audio','ccvm','search_label')),
 (1790,true,'a11yAuditoryFeatures','timingControl',oils_i18n_gettext('1790','timingControl','ccvm','value'),oils_i18n_gettext('1790','Timing control','ccvm','search_label')),
 (1791,true,'a11yAuditoryFeatures','synchronizedAudioText',oils_i18n_gettext('1791','synchronizedAudioText','ccvm','value'),oils_i18n_gettext('1791','Synchronized audio text','ccvm','search_label')),
 (1792,true,'a11yTactileFeatures','braille',oils_i18n_gettext('1792','braille','ccvm','value'),oils_i18n_gettext('1792','Braille','ccvm','search_label')),
 (1793,false,'a11yTactileFeatures','tactileGraphic',oils_i18n_gettext('1793','tactileGraphic','ccvm','value'),oils_i18n_gettext('1793','Tactile graphic','ccvm','search_label')),
 (1794,false,'a11yTactileFeatures','tactileObject',oils_i18n_gettext('1794','tactileObject','ccvm','value'),oils_i18n_gettext('1794','Tactile object','ccvm','search_label'))
;

-- The above is autogenerated from LoC data; because we use metabib.full_rec to look up the
-- in-record value, we have to make our CCVM value lowercase, as that's how MFR stores the data.
UPDATE config.coded_value_map SET code = LOWER(code) WHERE code <> LOWER(code) AND ctype LIKE 'a11y%';


SELECT evergreen.upgrade_deps_block_check('1501', :eg_version);

ALTER FUNCTION permission.usr_has_home_perm STABLE;
ALTER FUNCTION permission.usr_has_work_perm STABLE;
ALTER FUNCTION permission.usr_has_object_perm ( INT, TEXT, TEXT, TEXT ) STABLE;
ALTER FUNCTION permission.usr_has_perm STABLE;
ALTER FUNCTION permission.usr_has_perm_at_nd STABLE;
ALTER FUNCTION permission.usr_has_perm_at_all_nd STABLE;
ALTER FUNCTION permission.usr_has_perm_at STABLE;
ALTER FUNCTION permission.usr_has_perm_at_all STABLE;

CREATE OR REPLACE FUNCTION permission.usr_has_object_perm ( iuser INT, tperm TEXT, obj_type TEXT, obj_id TEXT, target_ou INT ) RETURNS BOOL AS $$
DECLARE
    r_usr   actor.usr%ROWTYPE;
    r_perm  permission.perm_list%ROWTYPE;
    res     BOOL;
BEGIN

    SELECT * INTO r_usr FROM actor.usr WHERE id = iuser;
    SELECT * INTO r_perm FROM permission.perm_list WHERE code = tperm;

    IF r_usr.active = FALSE THEN
        RETURN FALSE;
    END IF;

    IF r_usr.super_user = TRUE THEN
        RETURN TRUE;
    END IF;

    SELECT TRUE INTO res FROM permission.usr_object_perm_map WHERE perm = r_perm.id AND usr = r_usr.id AND object_type = obj_type AND object_id = obj_id;

    IF FOUND THEN
        RETURN TRUE;
    END IF;

    IF target_ou > -1 THEN
        RETURN permission.usr_has_perm( iuser, tperm, target_ou);
    END IF;

    RETURN FALSE;

END;
$$ LANGUAGE PLPGSQL STABLE;

-- Start trimming back RULEs, they're starting to make things too hard.  Trigger time!
CREATE OR REPLACE FUNCTION evergreen.raise_protected_row_exception() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Cannot % %.% with % of %', TG_OP, TG_TABLE_SCHEMA, TG_TABLE_NAME, COALESCE(TG_ARGV[0]::TEXT,'id'), COALESCE(TG_ARGV[1]::TEXT,'-1');
END;
$$ LANGUAGE plpgsql;

DROP RULE IF EXISTS protect_bre_id_neg1 ON biblio.record_entry;
CREATE TRIGGER protect_bre_id_neg1
  BEFORE UPDATE ON biblio.record_entry
  FOR EACH ROW WHEN (NEW.deleted = TRUE AND OLD.deleted = FALSE AND OLD.id = -1)
  EXECUTE PROCEDURE evergreen.raise_protected_row_exception();

DROP RULE IF EXISTS protect_acn_id_neg1 ON asset.call_number;
CREATE TRIGGER protect_acn_id_neg1
  BEFORE UPDATE ON asset.call_number
  FOR EACH ROW WHEN (OLD.id = -1)
  EXECUTE PROCEDURE evergreen.raise_protected_row_exception();

-- Open-ILS/src/sql/Pg/005.schema.actors.sql
CREATE OR REPLACE RULE protect_user_delete AS ON DELETE TO actor.usr DO INSTEAD UPDATE actor.usr SET deleted = TRUE WHERE OLD.id = actor.usr.id RETURNING *;
CREATE OR REPLACE RULE protect_usr_message_delete AS ON DELETE TO actor.usr_message DO INSTEAD UPDATE actor.usr_message SET deleted = TRUE WHERE OLD.id = actor.usr_message.id RETURNING *;

-- Open-ILS/src/sql/Pg/011.schema.authority.sql
CREATE OR REPLACE RULE protect_authority_rec_delete AS ON DELETE TO authority.record_entry DO INSTEAD (UPDATE authority.record_entry SET deleted = TRUE WHERE OLD.id = authority.record_entry.id RETURNING *; DELETE FROM authority.full_rec WHERE record = OLD.id);

-- Open-ILS/src/sql/Pg/040.schema.asset.sql
CREATE OR REPLACE RULE protect_copy_delete AS ON DELETE TO asset.copy DO INSTEAD UPDATE asset.copy SET deleted = TRUE WHERE OLD.id = asset.copy.id RETURNING *;
CREATE OR REPLACE RULE protect_cn_delete AS ON DELETE TO asset.call_number DO INSTEAD UPDATE asset.call_number SET deleted = TRUE WHERE OLD.id = asset.call_number.id RETURNING *;

-- Open-ILS/src/sql/Pg/210.schema.serials.sql
CREATE OR REPLACE RULE protect_mfhd_delete AS ON DELETE TO serial.record_entry DO INSTEAD UPDATE serial.record_entry SET deleted = true WHERE old.id = serial.record_entry.id RETURNING *;
CREATE OR REPLACE RULE protect_serial_unit_delete AS ON DELETE TO serial.unit DO INSTEAD UPDATE serial.unit SET deleted = TRUE WHERE OLD.id = serial.unit.id RETURNING *;

-- Open-ILS/src/sql/Pg/800.fkeys.sql
CREATE OR REPLACE RULE protect_bib_rec_delete AS ON DELETE TO biblio.record_entry DO INSTEAD UPDATE biblio.record_entry SET deleted = TRUE WHERE OLD.id = biblio.record_entry.id RETURNING *;
CREATE OR REPLACE RULE protect_mono_part_delete AS ON DELETE TO biblio.monograph_part DO INSTEAD (UPDATE biblio.monograph_part SET deleted = TRUE WHERE OLD.id = biblio.monograph_part.id RETURNING *; DELETE FROM asset.copy_part_map WHERE part = OLD.id);
CREATE OR REPLACE RULE protect_cn_delete AS ON DELETE TO asset.call_number DO INSTEAD UPDATE asset.call_number SET deleted = TRUE WHERE OLD.id = asset.call_number.id RETURNING *;
CREATE OR REPLACE RULE protect_copy_location_delete AS
    ON DELETE TO asset.copy_location DO INSTEAD (
        SELECT asset.check_delete_copy_location(OLD.id); -- exception on error
        UPDATE asset.copy_location SET deleted = TRUE WHERE OLD.id = asset.copy_location.id RETURNING *;
        UPDATE acq.lineitem_detail SET location = NULL WHERE location = OLD.id;
        DELETE FROM asset.copy_location_order WHERE location = OLD.id;
        DELETE FROM asset.copy_location_group_map WHERE location = OLD.id;
        DELETE FROM config.circ_limit_set_copy_loc_map WHERE copy_loc = OLD.id;
    );

SELECT evergreen.upgrade_deps_block_check('1502', :eg_version);

CREATE INDEX IF NOT EXISTS cbreb_pub_owner_not_temp_idx ON container.biblio_record_entry_bucket (pub,owner) WHERE btype != 'temp';

COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
