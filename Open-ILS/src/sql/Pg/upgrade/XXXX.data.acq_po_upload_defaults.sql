
BEGIN;

-- TODO SET VERSION

INSERT INTO config.org_unit_setting_type
    (name, label, description, grp, datatype, fm_class) VALUES
(
    'acq.upload.default.create_po',
    oils_i18n_gettext(
        'acq.upload.default.create_po',
        'ACQ Upoad Create PO',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.create_po',
        'Create a purchase order by default during ACQ file upload',
        'coust',
        'description'
    ),
   'acq',
    'bool',
    NULL
), (
    'acq.upload.default.activate_po',
    oils_i18n_gettext(
        'acq.upload.default.activate_po',
        'ACQ Upoad Activate PO',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.activate_po',
        'Activate the purchase order by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.provider',
    oils_i18n_gettext(
        'acq.upload.default.provider',
        'ACQ Upoad Default Provider',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.provider',
        'Default provider to use during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'link',
    'acqpro'
), (
    'acq.upload.default.vandelay.match_set',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.match_set',
        'ACQ Upoad Default Match Set',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.match_set',
        'Default match set to use during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'link',
    'vms'
), (
    'acq.upload.default.vandelay.merge_profile',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_profile',
        'ACQ Upoad Default Merge Profile',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_profile',
        'Default merge profile to use during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'link',
    'vmp'
), (
    'acq.upload.default.vandelay.import_non_matching',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.import_non_matching',
        'ACQ Upoad Import Non Matching by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.import_non_matching',
        'Import non-matching records by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.vandelay.merge_on_exact',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_exact',
        'ACQ Upoad Merge on Exact Match by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_exact',
        'Merge records on exact match by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.vandelay.merge_on_best',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_best',
        'ACQ Upoad Merge on Best Match by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_best',
        'Merge records on best match by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.vandelay.merge_on_single',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_single',
        'ACQ Upoad Merge on Single Match by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.merge_on_single',
        'Merge records on single match by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
), (
    'acq.upload.default.vandelay.quality_ratio',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.quality_ratio',
        'ACQ Upoad Default Min. Quality Ratio',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.quality_ratio',
        'Default minimum quality ratio used during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'integer',
    NULL
), (
    'acq.upload.default.vandelay.low_quality_fall_thru_profile',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.low_quality_fall_thru_profile',
        'ACQ Upoad Default Insufficient Quality Fall-Thru Profile',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.low_quality_fall_thru_profile',
        'Default low-quality fall through profile used during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'link',
    'vmp'
), (
    'acq.upload.default.vandelay.load_item_for_imported',
    oils_i18n_gettext(
        'acq.upload.default.vandelay.load_item_for_imported',
        'ACQ Upoad Load Items for Imported Records by Default',
        'coust',
        'label'
    ),
     oils_i18n_gettext(
        'acq.upload.default.vandelay.load_item_for_imported',
        'Load items for imported records by default during ACQ file upload',
        'coust',
        'description'
    ),
    'acq',
    'bool',
    NULL
);

COMMIT;
