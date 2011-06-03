BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0547'); -- dbwells

-- account for spelling errors (Admin != Administrator)
\qecho This might not insert much if you passed through 0542 on your way here,
\qecho but one group was missed there as well

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
        pgt.name = 'Cataloging Administrator' AND
        aout.name = 'System' AND
        perm.code IN (
            'CREATE_COPY_STAT_CAT',
            'CREATE_COPY_STAT_CAT_ENTRY',
            'CREATE_COPY_STAT_CAT_ENTRY_MAP',
            'RUN_REPORTS',
            'SHARE_REPORT_FOLDER',
            'UPDATE_COPY_LOCATION',
            'UPDATE_COPY_STAT_CAT',
            'UPDATE_COPY_STAT_CAT_ENTRY',
            'VIEW_REPORT_OUTPUT'
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

COMMIT;
