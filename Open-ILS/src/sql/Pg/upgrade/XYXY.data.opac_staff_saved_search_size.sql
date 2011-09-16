-- Evergreen DB patch XYXY.data.opac_staff_saved_search_size.sql

BEGIN;

SELECT evergreen.upgrade_deps_block_check('XYXY', :eg_version);

INSERT into config.org_unit_setting_type (name, grp, label, description, datatype)
VALUES (
    'opac.staff_saved_search.size', 'opac',
    oils_i18n_gettext('opac.staff_saved_search.size',
        'OPAC: Number of staff client saved searches to display on left side of results and record details pages', 'coust', 'label'),
    oils_i18n_gettext('opac.staff_saved_search.size',
        'If unset, the OPAC (only when wrapped in the staff client!) will default to showing you your ten most recent searches on the left side of the results and record details pages.  If you actually don''t want to see this feature at all, set this value to zero at the top of your organizational tree.', 'coust', 'description'),
    'integer'
);

COMMIT;
