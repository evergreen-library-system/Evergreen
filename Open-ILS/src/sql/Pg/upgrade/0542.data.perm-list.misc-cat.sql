BEGIN;

SELECT evergreen.upgrade_deps_block_check('0542', :eg_version); -- phasefx

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

-- stock Staff group

INSERT INTO permission.grp_perm_map ( grp, perm, depth )
    SELECT
        3,
        id,
        0
    FROM permission.perm_list
    WHERE code in (
        'CREATE_PURCHASE_REQUEST'
        ,'VIEW_USER_SETTING_TYPE'
    );


-- stock Circulators group

INSERT INTO permission.grp_perm_map ( grp, perm, depth )
    SELECT
        5,
        id,
        0
    FROM permission.perm_list
    WHERE code in (
        'MARK_ITEM_MISSING_PIECES'
    );

--- stock Circulation Administrator group

INSERT INTO permission.grp_perm_map ( grp, perm, depth, grantable )
    SELECT
        4,
        id,
        0,
        't'
    FROM permission.perm_list
    WHERE code in (
        'MARK_ITEM_MISSING_PIECES'
        ,'UPDATE_HOLD_REQUEST_TIME'
    );

-- stock Catalogers group

INSERT INTO permission.grp_perm_map ( grp, perm, depth )
    SELECT
        5,
        id,
        0
    FROM permission.perm_list
    WHERE code in (
        'MAP_MONOGRAPH_PART'
        ,'ADMIN_SERIAL_ITEM'
    );

-- stock Cataloging Administrator group

INSERT INTO permission.grp_perm_map ( grp, perm, depth, grantable )
    SELECT
        8,
        id,
        0,
        't'
    FROM permission.perm_list
    WHERE code in (
        'MAP_MONOGRAPH_PART'
        ,'ADMIN_SERIAL_ITEM'
        ,'CREATE_VOLUME_SUFFIX'
        ,'UPDATE_VOLUME_SUFFIX'
        ,'DELETE_VOLUME_SUFFIX'
        ,'CREATE_VOLUME_PREFIX'
        ,'UPDATE_VOLUME_PREFIX'
        ,'DELETE_VOLUME_PREFIX'
        ,'CREATE_MONOGRAPH_PART'
        ,'UPDATE_MONOGRAPH_PART'
        ,'DELETE_MONOGRAPH_PART'
        ,'CREATE_BIB_PTYPE'
        ,'UPDATE_BIB_PTYPE'
        ,'DELETE_BIB_PTYPE'
    );

-- stock Serials group

INSERT INTO permission.grp_perm_map ( grp, perm, depth )
    SELECT
        11,
        id,
        0
    FROM permission.perm_list
    WHERE code in (
        'ADMIN_SERIAL_ITEM'
    );


-- stock Acquisitions group

INSERT INTO permission.grp_perm_map ( grp, perm, depth )
    SELECT
        7,
        id,
        0
    FROM permission.perm_list
    WHERE code in (
        'UPDATE_PICKLIST'
    );

--- stock Acquisitions Administrator group

INSERT INTO permission.grp_perm_map ( grp, perm, depth, grantable )
    SELECT
        8,
        id,
        0,
        't'
    FROM permission.perm_list
    WHERE code in (
        'UPDATE_PICKLIST'
    );

--- stock Local Administrator group

INSERT INTO permission.grp_perm_map ( grp, perm, depth, grantable )
    SELECT
        10,
        id,
        2,
        't'
    FROM permission.perm_list
    WHERE code in (
        'UPDATE_WORKSTATION'
    );

--- stock System Administrator group

INSERT INTO permission.grp_perm_map ( grp, perm, depth, grantable )
    SELECT
        11,
        id,
        1,
        't'
    FROM permission.perm_list
    WHERE code in (
        'UPDATE_WORKSTATION'
    );

--- stock Global Administrator group

INSERT INTO permission.grp_perm_map ( grp, perm, depth, grantable )
    SELECT
        12,
        id,
        0,
        't'
    FROM permission.perm_list
    WHERE code in (
        'UPDATE_WORKSTATION'
        ,'ADMIN_SVF'
        ,'ADMIN_CODED_VALUE'
    );

COMMIT;
