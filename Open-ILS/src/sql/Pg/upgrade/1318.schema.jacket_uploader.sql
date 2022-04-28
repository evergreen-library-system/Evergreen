BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1318', :eg_version);

-- 950.data.seed-values.sql

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'opac.cover_upload_compression',
    0,
    TRUE,
    oils_i18n_gettext(
        'opac.cover_upload_compression',
        'Cover image uploads are converted to PNG files with this compression, on a scale of 0 (no compression) to 9 (maximum compression), or -1 for the zlib default.',
        'cgf', 'label'
    )
);

INSERT INTO config.org_unit_setting_type (name, label, grp, description, datatype)
VALUES (
    'opac.cover_upload_max_file_size',
    oils_i18n_gettext('opac.cover_upload_max_file_size',
        'Maximum file size for uploaded cover image files (at time of upload, prior to rescaling).',
        'coust', 'label'),
    'opac',
    oils_i18n_gettext('opac.cover_upload_max_file_size',
        'The number of bytes to allow for a cover image upload.  If unset, defaults to 10737418240 (roughly 10GB).',
        'coust', 'description'),
    'integer'
);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 637, 'UPLOAD_COVER_IMAGE', oils_i18n_gettext(637,
    'Upload local cover images for added content.', 'ppl', 'description'))
;

COMMIT;
