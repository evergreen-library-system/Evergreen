BEGIN;

SELECT evergreen.upgrade_deps_block_check('1067', :eg_version);

INSERT INTO acq.edi_attr (key, label) VALUES
    ('INCLUDE_PO_NAME', 
        oils_i18n_gettext('INCLUDE_PO_NAME', 
        'Orders Include PO Name', 'aea', 'label')),
    ('INCLUDE_COPIES', 
        oils_i18n_gettext('INCLUDE_COPIES', 
        'Orders Include Copy Data', 'aea', 'label')),
    ('INCLUDE_FUND', 
        oils_i18n_gettext('INCLUDE_FUND', 
        'Orders Include Copy Funds', 'aea', 'label')),
    ('INCLUDE_CALL_NUMBER', 
        oils_i18n_gettext('INCLUDE_CALL_NUMBER', 
        'Orders Include Copy Call Numbers', 'aea', 'label')),
    ('INCLUDE_ITEM_TYPE', 
        oils_i18n_gettext('INCLUDE_ITEM_TYPE', 
        'Orders Include Copy Item Types', 'aea', 'label')),
    ('INCLUDE_ITEM_BARCODE',
        oils_i18n_gettext('INCLUDE_ITEM_BARCODE',
        'Orders Include Copy Barcodes', 'aea', 'label')),
    ('INCLUDE_LOCATION', 
        oils_i18n_gettext('INCLUDE_LOCATION', 
        'Orders Include Copy Locations', 'aea', 'label')),
    ('INCLUDE_COLLECTION_CODE', 
        oils_i18n_gettext('INCLUDE_COLLECTION_CODE', 
        'Orders Include Copy Collection Codes', 'aea', 'label')),
    ('INCLUDE_OWNING_LIB', 
        oils_i18n_gettext('INCLUDE_OWNING_LIB', 
        'Orders Include Copy Owning Library', 'aea', 'label')),
    ('USE_ID_FOR_OWNING_LIB',
        oils_i18n_gettext('USE_ID_FOR_OWNING_LIB',
        'Emit Owning Library ID Rather Than Short Name. Takes effect only if INCLUDE_OWNING_LIB is in use', 'aea', 'label')),
    ('INCLUDE_QUANTITY', 
        oils_i18n_gettext('INCLUDE_QUANTITY', 
        'Orders Include Copy Quantities', 'aea', 'label')),
    ('INCLUDE_COPY_ID', 
        oils_i18n_gettext('INCLUDE_COPY_ID', 
        'Orders Include Copy IDs', 'aea', 'label')),
    ('BUYER_ID_INCLUDE_VENDCODE', 
        oils_i18n_gettext('BUYER_ID_INCLUDE_VENDCODE', 
        'Buyer ID Qualifier Includes Vendcode', 'aea', 'label')),
    ('BUYER_ID_ONLY_VENDCODE', 
        oils_i18n_gettext('BUYER_ID_ONLY_VENDCODE', 
        'Buyer ID Qualifier Only Contains Vendcode', 'aea', 'label')),
    ('INCLUDE_BIB_EDITION', 
        oils_i18n_gettext('INCLUDE_BIB_EDITION', 
        'Order Lineitems Include Edition Info', 'aea', 'label')),
    ('INCLUDE_BIB_AUTHOR', 
        oils_i18n_gettext('INCLUDE_BIB_AUTHOR', 
        'Order Lineitems Include Author Info', 'aea', 'label')),
    ('INCLUDE_BIB_PAGINATION', 
        oils_i18n_gettext('INCLUDE_BIB_PAGINATION', 
        'Order Lineitems Include Pagination Info', 'aea', 'label')),
    ('COPY_SPEC_CODES', 
        oils_i18n_gettext('COPY_SPEC_CODES', 
        'Order Lineitem Notes Include Copy Spec Codes', 'aea', 'label')),
    ('INCLUDE_EMPTY_IMD_VALUES', 
        oils_i18n_gettext('INCLUDE_EMPTY_IMD_VALUES',
        'Lineitem Title, Author, etc. Fields Are Present Even if Empty', 'aea', 'label')),
    ('INCLUDE_EMPTY_LI_NOTE', 
        oils_i18n_gettext('INCLUDE_EMPTY_LI_NOTE', 
        'Order Lineitem Notes Always Present (Even if Empty)', 'aea', 'label')),
    ('INCLUDE_EMPTY_CALL_NUMBER', 
        oils_i18n_gettext('INCLUDE_EMPTY_CALL_NUMBER', 
        'Order Copies Always Include Call Number (Even if Empty)', 'aea', 'label')),
    ('INCLUDE_EMPTY_ITEM_TYPE', 
        oils_i18n_gettext('INCLUDE_EMPTY_ITEM_TYPE', 
        'Order Copies Always Include Item Type (Even if Empty)', 'aea', 'label')),
    ('INCLUDE_EMPTY_LOCATION', 
        oils_i18n_gettext('INCLUDE_EMPTY_LOCATION', 
        'Order Copies Always Include Location (Even if Empty)', 'aea', 'label')),
    ('INCLUDE_EMPTY_COLLECTION_CODE', 
        oils_i18n_gettext('INCLUDE_EMPTY_COLLECTION_CODE', 
        'Order Copies Always Include Collection Code (Even if Empty)', 'aea', 'label')),
    ('LINEITEM_IDENT_VENDOR_NUMBER',
        oils_i18n_gettext('LINEITEM_IDENT_VENDOR_NUMBER',
        'Lineitem Identifier Fields (LIN/PIA) Use Vendor-Encoded ID Value When Available', 'aea', 'label')),
    ('LINEITEM_REF_ID_ONLY',
        oils_i18n_gettext('LINEITEM_REF_ID_ONLY',
        'Lineitem Reference Field (RFF) Uses Lineitem ID Only', 'aea', 'label'))

