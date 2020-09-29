--Upgrade Script for 3.5.1 to 3.6-beta1
\set eg_version '''3.6-beta1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.6-beta1', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1205', :eg_version);

INSERT INTO config.print_template 
    (id, name, locale, active, owner, label, template) 
VALUES (
    3, 'booking_capture', 'en-US', TRUE,
    (SELECT id FROM actor.org_unit WHERE parent_ou IS NULL),
    oils_i18n_gettext(3, 'Booking capture slip', 'cpt', 'label'),
$TEMPLATE$
[%-
    USE date;
    SET data = template_data;
    # template_data is data returned from open-ils.booking.resources.capture_for_reservation.
-%]
<div>
  [% IF data.transit;
       dest_ou = helpers.get_org_unit(data.transit.dest);
  %]
  <div>This item need to be routed to <strong>[% dest_ou.shortname %]</strong></div>
  [% ELSE %]
  <div>This item need to be routed to <strong>RESERVATION SHELF:</strong></div>
  [% END %]
  <div>Barcode: [% data.reservation.current_resource.barcode %]</div>
  <div>Title: [% data.reservation.current_resource.type.name %]</div>
  <div>Note: [% data.reservation.note %]</div>
  <br/>
  <p><strong>Reserved for patron</strong> [% data.reservation.usr.family_name %], [% data.reservation.usr.first_given_name %] [% data.reservation.usr.second_given_name %]
  <br/>Barcode: [% data.reservation.usr.card.barcode %]</p>
  <p>Request time: [% date.format(helpers.format_date(data.reservation.request_time, client_timezone), '%x %r', locale) %]
  <br/>Reserved from:
    [% date.format(helpers.format_date(data.reservation.start_time, client_timezone), '%x %r', locale) %]
    - [% date.format(helpers.format_date(data.reservation.end_time, client_timezone), '%x %r', locale) %]</p>
  <p>Slip date: [% date.format(helpers.current_date(client_timezone), '%x %r', locale) %]<br/>
  Printed by [% data.staff.family_name %], [% data.staff.first_given_name %] [% data.staff.second_given_name %]
    at [% data.workstation %]</p>
</div>
<br/>

$TEMPLATE$
);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.booking.captured', 'gui', 'object',
    oils_i18n_gettext(
        'booking.manage',
        'Grid Config: Booking Captured Reservations',
        'cwst', 'label')
);



SELECT evergreen.upgrade_deps_block_check('1210', :eg_version); -- csharp/rhamby/sandbergja/gmcharlt

ALTER TABLE action.in_house_use ADD COLUMN workstation INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE action.non_cat_in_house_use ADD COLUMN workstation INT REFERENCES actor.workstation (id) DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX action_in_house_use_ws_idx ON action.in_house_use ( workstation );
CREATE INDEX non_cat_in_house_use_ws_idx ON action.non_cat_in_house_use ( workstation );



SELECT evergreen.upgrade_deps_block_check('1212', :eg_version); -- berick/sandbergja/gmcharlt

DELETE FROM actor.org_unit_setting
    WHERE name = 'ui.staff.angular_catalog.enabled';

DELETE FROM config.org_unit_setting_type_log 
    WHERE field_name = 'ui.staff.angular_catalog.enabled';

DELETE FROM config.org_unit_setting_type
    WHERE name = 'ui.staff.angular_catalog.enabled';

-- activate the stock hold-for-bib server print template
UPDATE config.print_template SET active = TRUE WHERE name = 'holds_for_bib';


SELECT evergreen.upgrade_deps_block_check('1213', :eg_version);

CREATE OR REPLACE FUNCTION actor.change_password (user_id INT, new_pw TEXT, pw_type TEXT DEFAULT 'main')
RETURNS VOID AS $$
DECLARE
    new_salt TEXT;
BEGIN
    SELECT actor.create_salt(pw_type) INTO new_salt;

    IF pw_type = 'main' THEN
        -- Only 'main' passwords are required to have
        -- the extra layer of MD5 hashing.
        PERFORM actor.set_passwd(
            user_id, pw_type, md5(new_salt || md5(new_pw)), new_salt
        );

    ELSE
        PERFORM actor.set_passwd(user_id, pw_type, new_pw, new_salt);
    END IF;
END;
$$ LANGUAGE 'plpgsql';

COMMENT ON FUNCTION actor.change_password(INT,TEXT,TEXT) IS $$
Allows setting a salted password for a user by passing actor.usr id and the text of the password.
$$;


SELECT evergreen.upgrade_deps_block_check('1214', :eg_version);

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
	SELECT	INTO metarec *
	  FROM	metabib.metarecord
	  WHERE	master_record = source_record;

	IF FOUND THEN
		UPDATE	metabib.metarecord
		  SET	master_record = target_record,
			mods = NULL
		  WHERE	id = metarec.id;

		moved_objects := moved_objects + 1;
	END IF;

	-- Find call numbers attached to the source ...
	FOR source_cn IN SELECT * FROM asset.call_number WHERE record = source_record LOOP

		SELECT	INTO target_cn *
		  FROM	asset.call_number
		  WHERE	label = source_cn.label
            AND prefix = source_cn.prefix
            AND suffix = source_cn.suffix
			AND owning_lib = source_cn.owning_lib
			AND record = target_record
			AND NOT deleted;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copies to that, and ...
			UPDATE	asset.copy
			  SET	call_number = target_cn.id
			  WHERE	call_number = source_cn.id;

			-- ... move V holds to the move-target call number
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_cn.id AND hold_type = 'V' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_cn.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;
        
            UPDATE asset.call_number SET deleted = TRUE WHERE id = source_cn.id;

		-- ... if not ...
		ELSE
			-- ... just move the call number to the target record
			UPDATE	asset.call_number
			  SET	record = target_record
			  WHERE	id = source_cn.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find T holds targeting the source record ...
	FOR hold IN SELECT * FROM action.hold_request WHERE target = source_record AND hold_type = 'T' LOOP

		-- ... and move them to the target record
		UPDATE	action.hold_request
		  SET	target = target_record
		  WHERE	id = hold.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial records targeting the source record ...
	FOR ser_rec IN SELECT * FROM serial.record_entry WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.record_entry
		  SET	record = target_record
		  WHERE	id = ser_rec.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find serial subscriptions targeting the source record ...
	FOR ser_sub IN SELECT * FROM serial.subscription WHERE record_entry = source_record LOOP
		-- ... and move them to the target record
		UPDATE	serial.subscription
		  SET	record_entry = target_record
		  WHERE	id = ser_sub.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find booking resource types targeting the source record ...
	FOR booking IN SELECT * FROM booking.resource_type WHERE record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	booking.resource_type
		  SET	record = target_record
		  WHERE	id = booking.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq lineitems targeting the source record ...
	FOR acq_lineitem IN SELECT * FROM acq.lineitem WHERE eg_bib_id = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.lineitem
		  SET	eg_bib_id = target_record
		  WHERE	id = acq_lineitem.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find acq user purchase requests targeting the source record ...
	FOR acq_request IN SELECT * FROM acq.user_request WHERE eg_bib = source_record LOOP
		-- ... and move them to the target record
		UPDATE	acq.user_request
		  SET	eg_bib = target_record
		  WHERE	id = acq_request.id;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find parts attached to the source ...
	FOR source_part IN SELECT * FROM biblio.monograph_part WHERE record = source_record LOOP

		SELECT	INTO target_part *
		  FROM	biblio.monograph_part
		  WHERE	label = source_part.label
			AND record = target_record;

		-- ... and if there's a conflicting one on the target ...
		IF FOUND THEN

			-- ... move the copy-part maps to that, and ...
			UPDATE	asset.copy_part_map
			  SET	part = target_part.id
			  WHERE	part = source_part.id;

			-- ... move P holds to the move-target part
			FOR hold IN SELECT * FROM action.hold_request WHERE target = source_part.id AND hold_type = 'P' LOOP
		
				UPDATE	action.hold_request
				  SET	target = target_part.id
				  WHERE	id = hold.id;
		
				moved_objects := moved_objects + 1;
			END LOOP;

		-- ... if not ...
		ELSE
			-- ... just move the part to the target record
			UPDATE	biblio.monograph_part
			  SET	record = target_record
			  WHERE	id = source_part.id;
		END IF;

		moved_objects := moved_objects + 1;
	END LOOP;

	-- Find multi_home items attached to the source ...
	FOR multi_home IN SELECT * FROM biblio.peer_bib_copy_map WHERE peer_record = source_record LOOP
		-- ... and move them to the target record
		UPDATE	biblio.peer_bib_copy_map
		  SET	peer_record = target_record
		  WHERE	id = multi_home.id;

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


SELECT evergreen.upgrade_deps_block_check('1215', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.orgselect.cat.catalog.wide_holds', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.orgselect.cat.catalog.wide_holds',
        'Default org unit for catalog holds org unit selector',
        'cwst', 'label'
    )
);




SELECT evergreen.upgrade_deps_block_check('1216', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.orgselect.patron.search', 'gui', 'integer',
    oils_i18n_gettext(
        'eg.orgselect.patron.search',
        'Default org unit for patron search',
        'cwst', 'label'
    )
);




SELECT evergreen.upgrade_deps_block_check('1217', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.acq.search.default.lineitems', 'gui', 'object',
    oils_i18n_gettext(
    'eg.acq.search.default.lineitems',
    'Acquisitions Default Search: Lineitems',
    'cwst', 'label')
), (
    'eg.acq.search.default.purchaseorders', 'gui', 'object',
    oils_i18n_gettext(
    'eg.acq.search.default.purchaseorders',
    'Acquisitions Default Search: Purchase Orders',
    'cwst', 'label')
), (
    'eg.acq.search.default.invoices', 'gui', 'object',
    oils_i18n_gettext(
    'eg.acq.search.default.invoices',
    'Acquisitions Default Search: Invoices',
    'cwst', 'label')
), (
    'eg.acq.search.default.selectionlists', 'gui', 'object',
    oils_i18n_gettext(
    'eg.acq.search.default.selectionlists',
    'Acquisitions Default Search: Selection Lists',
    'cwst', 'label')
);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.acq.search.lineitems.run_immediately', 'gui', 'bool',
    oils_i18n_gettext(
    'eg.acq.search.lineitems.run_immediately',
    'Acquisitions Search: Immediately Search Lineitems',
    'cwst', 'label')
), (
    'eg.acq.search.purchaseorders.run_immediately', 'gui', 'bool',
    oils_i18n_gettext(
    'eg.acq.search.purchaseorders.run_immediately',
    'Acquisitions Search: Immediately Search Purchase Orders',
    'cwst', 'label')
), (
    'eg.acq.search.invoices.run_immediately', 'gui', 'bool',
    oils_i18n_gettext(
    'eg.acq.search.invoices.run_immediately',
    'Acquisitions Search: Immediately Search Invoices',
    'cwst', 'label')
), (
    'eg.acq.search.selectionlists.run_immediately', 'gui', 'bool',
    oils_i18n_gettext(
    'eg.acq.search.selectionlists.run_immediately',
    'Acquisitions Search: Immediately Search Selection Lists',
    'cwst', 'label')
);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.acq.search.lineitems', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.search.lineitems',
    'Grid Config: acq.search.lineitems',
    'cwst', 'label')
), (
    'eg.grid.acq.search.purchaseorders', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.search.purchaseorders',
    'Grid Config: acq.search.purchaseorders',
    'cwst', 'label')
), (
    'eg.grid.acq.search.selectionlists', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.search.selectionlists',
    'Grid Config: acq.search.selectionlists',
    'cwst', 'label')
), (
    'eg.grid.acq.search.invoices', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.search.invoices',
    'Grid Config: acq.search.invoices',
    'cwst', 'label')
);


SELECT evergreen.upgrade_deps_block_check('1218', :eg_version);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
        SELECT
                pgt.id, perm.id, aout.depth, TRUE
        FROM
                permission.grp_tree pgt,
                permission.perm_list perm,
                actor.org_unit_type aout
        WHERE
                pgt.name = 'Acquisitions Administrator' AND
                aout.name = 'Consortium' AND
                perm.code IN (
                    'VIEW_FUND',
                    'VIEW_FUNDING_SOURCE',
                    'VIEW_FUND_ALLOCATION',
                    'VIEW_PICKLIST',
                    'VIEW_PROVIDER',
                    'VIEW_PURCHASE_ORDER',
                    'VIEW_INVOICE',
                    'CREATE_PICKLIST',
                    'ACQ_ADD_LINEITEM_IDENTIFIER',
                    'ACQ_SET_LINEITEM_IDENTIFIER',
                    'MANAGE_FUND',
                    'CREATE_INVOICE',
                    'CREATE_PURCHASE_ORDER',
                    'IMPORT_ACQ_LINEITEM_BIB_RECORD',
                    'IMPORT_ACQ_LINEITEM_BIB_RECORD_UPLOAD',
                    'MANAGE_CLAIM',
                    'MANAGE_PROVIDER',
                    'MANAGE_FUNDING_SOURCE',
                    'RECEIVE_PURCHASE_ORDER',
                    'ADMIN_ACQ_LINEITEM_ALERT_TEXT',
                    'UPDATE_FUNDING_SOURCE',
                    'UPDATE_PROVIDER',
                    'VIEW_IMPORT_MATCH_SET',
                    'VIEW_MERGE_PROFILE',
                    'IMPORT_MARC'
                );


INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
        SELECT
                pgt.id, perm.id, aout.depth, FALSE
        FROM
                permission.grp_tree pgt,
                permission.perm_list perm,
                actor.org_unit_type aout
        WHERE
                pgt.name = 'Acquisitions' AND
                aout.name = 'Consortium' AND
                perm.code IN (
                    'ACQ_ADD_LINEITEM_IDENTIFIER',
                    'ACQ_SET_LINEITEM_IDENTIFIER',
                    'ADMIN_ACQ_FUND',
                    'ADMIN_FUND',
                    'ACQ_INVOICE-REOPEN',
                    'ADMIN_ACQ_DISTRIB_FORMULA',
                    'ADMIN_INVOICE',
                    'IMPORT_ACQ_LINEITEM_BIB_RECORD_UPLOAD',
                    'VIEW_IMPORT_MATCH_SET',
                    'VIEW_MERGE_PROFILE'
                );


SELECT evergreen.upgrade_deps_block_check('1219', :eg_version);

CREATE VIEW acq.li_state_label AS
  SELECT *
  FROM (VALUES
          ('new', 'New'),
          ('selector-ready', 'Selector-Ready'),
          ('order-ready', 'Order-Ready'),
          ('approved', 'Approved'),
          ('pending-order', 'Pending-Order'),
          ('on-order', 'On-Order'),
          ('received', 'Received'),
          ('cancelled', 'Cancelled')
       ) AS t (id,label);

CREATE VIEW acq.po_state_label AS
  SELECT *
  FROM (VALUES
          ('new', 'New'),
          ('pending', 'Pending'), 
          ('on-order', 'On-Order'),
          ('received', 'Received'),
          ('cancelled', 'Cancelled')
       ) AS t (id,label);


SELECT evergreen.upgrade_deps_block_check('1220', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'circ.holds.calculated_age_proximity', 'circ',
    oils_i18n_gettext('circ.holds.calculated_age_proximity',
        'Use calculated proximity for age-protection check',
        'coust', 'label'),
    oils_i18n_gettext('circ.holds.calculated_age_proximity',
        'When checking whether a copy is viable for a hold based on transit distance, use calculated proximity with adjustments rather than baseline Org Unit proximity.',
        'coust', 'description'),
    'bool', null);



SELECT evergreen.upgrade_deps_block_check('1221', :eg_version);

CREATE OR REPLACE FUNCTION action.copy_calculated_proximity(
    pickup  INT,
    request INT,
    vacp_cl  INT,
    vacp_cm  TEXT,
    vacn_ol  INT,
    vacl_ol  INT
) RETURNS NUMERIC AS $f$
DECLARE
    baseline_prox   NUMERIC;
    aoupa           actor.org_unit_proximity_adjustment%ROWTYPE;
BEGIN

    -- First, gather the baseline proximity of "here" to pickup lib
    SELECT prox INTO baseline_prox FROM actor.org_unit_proximity WHERE from_org = vacp_cl AND to_org = pickup;

    -- Find any absolute adjustments, and set the baseline prox to that
    SELECT  adj.* INTO aoupa
      FROM  actor.org_unit_proximity_adjustment adj
            LEFT JOIN actor.org_unit_ancestors_distance(vacp_cl) acp_cl ON (acp_cl.id = adj.item_circ_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(vacn_ol) acn_ol ON (acn_ol.id = adj.item_owning_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(vacl_ol) acl_ol ON (acl_ol.id = adj.copy_location)
            LEFT JOIN actor.org_unit_ancestors_distance(pickup) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(request) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
      WHERE (adj.circ_mod IS NULL OR adj.circ_mod = vacp_cm) AND
            (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
            (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
            (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
            (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
            (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
            absolute_adjustment AND
            COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
      ORDER BY
            COALESCE(acp_cl.distance,999)
                + COALESCE(acn_ol.distance,999)
                + COALESCE(acl_ol.distance,999)
                + COALESCE(ahr_pl.distance,999)
                + COALESCE(ahr_rl.distance,999),
            adj.pos
      LIMIT 1;

    IF FOUND THEN
        baseline_prox := aoupa.prox_adjustment;
    END IF;

    -- Now find any relative adjustments, and change the baseline prox based on them
    FOR aoupa IN
        SELECT  adj.*
          FROM  actor.org_unit_proximity_adjustment adj
                LEFT JOIN actor.org_unit_ancestors_distance(vacp_cl) acp_cl ON (acp_cl.id = adj.item_circ_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(vacn_ol) acn_ol ON (acn_ol.id = adj.item_owning_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(vacl_ol) acl_ol ON (acn_ol.id = adj.copy_location)
                LEFT JOIN actor.org_unit_ancestors_distance(pickup) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(request) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
          WHERE (adj.circ_mod IS NULL OR adj.circ_mod = vacp_cm) AND
                (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
                (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
                (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
                (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
                (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
                NOT absolute_adjustment AND
                COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
    LOOP
        baseline_prox := baseline_prox + aoupa.prox_adjustment;
    END LOOP;

    RETURN baseline_prox;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.hold_copy_calculated_proximity(
    ahr_id INT,
    acp_id BIGINT,
    copy_context_ou INT DEFAULT NULL
    -- TODO maybe? hold_context_ou INT DEFAULT NULL.  This would optionally
    -- support an "ahprox" measurement: adjust prox between copy circ lib and
    -- hold request lib, but I'm unsure whether to use this theoretical
    -- argument only in the baseline calculation or later in the other
    -- queries in this function.
) RETURNS NUMERIC AS $f$
DECLARE
    ahr  action.hold_request%ROWTYPE;
    acp  asset.copy%ROWTYPE;
    acn  asset.call_number%ROWTYPE;
    acl  asset.copy_location%ROWTYPE;

    prox NUMERIC;
BEGIN

    SELECT * INTO ahr FROM action.hold_request WHERE id = ahr_id;
    SELECT * INTO acp FROM asset.copy WHERE id = acp_id;
    SELECT * INTO acn FROM asset.call_number WHERE id = acp.call_number;
    SELECT * INTO acl FROM asset.copy_location WHERE id = acp.location;

    IF copy_context_ou IS NULL THEN
        copy_context_ou := acp.circ_lib;
    END IF;

    SELECT action.copy_calculated_proximity(
        ahr.pickup_lib,
        ahr.request_lib,
        copy_context_ou,
        acp.circ_modifier,
        acn.owning_lib,
        acl.owning_lib
    ) INTO prox;

    RETURN prox;
END;
$f$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION action.hold_request_permit_test( pickup_ou INT, request_ou INT, match_item BIGINT, match_user INT, match_requestor INT, retargetting BOOL ) RETURNS SETOF action.matrix_test_result AS $func$
DECLARE
    matchpoint_id        INT;
    user_object        actor.usr%ROWTYPE;
    age_protect_object    config.rule_age_hold_protect%ROWTYPE;
    standing_penalty    config.standing_penalty%ROWTYPE;
    transit_range_ou_type    actor.org_unit_type%ROWTYPE;
    transit_source        actor.org_unit%ROWTYPE;
    item_object        asset.copy%ROWTYPE;
    item_cn_object     asset.call_number%ROWTYPE;
    item_status_object  config.copy_status%ROWTYPE;
    item_location_object    asset.copy_location%ROWTYPE;
    ou_skip              actor.org_unit_setting%ROWTYPE;
    calc_age_prox        actor.org_unit_setting%ROWTYPE;
    result            action.matrix_test_result;
    hold_test        config.hold_matrix_matchpoint%ROWTYPE;
    use_active_date   TEXT;
    prox_ou           INT;
    age_protect_date  TIMESTAMP WITH TIME ZONE;
    hold_count        INT;
    hold_transit_prox    NUMERIC;
    frozen_hold_count    INT;
    context_org_list    INT[];
    done            BOOL := FALSE;
    hold_penalty TEXT;
    v_pickup_ou ALIAS FOR pickup_ou;
    v_request_ou ALIAS FOR request_ou;
    item_prox INT;
    pickup_prox INT;
BEGIN
    SELECT INTO user_object * FROM actor.usr WHERE id = match_user;
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( v_pickup_ou );

    result.success := TRUE;

    -- The HOLD penalty block only applies to new holds.
    -- The CAPTURE penalty block applies to existing holds.
    hold_penalty := 'HOLD';
    IF retargetting THEN
        hold_penalty := 'CAPTURE';
    END IF;

    -- Fail if we couldn't find a user
    IF user_object.id IS NULL THEN
        result.fail_part := 'no_user';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_object * FROM asset.copy WHERE id = match_item;

    -- Fail if we couldn't find a copy
    IF item_object.id IS NULL THEN
        result.fail_part := 'no_item';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO matchpoint_id action.find_hold_matrix_matchpoint(v_pickup_ou, v_request_ou, match_item, match_user, match_requestor);
    result.matchpoint := matchpoint_id;

    SELECT INTO ou_skip * FROM actor.org_unit_setting WHERE name = 'circ.holds.target_skip_me' AND org_unit = item_object.circ_lib;

    -- Fail if the circ_lib for the item has circ.holds.target_skip_me set to true
    IF ou_skip.id IS NOT NULL AND ou_skip.value = 'true' THEN
        result.fail_part := 'circ.holds.target_skip_me';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    -- Fail if user is barred
    IF user_object.barred IS TRUE THEN
        result.fail_part := 'actor.usr.barred';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO item_cn_object * FROM asset.call_number WHERE id = item_object.call_number;
    SELECT INTO item_status_object * FROM config.copy_status WHERE id = item_object.status;
    SELECT INTO item_location_object * FROM asset.copy_location WHERE id = item_object.location;

    -- Fail if we couldn't find any matchpoint (requires a default)
    IF matchpoint_id IS NULL THEN
        result.fail_part := 'no_matchpoint';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
        RETURN;
    END IF;

    SELECT INTO hold_test * FROM config.hold_matrix_matchpoint WHERE id = matchpoint_id;

    IF hold_test.holdable IS FALSE THEN
        result.fail_part := 'config.hold_matrix_test.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_object.holdable IS FALSE THEN
        result.fail_part := 'item.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_status_object.holdable IS FALSE THEN
        result.fail_part := 'status.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF item_location_object.holdable IS FALSE THEN
        result.fail_part := 'location.holdable';
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END IF;

    IF hold_test.transit_range IS NOT NULL THEN
        SELECT INTO transit_range_ou_type * FROM actor.org_unit_type WHERE id = hold_test.transit_range;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO transit_source ou.* FROM actor.org_unit ou JOIN asset.call_number cn ON (cn.owning_lib = ou.id) WHERE cn.id = item_object.call_number;
        ELSE
            SELECT INTO transit_source * FROM actor.org_unit WHERE id = item_object.circ_lib;
        END IF;

        PERFORM * FROM actor.org_unit_descendants( transit_source.id, transit_range_ou_type.depth ) WHERE id = v_pickup_ou;

        IF NOT FOUND THEN
            result.fail_part := 'transit_range';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    -- Proximity of user's home_ou to the pickup_lib to see if penalty should be ignored.
    SELECT INTO pickup_prox prox FROM actor.org_unit_proximity WHERE from_org = user_object.home_ou AND to_org = v_pickup_ou;
    -- Proximity of user's home_ou to the items' lib to see if penalty should be ignored.
    IF hold_test.distance_is_from_owner THEN
        SELECT INTO item_prox prox FROM actor.org_unit_proximity WHERE from_org = user_object.home_ou AND to_org = item_cn_object.owning_lib;
    ELSE
        SELECT INTO item_prox prox FROM actor.org_unit_proximity WHERE from_org = user_object.home_ou AND to_org = item_object.circ_lib;
    END IF;

    FOR standing_penalty IN
        SELECT  DISTINCT csp.*
          FROM  actor.usr_standing_penalty usp
                JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
          WHERE usr = match_user
                AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                AND (csp.ignore_proximity IS NULL OR csp.ignore_proximity < item_prox
                     OR csp.ignore_proximity < pickup_prox)
                AND csp.block_list LIKE '%' || hold_penalty || '%' LOOP

        result.fail_part := standing_penalty.name;
        result.success := FALSE;
        done := TRUE;
        RETURN NEXT result;
    END LOOP;

    IF hold_test.stop_blocked_user IS TRUE THEN
        FOR standing_penalty IN
            SELECT  DISTINCT csp.*
              FROM  actor.usr_standing_penalty usp
                    JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
              WHERE usr = match_user
                    AND usp.org_unit IN ( SELECT * FROM unnest(context_org_list) )
                    AND (usp.stop_date IS NULL or usp.stop_date > NOW())
                    AND csp.block_list LIKE '%CIRC%' LOOP

            result.fail_part := standing_penalty.name;
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END LOOP;
    END IF;

    IF hold_test.max_holds IS NOT NULL AND NOT retargetting THEN
        SELECT    INTO hold_count COUNT(*)
          FROM    action.hold_request
          WHERE    usr = match_user
            AND fulfillment_time IS NULL
            AND cancel_time IS NULL
            AND CASE WHEN hold_test.include_frozen_holds THEN TRUE ELSE frozen IS FALSE END;

        IF hold_count >= hold_test.max_holds THEN
            result.fail_part := 'config.hold_matrix_test.max_holds';
            result.success := FALSE;
            done := TRUE;
            RETURN NEXT result;
        END IF;
    END IF;

    IF item_object.age_protect IS NOT NULL THEN
        SELECT INTO age_protect_object * FROM config.rule_age_hold_protect WHERE id = item_object.age_protect;
        IF hold_test.distance_is_from_owner THEN
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_cn_object.owning_lib);
        ELSE
            SELECT INTO use_active_date value FROM actor.org_unit_ancestor_setting('circ.holds.age_protect.active_date', item_object.circ_lib);
        END IF;
        IF use_active_date = 'true' THEN
            age_protect_date := COALESCE(item_object.active_date, NOW());
        ELSE
            age_protect_date := item_object.create_date;
        END IF;
        IF age_protect_date + age_protect_object.age > NOW() THEN
            SELECT INTO calc_age_prox * FROM actor.org_unit_setting WHERE name = 'circ.holds.calculated_age_proximity' AND org_unit = item_object.circ_lib;
            IF hold_test.distance_is_from_owner THEN
                prox_ou := item_cn_object.owning_lib;
            ELSE
                prox_ou := item_object.circ_lib;
            END IF;
            IF calc_age_prox.id IS NOT NULL AND calc_age_prox.value = 'true' THEN
                SELECT INTO hold_transit_prox action.copy_calculated_proximity(
                    v_pickup_ou,
                    v_request_ou,
                    prox_ou,
                    item_object.circ_modifier,
                    item_cn_object.owning_lib,
                    item_location_object.owning_lib
                );
            ELSE
                SELECT INTO hold_transit_prox prox::NUMERIC FROM actor.org_unit_proximity WHERE from_org = prox_ou AND to_org = v_pickup_ou;
            END IF;

            IF hold_transit_prox > age_protect_object.prox::NUMERIC THEN
                result.fail_part := 'config.rule_age_hold_protect.prox';
                result.success := FALSE;
                done := TRUE;
                RETURN NEXT result;
            END IF;
        END IF;
    END IF;

    IF NOT done THEN
        RETURN NEXT result;
    END IF;

    RETURN;
END;
$func$ LANGUAGE plpgsql;


  
SELECT evergreen.upgrade_deps_block_check('1222', :eg_version);

INSERT INTO action_trigger.reactor (module, description) VALUES (
    'CallHTTP', 'Push event information out to an external system via HTTP'
);

INSERT INTO action_trigger.hook (key, core_type, description, passive) VALUES (
    'bre.edit', 'bre', 'A bib record was edited', FALSE
);



SELECT evergreen.upgrade_deps_block_check('1223', :eg_version);

-- First, normalize the au.create[d] and au.update[d] hooks.  The code and seed data differ.

INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.created', 'au', 'A user was created', 't') ON CONFLICT DO NOTHING;
INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.updated', 'au', 'A user was updated', 't') ON CONFLICT DO NOTHING;


UPDATE action_trigger.event_definition SET hook = 'au.created' WHERE hook = 'au.create';
UPDATE action_trigger.event_definition SET hook = 'au.updated' WHERE hook = 'au.update';

DELETE FROM action_trigger.hook WHERE key = 'au.create';
DELETE FROM action_trigger.hook WHERE key = 'au.update';

-- Now the entirely new ones...
INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.renewed', 'au', 'A user was renewed by having their expire date changed', 't');

INSERT INTO action_trigger.hook (key, core_type, description, passive)
    VALUES ('au.barcode_changed', 'au', 'A card was updated or created for an existing user', 't');


SELECT evergreen.upgrade_deps_block_check('1224', :eg_version);

INSERT INTO config.coded_value_map (id,ctype,code,opac_visible,is_simple,value,search_label) VALUES
(1736,'icon_format','preloadedaudio',TRUE,FALSE,
    oils_i18n_gettext(1736, 'Preloaded Audio', 'ccvm', 'value'),
    oils_i18n_gettext(1736, 'Preloaded Audio', 'ccvm', 'search_label')),
(1737,'search_format','preloadedaudio',TRUE,FALSE,
    oils_i18n_gettext(1737, 'Preloaded Audio', 'ccvm', 'value'),
    oils_i18n_gettext(1737, 'Preloaded Audio', 'ccvm', 'search_label'))
;

INSERT INTO config.composite_attr_entry_definition (coded_value, definition) VALUES
((SELECT id from config.coded_value_map where ctype = 'search_format' AND code = 'preloadedaudio'),'{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"item_form","_val":"q"}}'),
((SELECT id from config.coded_value_map where ctype = 'icon_format' AND code = 'preloadedaudio'),'{"0":{"_attr":"item_type","_val":"i"},"1":{"_attr":"item_form","_val":"q"}}');



SELECT evergreen.upgrade_deps_block_check('1225', :eg_version);

ALTER TABLE acq.provider ADD COLUMN primary_contact INT;
ALTER TABLE acq.provider ADD CONSTRAINT acq_provider_primary_contact_fkey FOREIGN KEY (primary_contact) REFERENCES acq.provider_contact (id) ON DELETE SET NULL ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED;


SELECT evergreen.upgrade_deps_block_check('1226', :eg_version);

INSERT INTO config.workstation_setting_type
    (name, grp, datatype, label)
VALUES (
    'eg.grid.acq.provider.addresses', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.addresses',
    'Grid Config: acq.provider.addresses',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.attributes', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.attributes',
    'Grid Config: acq.provider.attributes',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.contact.addresses', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.contact.addresses',
    'Grid Config: acq.provider.contact.addresses',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.contacts', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.contacts',
    'Grid Config: acq.provider.contacts',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.edi_accounts', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.edi_accounts',
    'Grid Config: acq.provider.edi_accounts',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.edi_messages', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.edi_messages',
    'Grid Config: acq.provider.edi_messages',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.holdings', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.holdings',
    'Grid Config: acq.provider.holdings',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.invoices', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.invoices',
    'Grid Config: acq.provider.invoices',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.purchaseorders', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.purchaseorders',
    'Grid Config: acq.provider.purchaseorders',
    'cwst', 'label')
), (
    'eg.grid.acq.provider.search.results', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.acq.provider.search.results',
    'Grid Config: acq.provider.search.results',
    'cwst', 'label')
);


SELECT evergreen.upgrade_deps_block_check('1227', :eg_version);

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.cat.authority.browse', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.cat.authority.browse',
    'Grid Config: eg.grid.cat.authority.browse',
    'cwst', 'label')
), (
    'eg.grid.cat.authority.manage.bibs', 'gui', 'object',
    oils_i18n_gettext(
    'eg.grid.cat.authority.manage.bibs',
    'Grid Config: eg.grid.cat.authority.manage.bibs',
    'cwst', 'label')
);


SELECT evergreen.upgrade_deps_block_check('1228', :eg_version);

CREATE OR REPLACE FUNCTION actor.org_unit_full_path ( INT ) RETURNS SETOF actor.org_unit AS $$
    SELECT  aou.*
      FROM  actor.org_unit AS aou
            JOIN (
                (SELECT au.id, t.depth FROM actor.org_unit_ancestors($1) AS au JOIN actor.org_unit_type t ON (au.ou_type = t.id))
                    UNION
                (SELECT au.id, t.depth FROM actor.org_unit_descendants($1) AS au JOIN actor.org_unit_type t ON (au.ou_type = t.id))
            ) AS ad ON (aou.id=ad.id)
      ORDER BY ad.depth;
$$ LANGUAGE SQL STABLE;



SELECT evergreen.upgrade_deps_block_check('1229', :eg_version);


INSERT into action_trigger.hook (key, core_type, description) VALUES (
    'au.email.test', 'au', 'A test email has been requested for this user'
),
(
    'au.sms_text.test', 'au', 'A test SMS has been requested for this user'
);

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    't', 1, 'Send Test Email', 'au.email.test', 'NOOP_True', 'SendEmail', '00:01:00', 
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = target.home_ou -%]
To: [%- user.email %]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Reply-To: [%- lib.email || params.sender_email || default_sender %]
Subject: Email Test Notification
Auto-Submitted: auto-generated

Dear [% user.first_given_name %] [% user.family_name %],

This is a test of the email associated with your account at [%- lib.name -%]. If you are receiving this message, your email information is correct.

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

INSERT INTO action_trigger.event_definition (active, owner, name, hook, validator, reactor, delay, template)
VALUES (
    't', 1, 'Send Test SMS', 'au.sms_text.test', 'NOOP_True', 'SendSMS', '00:01:00', 
$$
[%- USE date -%]
[%- user = target -%]
[%- lib = user.home_ou -%]
[%- sms_number = helpers.get_user_setting(target.id, 'opac.default_sms_notify') -%]
[%- sms_carrier = helpers.get_user_setting(target.id, 'opac.default_sms_carrier') -%]
From: [%- helpers.get_org_setting(target.home_ou.id, 'org.bounced_emails') || lib.email || params.sender_email || default_sender %]
To: [%- helpers.get_sms_gateway_email(sms_carrier,sms_number) %]
Subject: Test Text Message

This is a test confirming your mobile number for [% lib.name %] is correct.

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



SELECT evergreen.upgrade_deps_block_check('1230', :eg_version);

INSERT INTO permission.perm_list
    ( id, code, description )
VALUES (
    623, 'UPDATE_ORG_UNIT_SETTING.opac.matomo', oils_i18n_gettext(623,
    'Allows a user to configure Matomo Analytics org unit settings', 'ppl', 'description')
);

INSERT into config.org_unit_setting_type
    ( name, grp, label, description, datatype, update_perm )
VALUES (
    'opac.analytics.matomo_id', 'opac',
    oils_i18n_gettext(
    'opac.analytics.matomo_id',
    'Matomo Site ID',
    'coust', 'label'),
    oils_i18n_gettext('opac.analytics.matomo_id',
    'The Site ID for your Evergreen catalog. You can find the Site ID in the tracking code you got from Matomo.',
    'coust', 'description'),
    'string', 623
), (
    'opac.analytics.matomo_url', 'opac',
    oils_i18n_gettext('opac.analytics.matomo_url',
    'Matomo URL',
    'coust', 'label'),
    oils_i18n_gettext('opac.analytics.matomo_url',
    'The URL for your the Matomo software. Be sure to include the trailing slash, e.g. https://my-evergreen.matomo.cloud/',
    'coust', 'description'),
    'string', 623
);



SELECT evergreen.upgrade_deps_block_check('1231', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'opac.email_record.allow_without_login', 'opac',
    oils_i18n_gettext('opac.email_record.allow_without_login',
        'Allow record emailing without login',
        'coust', 'label'),
    oils_i18n_gettext('opac.email_record.allow_without_login',
        'Instead of forcing a patron to log in in order to email the details of a record, just challenge them with a simple catpcha.',
        'coust', 'description'),
    'bool', null)
;

CREATE TABLE action_trigger.event_def_group (
    id      SERIAL  PRIMARY KEY,
    owner   INT     NOT NULL REFERENCES actor.org_unit (id)
                        ON DELETE RESTRICT ON UPDATE CASCADE
                        DEFERRABLE INITIALLY DEFERRED,
    hook    TEXT    NOT NULL REFERENCES action_trigger.hook (key)
                        ON DELETE RESTRICT ON UPDATE CASCADE
                        DEFERRABLE INITIALLY DEFERRED,
    active  BOOL    NOT NULL DEFAULT TRUE,
    name    TEXT    NOT NULL
);
SELECT SETVAL('action_trigger.event_def_group_id_seq'::TEXT, 100, TRUE);

CREATE TABLE action_trigger.event_def_group_member (
    id          SERIAL  PRIMARY KEY,
    grp         INT     NOT NULL REFERENCES action_trigger.event_def_group (id)
                            ON DELETE CASCADE ON UPDATE CASCADE
                            DEFERRABLE INITIALLY DEFERRED,
    event_def   INT     NOT NULL REFERENCES action_trigger.event_definition (id)
                            ON DELETE RESTRICT ON UPDATE CASCADE
                            DEFERRABLE INITIALLY DEFERRED,
    sortable    BOOL    NOT NULL DEFAULT TRUE,
    holdings    BOOL    NOT NULL DEFAULT FALSE,
    external    BOOL    NOT NULL DEFAULT FALSE,
    name        TEXT    NOT NULL
);

INSERT INTO action_trigger.event_def_group (id, owner, hook, name)
    VALUES (1, 1, 'biblio.format.record_entry.print','Print Record(s)');

INSERT INTO action_trigger.event_def_group (id, owner, hook, name)
    VALUES (2,1,'biblio.format.record_entry.email','Email Record(s)');

DO $block$
BEGIN
  PERFORM * FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email' AND owner = 1 AND active AND template =
$$
[%- USE date -%]
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Bibliographic Records
Auto-Submitted: auto-generated

[% FOR cbreb IN target %]
[% FOR item IN cbreb.items;
    bre_id = item.target_biblio_record_entry;

    bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
    title = '';
    FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
        title = title _ part.textContent;
    END;

    author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
    item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
    publisher = bibxml.findnodes('//*[@tag="260"]/*[@code="b"]').textContent;
    pubdate = bibxml.findnodes('//*[@tag="260"]/*[@code="c"]').textContent;
    isbn = bibxml.findnodes('//*[@tag="020"]/*[@code="a"]').textContent;
    issn = bibxml.findnodes('//*[@tag="022"]/*[@code="a"]').textContent;
    upc = bibxml.findnodes('//*[@tag="024"]/*[@code="a"]').textContent;
%]

[% loop.count %]/[% loop.size %].  Bib ID# [% bre_id %]
[% IF isbn %]ISBN: [% isbn _ "\n" %][% END -%]
[% IF issn %]ISSN: [% issn _ "\n" %][% END -%]
[% IF upc  %]UPC:  [% upc _ "\n" %] [% END -%]
Title: [% title %]
Author: [% author %]
Publication Info: [% publisher %] [% pubdate %]
Item Type: [% item_type %]

[% END %]
[% END %]
$$;

  IF FOUND THEN -- update

    INSERT INTO action_trigger.event_def_group_member (grp, name, event_def)
        SELECT 2, 'Brief', id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email';

    INSERT INTO action_trigger.event_def_group_member (grp, name, holdings, event_def)
        SELECT 2, 'Full', TRUE, id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email';

    UPDATE action_trigger.event_definition SET template = $$
[%- USE date -%]
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user_data.0.email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: [%- user_data.0.subject || 'Bibliographic Records' %]
Auto-Submitted: auto-generated

[%- FOR cbreb IN target;

    flesh_list = '{mra';
    IF user_data.0.type == 'full';
        flesh_list = flesh_list _ ',holdings_xml,acp';
        IF params.holdings_limit;
            flimit = 'acn=>' _ params.holdings_limit _ ',acp=>' _ params.holdings_limit;
        END;
    END;
    flesh_list = flesh_list _ '}';

    item_list = helpers.sort_bucket_unapi_bre(cbreb.items,{flesh => flesh_list, site => user_data.0.context_org, flesh_limit => flimit}, user_data.0.sort_by, user_data.0.sort_dir);

FOR item IN item_list -%]

[% loop.count %]/[% loop.size %].  Bib ID# [% item.id %]
[% IF item.isbn %]ISBN: [% item.isbn _ "\n" %][% END -%]
[% IF item.issn %]ISSN: [% item.issn _ "\n" %][% END -%]
[% IF item.upc  %]UPC:  [% item.upc _ "\n" %][% END -%]
Title: [% item.title %]
[% IF item.author %]Author: [% item.author _ "\n" %][% END -%]
Publication Info: [% item.publisher %] [% item.pubdate %]
Item Type: [% item.item_type %]
[% IF user_data.0.type == 'full' && item.holdings.size == 0 %]
 * No items for this record at the selected location
[%- END %]
[% FOR cp IN item.holdings -%]
 * Library: [% cp.circ_lib %]
   Location: [% cp.location %]
   Call Number: [% cp.prefix _ ' ' _ cp.callnumber _ ' ' _ cp.suffix %]
[% IF cp.parts %]   Parts: [% cp.parts _ "\n" %][% END -%]
   Status: [% cp.status_label %]
   Barcode: [% cp.barcode %]
 
[% END -%]
[%- END -%]
[%- END -%]
$$ WHERE hook = 'biblio.format.record_entry.email' AND owner = 1 AND active;

  ELSE -- insert full and add existing brief

    INSERT INTO action_trigger.event_def_group_member (grp, name, event_def)
        SELECT 2, 'Brief', id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email' AND active;

    INSERT INTO action_trigger.event_definition (
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        cleanup_success,
        cleanup_failure,
        group_field,
        granularity,
        delay,
        template
    ) SELECT
        TRUE,
        owner,
        'biblio.record_entry.email.full',
        'biblio.format.record_entry.email',
        'NOOP_True',
        'SendEmail',
        'DeleteTempBiblioBucket',
        'DeleteTempBiblioBucket',
        'owner',
        NULL,
        '00:00:00',
        $$
[%- USE date -%]
[%- SET user = target.0.owner -%]
To: [%- params.recipient_email || user_data.0.email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: [%- user_data.0.subject || 'Bibliographic Records' %]
Auto-Submitted: auto-generated

[%- FOR cbreb IN target;

    flesh_list = '{mra';
    IF user_data.0.type == 'full';
        flesh_list = flesh_list _ ',holdings_xml,acp';
        IF params.holdings_limit;
            flimit = 'acn=>' _ params.holdings_limit _ ',acp=>' _ params.holdings_limit;
        END;
    END;
    flesh_list = flesh_list _ '}';

    item_list = helpers.sort_bucket_unapi_bre(cbreb.items,{flesh => flesh_list, site => user_data.0.context_org, flesh_limit => flimit}, user_data.0.sort_by, user_data.0.sort_dir);

FOR item IN item_list -%]

[% loop.count %]/[% loop.size %].  Bib ID# [% item.id %]
[% IF item.isbn %]ISBN: [% item.isbn _ "\n" %][% END -%]
[% IF item.issn %]ISSN: [% item.issn _ "\n" %][% END -%]
[% IF item.upc  %]UPC:  [% item.upc _ "\n" %][% END -%]
Title: [% item.title %]
[% IF item.author %]Author: [% item.author _ "\n" %][% END -%]
Publication Info: [% item.publisher %] [% item.pubdate %]
Item Type: [% item.item_type %]
[% IF user_data.0.type == 'full' && item.holdings.size == 0 %]
 * No items for this record at the selected location
[%- END %]
[% FOR cp IN item.holdings -%]
 * Library: [% cp.circ_lib %]
   Location: [% cp.location %]
   Call Number: [% cp.prefix _ ' ' _ cp.callnumber _ ' ' _ cp.suffix %]
[% IF cp.parts %]   Parts: [% cp.parts _ "\n" %][% END -%]
   Status: [% cp.status_label %]
   Barcode: [% cp.barcode %]
 
[% END -%]
[%- END -%]
[%- END -%]
$$ FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.email' AND active;

    INSERT INTO action_trigger.event_def_group_member (grp, name, holdings, event_def)
        SELECT 2, 'Full', TRUE, id FROM action_trigger.event_definition WHERE name = 'biblio.record_entry.email.full' and active;

  END IF;
END
$block$;

DO $block$
BEGIN
  PERFORM * FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print' AND owner = 1 AND active AND template =
$$
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target %]
    [% FOR item IN cbreb.items;
        bre_id = item.target_biblio_record_entry;

        bibxml = helpers.unapi_bre(bre_id, {flesh => '{mra}'});
        title = '';
        FOR part IN bibxml.findnodes('//*[@tag="245"]/*[@code="a" or @code="b"]');
            title = title _ part.textContent;
        END;

        author = bibxml.findnodes('//*[@tag="100"]/*[@code="a"]').textContent;
        item_type = bibxml.findnodes('//*[local-name()="attributes"]/*[local-name()="field"][@name="item_type"]').getAttribute('coded-value');
        publisher = bibxml.findnodes('//*[@tag="260"]/*[@code="b"]').textContent;
        pubdate = bibxml.findnodes('//*[@tag="260"]/*[@code="c"]').textContent;
        isbn = bibxml.findnodes('//*[@tag="020"]/*[@code="a"]').textContent;
        %]

        <li>
            Bib ID# [% bre_id %] ISBN: [% isbn %]<br />
            Title: [% title %]<br />
            Author: [% author %]<br />
            Publication Info: [% publisher %] [% pubdate %]<br/>
            Item Type: [% item_type %]
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$;

  IF FOUND THEN -- update

    INSERT INTO action_trigger.event_def_group_member (grp, name, event_def)
        SELECT 1, 'Brief', id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print';

    INSERT INTO action_trigger.event_def_group_member (grp, name, holdings, event_def)
        SELECT 1, 'Full', TRUE, id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print';

    UPDATE action_trigger.event_definition SET template = $$
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target;

    flesh_list = '{mra';
    IF user_data.0.type == 'full';
        flesh_list = flesh_list _ ',holdings_xml,acp';
        IF params.holdings_limit;
            flimit = 'acn=>' _ params.holdings_limit _ ',acp=>' _ params.holdings_limit;
        END;
    END;
    flesh_list = flesh_list _ '}';

    item_list = helpers.sort_bucket_unapi_bre(cbreb.items,{flesh => flesh_list, site => user_data.0.context_org, flesh_limit => flimit}, user_data.0.sort_by, user_data.0.sort_dir);
    FOR item IN item_list %]
        <li>
            Bib ID# [% item.id %]<br />
            [% IF item.isbn %]ISBN: [% item.isbn %]<br />[% END %]
            [% IF item.issn %]ISSN: [% item.issn %]<br />[% END %]
            [% IF item.upc  %]UPC:  [% item.upc %]<br />[% END %]
            Title: [% item.title %]<br />
[% IF item.author %]            Author: [% item.author %]<br />[% END -%]
            Publication Info: [% item.publisher %] [% item.pubdate %]<br/>
            Item Type: [% item.item_type %]
            <ul>
            [% IF user_data.0.type == 'full' && item.holdings.size == 0 %]
                <li>No items for this record at the selected location</li>
            [% END %]
            [% FOR cp IN item.holdings -%]
                <li>
                    Library: [% cp.circ_lib %]<br/>
                    Location: [% cp.location %]<br/>
                    Call Number: [% cp.prefix _ ' ' _ cp.callnumber _ ' ' _ cp.suffix %]<br/>
                    [% IF cp.parts %]Parts: [% cp.parts %]<br/>[% END %]
                    Status: [% cp.status_label %]<br/>
                    Barcode: [% cp.barcode %]
                </li>
            [% END %]
            </ul>
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$ WHERE hook = 'biblio.format.record_entry.print' AND owner = 1 AND active;

    ELSE -- insert full and add brief

    INSERT INTO action_trigger.event_def_group_member (grp, name, event_def)
        SELECT 1, 'Brief', id FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print' AND active;

    INSERT INTO action_trigger.event_definition (
        active,
        owner,
        name,
        hook,
        validator,
        reactor,
        cleanup_success,
        cleanup_failure,
        group_field,
        granularity,
        delay,
        template
    ) SELECT
        TRUE,
        owner,
        'biblio.record_entry.print.full',
        'biblio.format.record_entry.print',
        'NOOP_True',
        'ProcessTemplate',
        'DeleteTempBiblioBucket',
        'DeleteTempBiblioBucket',
        'owner',
        'print-on-demand',
        '00:00:00',
        $$
<div>
    <style> li { padding: 8px; margin 5px; }</style>
    <ol>
    [% FOR cbreb IN target;

    flesh_list = '{mra';
    IF user_data.0.type == 'full';
        flesh_list = flesh_list _ ',holdings_xml,acp';
        IF params.holdings_limit;
            flimit = 'acn=>' _ params.holdings_limit _ ',acp=>' _ params.holdings_limit;
        END;
    END;
    flesh_list = flesh_list _ '}';

    item_list = helpers.sort_bucket_unapi_bre(cbreb.items,{flesh => flesh_list, site => user_data.0.context_org, flesh_limit => flimit}, user_data.0.sort_by, user_data.0.sort_dir);
    FOR item IN item_list %]
        <li>
            Bib ID# [% item.id %]<br />
            [% IF item.isbn %]ISBN: [% item.isbn %]<br />[% END %]
            [% IF item.issn %]ISSN: [% item.issn %]<br />[% END %]
            [% IF item.upc  %]UPC:  [% item.upc %]<br />[% END %]
            Title: [% item.title %]<br />
[% IF item.author %]            Author: [% item.author %]<br />[% END -%]
            Publication Info: [% item.publisher %] [% item.pubdate %]<br/>
            Item Type: [% item.item_type %]
            <ul>
            [% IF user_data.0.type == 'full' && item.holdings.size == 0 %]
                <li>No items for this record at the selected location</li>
            [% END %]
            [% FOR cp IN item.holdings -%]
                <li>
                    Library: [% cp.circ_lib %]<br/>
                    Location: [% cp.location %]<br/>
                    Call Number: [% cp.prefix _ ' ' _ cp.callnumber _ ' ' _ cp.suffix %]<br/>
                    [% IF cp.parts %]Parts: [% cp.parts %]<br/>[% END %]
                    Status: [% cp.status_label %]<br/>
                    Barcode: [% cp.barcode %]
                </li>
            [% END %]
            </ul>
        </li>
    [% END %]
    [% END %]
    </ol>
</div>
$$ FROM action_trigger.event_definition WHERE hook = 'biblio.format.record_entry.print' AND active;

    INSERT INTO action_trigger.event_def_group_member (grp, name, holdings, event_def)
        SELECT 1, 'Full', TRUE, id FROM action_trigger.event_definition WHERE name = 'biblio.record_entry.print.full' and active;

  END IF;
END
$block$;



SELECT evergreen.upgrade_deps_block_check('1232', :eg_version);

CREATE TABLE asset.course_module_course (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    course_number   TEXT NOT NULL,
    section_number  TEXT,
    owning_lib      INT REFERENCES actor.org_unit (id),
    is_archived        BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE asset.course_module_role (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    UNIQUE NOT NULL,
    is_public       BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE asset.course_module_course_users (
    id              SERIAL PRIMARY KEY,
    course          INT NOT NULL REFERENCES asset.course_module_course (id),
    usr             INT NOT NULL REFERENCES actor.usr (id),
    usr_role        INT REFERENCES asset.course_module_role (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE asset.course_module_course_materials (
    id              SERIAL PRIMARY KEY,
    course          INT NOT NULL REFERENCES asset.course_module_course (id),
    item            INT REFERENCES asset.copy (id),
    relationship    TEXT,
    record          INT REFERENCES biblio.record_entry (id),
    temporary_record       BOOLEAN,
    original_location      INT REFERENCES asset.copy_location,
    original_status        INT REFERENCES config.copy_status,
    original_circ_modifier TEXT, --REFERENCES config.circ_modifier
    original_callnumber    INT REFERENCES asset.call_number,
    unique (course, item, record)
);

CREATE TABLE asset.course_module_term (
    id              SERIAL  PRIMARY KEY,
    name            TEXT    UNIQUE NOT NULL,
    owning_lib      INT REFERENCES actor.org_unit (id),
    start_date      TIMESTAMP WITH TIME ZONE,
    end_date        TIMESTAMP WITH TIME ZONE
);

INSERT INTO asset.course_module_role (id, name, is_public) VALUES
(1, oils_i18n_gettext(1, 'Instructor', 'acmr', 'name'), true),
(2, oils_i18n_gettext(2, 'Teaching assistant', 'acmr', 'name'), true),
(3, oils_i18n_gettext(2, 'Student', 'acmr', 'name'), false);

SELECT SETVAL('asset.course_module_role_id_seq'::TEXT, 100);

CREATE TABLE asset.course_module_term_course_map (
    id              BIGSERIAL  PRIMARY KEY,
    term            INT     NOT NULL REFERENCES asset.course_module_term (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    course          INT     NOT NULL REFERENCES asset.course_module_course (id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

INSERT INTO permission.perm_list(id, code, description)
    VALUES (
        624,
        'MANAGE_RESERVES',
        oils_i18n_gettext(
            624,
            'Allows user to manage Courses, Course Materials, and associate Users with Courses.',
            'ppl',
            'description'
        )
    );

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
    SELECT
        pgt.id, perm.id, aout.depth, TRUE
    FROM
        permission.grp_tree pgt,
        permission.perm_list perm,
        actor.org_unit_type aout
    WHERE
        pgt.name = 'Circulation Administrator' AND
        aout.name = 'Consortium' AND
        perm.code = 'MANAGE_RESERVES'
;

INSERT INTO config.org_unit_setting_type 
    (grp, name, datatype, label, description, fm_class)
VALUES (
    'circ',
    'circ.course_materials_opt_in', 'bool',
    oils_i18n_gettext(
        'circ.course_materials_opt_in',
        'Opt Org Unit into the Course Materials Module',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.course_materials_opt_in',
        'If enabled, the Org Unit will utilize Course Material functionality.',
        'coust',
        'description'
    ), null
), (
    'circ',
    'circ.course_materials_browse_by_instructor', 'bool',
    oils_i18n_gettext(
        'circ.course_materials_browse_by_instructor',
        'Allow users to browse Courses by Instructor',
        'coust',
        'label'
    ),
    oils_i18n_gettext(
        'circ.course_materials_browse_by_instructor',
        'If enabled, the Org Unit will allow OPAC users to browse Courses by instructor name.',
        'coust',
        'description'
    ), null
), (
    'circ',
    'circ.course_materials_brief_record_bib_source', 'link',
    oils_i18n_gettext(
        'circ.course_materials_brief_record_bib_source',
        'Bib source for brief records created in the course materials module',
        'coust', 'label'
    ),
    oils_i18n_gettext(
        'circ.course_materials_brief_record_bib_source',
        'The course materials module will use this bib source for any new brief bibliographic records made inside that module. For best results, use a transcendant bib source.',
        'coust', 'description'
    ), 'cbs'

);

INSERT INTO config.bib_source (quality, source, transcendant) VALUES
    (1, oils_i18n_gettext(4, 'Course materials module', 'cbs', 'source'), TRUE);

INSERT INTO actor.org_unit_setting (org_unit, name, value)
    SELECT 1, 'circ.course_materials_brief_record_bib_source', id
    FROM config.bib_source
    WHERE source='Course materials module';


SELECT evergreen.upgrade_deps_block_check('1233', :eg_version);

INSERT into config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.hopeless.wide_holds', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.hopeless.wide_holds',
        'Grid Config: hopeless.wide_holds',
        'cwst', 'label'
    )
);



SELECT evergreen.upgrade_deps_block_check('1234', :eg_version);

ALTER TABLE config.copy_status ADD COLUMN hopeless_prone BOOL NOT NULL DEFAULT FALSE; -- 002.schema.config.sql
ALTER TABLE action.hold_request ADD COLUMN hopeless_date TIMESTAMP WITH TIME ZONE; -- 090.schema.action.sql

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('1235', :eg_version);

CREATE TABLE action.curbside (
    id          SERIAL      PRIMARY KEY,
    patron      INT         NOT NULL REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    org         INT         NOT NULL REFERENCES actor.org_unit (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    slot        TIMESTAMPTZ,
    staged      TIMESTAMPTZ,
    stage_staff     INT     REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    arrival     TIMESTAMPTZ,
    delivered   TIMESTAMPTZ,
    delivery_staff  INT     REFERENCES actor.usr (id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    notes       TEXT
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'circ.curbside',
    'Enable curbside pickup functionality at library.',
    'circ',
    'When set to TRUE, enable staff and public interfaces to schedule curbside pickup of holds that become available for pickup.',
    'bool'
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'circ.curbside.granularity',
    'Time interval between curbside appointments',
    'circ',
    'Time interval between curbside appointments',
    'interval'
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'circ.curbside.max_concurrent',
    'Maximum number of patrons that may select a particular curbside pickup time',
    'circ',
    'Maximum number of patrons that may select a particular curbside pickup time',
    'integer'
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'circ.curbside.disable_patron_input',
    'Disable patron modification of curbside appointments in public catalog',
    'circ',
    'When set to TRUE, patrons cannot use the My Account interface to select curbside pickup times',
    'bool'
);

INSERT INTO actor.org_unit_setting (org_unit, name, value)
    SELECT id, 'circ.curbside', 'false' FROM actor.org_unit WHERE parent_ou IS NULL
        UNION
    SELECT id, 'circ.curbside.max_concurrent', '10' FROM actor.org_unit WHERE parent_ou IS NULL
        UNION
    SELECT id, 'circ.curbside.granularity', '"15 minutes"' FROM actor.org_unit WHERE parent_ou IS NULL
;

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'hold.offer_curbside',
    'ahr',
    oils_i18n_gettext(
        'hold.offer_curbside',
        'Hook used to trigger the notification of an offer of curbside pickup',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.hook (key, core_type, description, passive)
VALUES (
    'hold.confirm_curbside',
    'acsp',
    oils_i18n_gettext(
        'hold.confirm_curbside',
        'Hook used to trigger the notification of the creation or update of a curbside pickup appointment with an arrival URL',
        'ath',
        'description'
    ),
    FALSE
);

INSERT INTO action_trigger.reactor (module, description) VALUES (
    'CurbsideSlot', 'Create a curbside pickup appointment slot when necessary'
);

INSERT INTO action_trigger.validator (module, description) VALUES (
    'Curbside', 'Confirm that curbside pickup is enabled for the hold pickup library'
);

------------------- Disabled example A/T defintions ------------------------------

-- Create a "dummy" slot when applicable, and trigger the "offer curbside" events
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay
) VALUES (
    'f',
    1,
    'Trigger curbside offer events and create a placeholder for the patron, where applicable',
    'hold.available',
    'Curbside',
    'CurbsideSlot',
    '00:30:00'
);

-- Email offer
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay,
    delay_field,
    group_field,
    template
) VALUES (
    'f',
    1,
    'Curbside offer Email notification, triggered by CurbsideSlot reactor on a definition attached to the hold.available hook',
    'hold.offer_curbside',
    'Curbside',
    'SendEmail',
    '00:00:00',
    'shelf_time',
    'usr',
$$
[%- USE date -%]
[%- user = target.0.usr -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Curbside Pickup
Auto-Submitted: auto-generated

[% target.0.pickup_lib.name %] is now offering curbside delivery
service.  Please call [% target.0.pickup_lib.phone %] or visit the
link below to schedule a pickup time.

https://example.org/eg/opac/myopac/holds_curbside

Stay safe! Wash your hands!
$$);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'pickup_lib'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
);

INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (currval('action_trigger.event_definition_id_seq'), 'check_email_notify', 1);

-- SMS offer
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay,
    delay_field,
    group_field,
    template
) VALUES (
    false,
    1,
    'Curbside offer SMS notification, triggered by CurbsideSlot reactor on a definition attached to the hold.available hook',
    'hold.offer_curbside',
    'Curbside',
    'SendSMS',
    '00:00:00',
    'shelf_time',
    'sms_notify',
    $$[%- USE date -%]
[%- user = target.0.usr -%]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
To: [%- params.recipient_email || helpers.get_sms_gateway_email(target.0.sms_carrier,target.0.sms_notify) %]
Subject: Curbside Pickup
Auto-Submitted: auto-generated

[% target.0.pickup_lib.name %] offers curbside pickup.
Call [% target.0.pickup_lib.phone %] or visit https://example.org/eg/opac/myopac/holds_curbside
$$
);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'pickup_lib'
), (
    currval('action_trigger.event_definition_id_seq'),
    'usr'
);

INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (currval('action_trigger.event_definition_id_seq'), 'check_sms_notify', 1);

-- Email confirmation
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay,
    template
) VALUES (
    'f',
    1,
    'Curbside confirmation Email notification',
    'hold.confirm_curbside',
    'Curbside',
    'SendEmail',
    '00:00:00',
$$
[%- USE date -%]
[%- user = target.patron -%]
To: [%- params.recipient_email || user.email %]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
Subject: Curbside Pickup Confirmed
Auto-Submitted: auto-generated

This email is to confirm that you have scheduled a curbside item
pickup at [% target.org.name %] for [% date.format(helpers.format_date(target.slot), '%a, %d %b %Y %T') %].

You can cancel or change to your appointment, add vehicle description
notes, and alert staff to your arrival by going to the link below.

When you arrive, please call [% target.org.phone %] or visit the
link below to let us know you are here.

https://example.org/eg/opac/myopac/holds_curbside

Stay safe! Wash your hands!
$$);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'org'
), (
    currval('action_trigger.event_definition_id_seq'),
    'patron'
);

-- We do /not/ add this by default, treating curbside request as implicit opt-in
/*
INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (currval('action_trigger.event_definition_id_seq'), 'check_email_notify', 1);
*/

-- SMS confirmation
INSERT INTO action_trigger.event_definition (
    active,
    owner,
    name,
    hook,
    validator,
    reactor,
    delay,
    template
) VALUES (
    false,
    1,
    'Curbside confirmation SMS notification',
    'hold.confirm_curbside',
    'Curbside',
    'SendSMS',
    '00:00:00',
    $$[%- USE date -%]
[%- user = target.patron -%]
From: [%- params.sender_email || default_sender %]
Date: [%- date.format(date.now, '%a, %d %b %Y %T -0000', gmt => 1) %]
To: [%- params.recipient_email || helpers.get_sms_gateway_email(helpers.get_user_setting(user.id, 'opac.default_sms_carrier'), helpers.get_user_setting(user.id, 'opac.default_sms_notify')) %]
Subject: Curbside Pickup Confirmed
Auto-Submitted: auto-generated

Location: [% target.org.name %]
Time: [% date.format(helpers.format_date(target.slot), '%a, %d %b %Y %T') %]
Make changes at https://example.org/eg/opac/myopac/holds_curbside
$$
);

INSERT INTO action_trigger.environment (
    event_def,
    path
) VALUES (
    currval('action_trigger.event_definition_id_seq'),
    'org'
), (
    currval('action_trigger.event_definition_id_seq'),
    'patron'
);

-- We do /not/ add this by default, treating curbside request as implicit opt-in
/*
INSERT INTO action_trigger.event_params (event_def, param, value)
    VALUES (currval('action_trigger.event_definition_id_seq'), 'check_sms_notify', 1);
*/


COMMIT;

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
