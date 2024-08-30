BEGIN;

SELECT evergreen.upgrade_deps_block_check('1429', :eg_version);

UPDATE config.org_unit_setting_type
SET description = oils_i18n_gettext('circ.course_materials_brief_record_bib_source',
    'The course materials module will use this bib source for any new brief bibliographic records made inside that module. For best results, use a transcendent bib source.',
    'coust', 'description')
WHERE name='circ.course_materials_brief_record_bib_source';

COMMIT;