;

INSERT INTO acq.edi_attr_set (id, label) VALUES (1, 'Ingram Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (2, 'Baker & Taylor Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (3, 'Brodart Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (4, 'Midwest Tape Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (5, 'ULS Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (6, 'Recorded Books Default');
INSERT INTO acq.edi_attr_set (id, label) VALUES (7, 'Midwest Library Service');

-- carve out space for mucho defaults
SELECT SETVAL('acq.edi_attr_set_id_seq'::TEXT, 1000);

INSERT INTO acq.edi_attr_set_map (attr_set, attr) VALUES

    -- Ingram
    (1, 'INCLUDE_PO_NAME'),
    (1, 'INCLUDE_COPIES'),
    (1, 'INCLUDE_ITEM_TYPE'),
    (1, 'INCLUDE_COLLECTION_CODE'),
    (1, 'INCLUDE_OWNING_LIB'),
    (1, 'INCLUDE_QUANTITY'),
    (1, 'INCLUDE_BIB_PAGINATION'),

    -- B&T
    (2, 'INCLUDE_COPIES'),
    (2, 'INCLUDE_ITEM_TYPE'),
    (2, 'INCLUDE_COLLECTION_CODE'),
    (2, 'INCLUDE_CALL_NUMBER'),
    (2, 'INCLUDE_OWNING_LIB'),
    (2, 'INCLUDE_QUANTITY'),
    (2, 'INCLUDE_BIB_PAGINATION'),
    (2, 'BUYER_ID_INCLUDE_VENDCODE'),
    (2, 'INCLUDE_EMPTY_LI_NOTE'),
    (2, 'INCLUDE_EMPTY_CALL_NUMBER'),
    (2, 'INCLUDE_EMPTY_ITEM_TYPE'),
    (2, 'INCLUDE_EMPTY_COLLECTION_CODE'),
    (2, 'INCLUDE_EMPTY_LOCATION'),
    (2, 'LINEITEM_IDENT_VENDOR_NUMBER'),
    (2, 'LINEITEM_REF_ID_ONLY'),

    -- Brodart
    (3, 'INCLUDE_COPIES'),
    (3, 'INCLUDE_FUND'),
    (3, 'INCLUDE_ITEM_TYPE'),
    (3, 'INCLUDE_COLLECTION_CODE'),
    (3, 'INCLUDE_OWNING_LIB'),
    (3, 'INCLUDE_QUANTITY'),
    (3, 'INCLUDE_BIB_PAGINATION'),
    (3, 'COPY_SPEC_CODES'),

    -- Midwest
    (4, 'INCLUDE_COPIES'),
    (4, 'INCLUDE_FUND'),
    (4, 'INCLUDE_OWNING_LIB'),
    (4, 'INCLUDE_QUANTITY'),
    (4, 'INCLUDE_BIB_PAGINATION'),

    -- ULS
    (5, 'INCLUDE_COPIES'),
    (5, 'INCLUDE_ITEM_TYPE'),
    (5, 'INCLUDE_COLLECTION_CODE'),
    (5, 'INCLUDE_OWNING_LIB'),
    (5, 'INCLUDE_QUANTITY'),
    (5, 'INCLUDE_BIB_AUTHOR'),
    (5, 'INCLUDE_BIB_EDITION'),
    (5, 'INCLUDE_EMPTY_LI_NOTE'),

    -- Recorded Books
    (6, 'INCLUDE_COPIES'),
    (6, 'INCLUDE_ITEM_TYPE'),
    (6, 'INCLUDE_COLLECTION_CODE'),
    (6, 'INCLUDE_OWNING_LIB'),
    (6, 'INCLUDE_QUANTITY'),
    (6, 'INCLUDE_BIB_PAGINATION'),

    -- Midwest Library Service
    (7, 'INCLUDE_BIB_AUTHOR'),
    (7, 'INCLUDE_BIB_EDITION'),
    (7, 'BUYER_ID_ONLY_VENDCODE'),
    (7, 'INCLUDE_EMPTY_IMD_VALUES')
;


COMMIT;


