BEGIN;

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

COMMIT;
