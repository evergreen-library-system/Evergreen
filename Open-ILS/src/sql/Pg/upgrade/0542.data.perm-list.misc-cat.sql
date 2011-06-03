BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0542'); -- phasefx

INSERT INTO permission.perm_list VALUES
    (485, 'CREATE_VOLUME_SUFFIX', oils_i18n_gettext(485, 'Create suffix label definition.', 'ppl', 'description'))
    ,(486, 'UPDATE_VOLUME_SUFFIX', oils_i18n_gettext(486, 'Update suffix label definition.', 'ppl', 'description'))
    ,(487, 'DELETE_VOLUME_SUFFIX', oils_i18n_gettext(487, 'Delete suffix label definition.', 'ppl', 'description'))
    ,(488, 'CREATE_VOLUME_PREFIX', oils_i18n_gettext(488, 'Create prefix label definition.', 'ppl', 'description'))
    ,(489, 'UPDATE_VOLUME_PREFIX', oils_i18n_gettext(489, 'Update prefix label definition.', 'ppl', 'description'))
    ,(490, 'DELETE_VOLUME_PREFIX', oils_i18n_gettext(490, 'Delete prefix label definition.', 'ppl', 'description'))
    ,(491, 'CREATE_MONOGRAPH_PART', oils_i18n_gettext(491, 'Create monograph part definition.', 'ppl', 'description'))
    ,(492, 'UPDATE_MONOGRAPH_PART', oils_i18n_gettext(492, 'Update monograph part definition.', 'ppl', 'description'))
    ,(493, 'DELETE_MONOGRAPH_PART', oils_i18n_gettext(493, 'Delete monograph part definition.', 'ppl', 'description'))
    ,(494, 'ADMIN_CODED_VALUE', oils_i18n_gettext(494, 'Create/Update/Delete SVF Record Attribute Coded Value Map', 'ppl', 'description'))
    ,(495, 'ADMIN_SERIAL_ITEM', oils_i18n_gettext(495, 'Create/Retrieve/Update/Delete Serial Item', 'ppl', 'description'))
    ,(496, 'ADMIN_SVF', oils_i18n_gettext(496, 'Create/Update/Delete SVF Record Attribute Defintion', 'ppl', 'description'))
    ,(497, 'CREATE_BIB_PTYPE', oils_i18n_gettext(497, 'Create Bibliographic Record Peer Type', 'ppl', 'description'))
    ,(498, 'CREATE_PURCHASE_REQUEST', oils_i18n_gettext(498, 'Create User Purchase Request', 'ppl', 'description'))
    ,(499, 'DELETE_BIB_PTYPE', oils_i18n_gettext(499, 'Delete Bibliographic Record Peer Type', 'ppl', 'description'))
    ,(500, 'MAP_MONOGRAPH_PART', oils_i18n_gettext(500, 'Create/Update/Delete Copy Monograph Part Map', 'ppl', 'description'))
    ,(501, 'MARK_ITEM_MISSING_PIECES', oils_i18n_gettext(501, 'Allows the Mark Item Missing Pieces action.', 'ppl', 'description'))
    ,(502, 'UPDATE_BIB_PTYPE', oils_i18n_gettext(502, 'Update Bibliographic Record Peer Type', 'ppl', 'description'))
    ,(503, 'UPDATE_HOLD_REQUEST_TIME', oils_i18n_gettext(503, 'Allows editing of a hold''s request time, and/or its Cut-in-line/Top-of-queue flag.', 'ppl', 'description'))
    ,(504, 'UPDATE_PICKLIST', oils_i18n_gettext(504, 'Allows update/re-use of an acquisitions pick/selection list.', 'ppl', 'description'))
    ,(505, 'UPDATE_WORKSTATION', oils_i18n_gettext(505, 'Allows update of a workstation during workstation registration override.', 'ppl', 'description'))
    ,(506, 'VIEW_USER_SETTING_TYPE', oils_i18n_gettext(506, 'Allows viewing of configurable user setting types.', 'ppl', 'description'))
;


-- add new perms AND catch up on some missed upgrade data, if needed

-- we could get away from these fixed-id inserts here, but then this
-- upgrade would be ahead of the mainline, I think

INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm)
	SELECT 8, oils_i18n_gettext(8, 'Cataloging Administrator', 'pgt', 'name'), 3, NULL, '3 years', TRUE, 'group_application.user.staff.cat_admin'
	WHERE NOT EXISTS (
		SELECT 1
		FROM permission.grp_tree
		WHERE
			id = 8
	);

INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm)
	SELECT 9, oils_i18n_gettext(9, 'Circulation Administrator', 'pgt', 'name'), 3, NULL, '3 years', TRUE, 'group_application.user.staff.circ_admin'
	WHERE NOT EXISTS (
		SELECT 1
		FROM permission.grp_tree
		WHERE
			id = 9
	);

UPDATE permission.grp_tree SET description = oils_i18n_gettext(10, 'Can do anything at the Branch level', 'pgt', 'description') WHERE id = 10;

INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm)
	SELECT 11, oils_i18n_gettext(11, 'Serials', 'pgt', 'name'), 3, oils_i18n_gettext(11, 'Serials (includes admin features)', 'pgt', 'description'), '3 years', TRUE, 'group_application.user.staff.serials'
	WHERE NOT EXISTS (
		SELECT 1
		FROM permission.grp_tree
		WHERE
			id = 11
	);

INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm)
	SELECT 12, oils_i18n_gettext(12, 'System Administrator', 'pgt', 'name'), 3, oils_i18n_gettext(12, 'Can do anything at the System level', 'pgt', 'description'), '3 years', TRUE, 'group_application.user.staff.admin.system_admin'
	WHERE NOT EXISTS (
		SELECT 1
		FROM permission.grp_tree
		WHERE
			id = 12
	);

INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm)
	SELECT 13, oils_i18n_gettext(13, 'Global Administrator', 'pgt', 'name'), 3, oils_i18n_gettext(13, 'Can do anything at the Consortium level', 'pgt', 'description'), '3 years', TRUE, 'group_application.user.staff.admin.global_admin'
	WHERE NOT EXISTS (
		SELECT 1
		FROM permission.grp_tree
		WHERE
			id = 13
	);

INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm)
	SELECT 14, oils_i18n_gettext(14, 'Data Review', 'pgt', 'name'), 3, NULL, '3 years', TRUE, 'group_application.user.staff.data_review'
	WHERE NOT EXISTS (
		SELECT 1
		FROM permission.grp_tree
		WHERE
			id = 14
	);

INSERT INTO permission.grp_tree (id, name, parent, description, perm_interval, usergroup, application_perm)
	SELECT 15, oils_i18n_gettext(15, 'Volunteers', 'pgt', 'name'), 3, NULL, '3 years', TRUE, 'group_application.user.staff.volunteers'
	WHERE NOT EXISTS (
		SELECT 1
		FROM permission.grp_tree
		WHERE
			id = 15
	);



INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Cataloging Administrator' AND
		aout.name = 'Consortium' AND
		perm.code IN (
			'ADMIN_IMPORT_ITEM_ATTR_DEF',
			'ADMIN_MERGE_PROFILE',
			'CREATE_AUTHORITY_IMPORT_IMPORT_DEF',
			'CREATE_BIB_IMPORT_FIELD_DEF',
			'CREATE_BIB_PTYPE',
			'CREATE_BIB_SOURCE',
			'CREATE_IMPORT_ITEM_ATTR_DEF',
			'CREATE_IMPORT_TRASH_FIELD',
			'CREATE_MERGE_PROFILE',
			'CREATE_MONOGRAPH_PART',
			'CREATE_VOLUME_PREFIX',
			'CREATE_VOLUME_SUFFIX',
			'DELETE_AUTHORITY_IMPORT_IMPORT_FIELD_DEF',
			'DELETE_BIB_PTYPE',
			'DELETE_BIB_SOURCE',
			'DELETE_IMPORT_ITEM_ATTR_DEF',
			'DELETE_IMPORT_TRASH_FIELD',
			'DELETE_MERGE_PROFILE',
			'DELETE_MONOGRAPH_PART',
			'DELETE_VOLUME_PREFIX',
			'DELETE_VOLUME_SUFFIX',
			'MAP_MONOGRAPH_PART',
			'UPDATE_AUTHORITY_IMPORT_IMPORT_FIELD_DEF',
			'UPDATE_BIB_IMPORT_IMPORT_FIELD_DEF',
			'UPDATE_BIB_PTYPE',
			'UPDATE_IMPORT_ITEM_ATTR_DEF',
			'UPDATE_IMPORT_TRASH_FIELD',
			'UPDATE_MERGE_PROFILE',
			'UPDATE_MONOGRAPH_PART',
			'UPDATE_VOLUME_PREFIX',
			'UPDATE_VOLUME_SUFFIX'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
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
		aout.name = 'Branch' AND
		perm.code IN (
			'DELETE_USER'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
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
		perm.code IN (
			'ADMIN_MAX_FINE_RULE',
			'CREATE_CIRC_DURATION',
			'DELETE_CIRC_DURATION',
			'MARK_ITEM_MISSING_PIECES',
			'UPDATE_CIRC_DURATION',
			'UPDATE_HOLD_REQUEST_TIME',
			'UPDATE_NET_ACCESS_LEVEL',
			'VIEW_CIRC_MATRIX_MATCHPOINT',
			'VIEW_HOLD_MATRIX_MATCHPOINT'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
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
		aout.name = 'System' AND
		perm.code IN (
			'ADMIN_BOOKING_RESERVATION',
			'ADMIN_BOOKING_RESERVATION_ATTR_MAP',
			'ADMIN_BOOKING_RESERVATION_ATTR_VALUE_MAP',
			'ADMIN_BOOKING_RESOURCE',
			'ADMIN_BOOKING_RESOURCE_ATTR',
			'ADMIN_BOOKING_RESOURCE_ATTR_MAP',
			'ADMIN_BOOKING_RESOURCE_ATTR_VALUE',
			'ADMIN_BOOKING_RESOURCE_TYPE',
			'ADMIN_COPY_LOCATION_ORDER',
			'ADMIN_HOLD_CANCEL_CAUSE',
			'ASSIGN_GROUP_PERM',
			'BAR_PATRON',
			'COPY_HOLDS',
			'COPY_TRANSIT_RECEIVE',
			'CREATE_BILL',
			'CREATE_BILLING_TYPE',
			'CREATE_NON_CAT_TYPE',
			'CREATE_PATRON_STAT_CAT',
			'CREATE_PATRON_STAT_CAT_ENTRY',
			'CREATE_PATRON_STAT_CAT_ENTRY_MAP',
			'CREATE_USER_GROUP_LINK',
			'DELETE_BILLING_TYPE',
			'DELETE_NON_CAT_TYPE',
			'DELETE_PATRON_STAT_CAT',
			'DELETE_PATRON_STAT_CAT_ENTRY',
			'DELETE_PATRON_STAT_CAT_ENTRY_MAP',
			'DELETE_TRANSIT',
			'group_application.user.staff',
			'MANAGE_BAD_DEBT',
			'MARK_ITEM_AVAILABLE',
			'MARK_ITEM_BINDERY',
			'MARK_ITEM_CHECKED_OUT',
			'MARK_ITEM_ILL',
			'MARK_ITEM_IN_PROCESS',
			'MARK_ITEM_IN_TRANSIT',
			'MARK_ITEM_LOST',
			'MARK_ITEM_MISSING',
			'MARK_ITEM_ON_HOLDS_SHELF',
			'MARK_ITEM_ON_ORDER',
			'MARK_ITEM_RESHELVING',
			'MERGE_USERS',
			'money.collections_tracker.create',
			'money.collections_tracker.delete',
			'OFFLINE_EXECUTE',
			'OFFLINE_UPLOAD',
			'OFFLINE_VIEW',
			'REMOVE_USER_GROUP_LINK',
			'SET_CIRC_CLAIMS_RETURNED',
			'SET_CIRC_CLAIMS_RETURNED.override',
			'SET_CIRC_LOST',
			'SET_CIRC_MISSING',
			'UNBAR_PATRON',
			'UPDATE_BILL_NOTE',
			'UPDATE_NON_CAT_TYPE',
			'UPDATE_PATRON_CLAIM_NEVER_CHECKED_OUT_COUNT',
			'UPDATE_PATRON_CLAIM_RETURN_COUNT',
			'UPDATE_PICKUP_LIB_FROM_HOLDS_SHELF',
			'UPDATE_PICKUP_LIB_FROM_TRANSIT',
			'UPDATE_USER',
			'VIEW_REPORT_OUTPUT',
			'VIEW_STANDING_PENALTY',
			'VOID_BILLING',
			'VOLUME_HOLDS'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Local Administrator' AND
		aout.name = 'Branch' AND
		perm.code IN (
			'EVERYTHING'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Serials' AND
		aout.name = 'System' AND
		perm.code IN (
			'ADMIN_ASSET_COPY_TEMPLATE',
			'ADMIN_SERIAL_CAPTION_PATTERN',
			'ADMIN_SERIAL_DISTRIBUTION',
			'ADMIN_SERIAL_ITEM',
			'ADMIN_SERIAL_STREAM',
			'ADMIN_SERIAL_SUBSCRIPTION',
			'ISSUANCE_HOLDS',
			'RECEIVE_SERIAL'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'System Administrator' AND
		aout.name = 'System' AND
		perm.code IN (
			'EVERYTHING'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'System Administrator' AND
		aout.name = 'Consortium' AND
		perm.code ~ '^VIEW_TRIGGER'
		AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, TRUE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Global Administrator' AND
		aout.name = 'Consortium' AND
		perm.code IN (
			'EVERYTHING'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Data Review' AND
		aout.name = 'Consortium' AND
		perm.code IN (
			'CREATE_COPY_TRANSIT',
			'VIEW_BILLING_TYPE',
			'VIEW_CIRCULATIONS',
			'VIEW_COPY_NOTES',
			'VIEW_HOLD',
			'VIEW_ORG_SETTINGS',
			'VIEW_TITLE_NOTES',
			'VIEW_TRANSACTION',
			'VIEW_USER',
			'VIEW_USER_FINES_SUMMARY',
			'VIEW_USER_TRANSACTIONS',
			'VIEW_VOLUME_NOTES',
			'VIEW_ZIP_DATA'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Data Review' AND
		aout.name = 'System' AND
		perm.code IN (
			'COPY_CHECKOUT',
			'COPY_HOLDS',
			'CREATE_IN_HOUSE_USE',
			'CREATE_TRANSACTION',
			'OFFLINE_EXECUTE',
			'OFFLINE_VIEW',
			'STAFF_LOGIN',
			'VOLUME_HOLDS'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Volunteers' AND
		aout.name = 'Branch' AND
		perm.code IN (
			'COPY_CHECKOUT',
			'CREATE_BILL',
			'CREATE_IN_HOUSE_USE',
			'CREATE_PAYMENT',
			'VIEW_BILLING_TYPE',
			'VIEW_CIRCS',
			'VIEW_COPY_CHECKOUT',
			'VIEW_HOLD',
			'VIEW_TITLE_HOLDS',
			'VIEW_TRANSACTION',
			'VIEW_USER',
			'VIEW_USER_FINES_SUMMARY',
			'VIEW_USER_TRANSACTIONS'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Volunteers' AND
		aout.name = 'Consortium' AND
		perm.code IN (
			'CREATE_COPY_TRANSIT',
			'CREATE_TRANSACTION',
			'CREATE_TRANSIT',
			'STAFF_LOGIN',
			'TRANSIT_COPY',
			'VIEW_ORG_SETTINGS'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);


-- stock Users group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Users' AND
		aout.name = 'Consortium' AND
		perm.code IN (
			'CREATE_PURCHASE_REQUEST'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

-- stock Staff group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Staff' AND
		aout.name = 'Consortium' AND
		perm.code IN (
			'VIEW_USER_SETTING_TYPE'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

-- stock Circulators group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Circulators' AND
		aout.name = 'Branch' AND
		perm.code IN (
			'MARK_ITEM_MISSING_PIECES'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

-- stock Catalogers group
INSERT INTO permission.grp_perm_map (grp, perm, depth, grantable)
	SELECT
		pgt.id, perm.id, aout.depth, FALSE
	FROM
		permission.grp_tree pgt,
		permission.perm_list perm,
		actor.org_unit_type aout
	WHERE
		pgt.name = 'Catalogers' AND
		aout.name = 'System' AND
		perm.code IN (
			'MAP_MONOGRAPH_PART'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

-- stock Acquisitions group
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
			'UPDATE_PICKLIST'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

-- stock Acq Admin group
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
			'UPDATE_PICKLIST'
		) AND NOT EXISTS (
			SELECT 1
			FROM permission.grp_perm_map AS map
			WHERE
				map.grp = pgt.id
				AND map.perm = perm.id
		);

COMMIT;
