-- Evergreen DB patch 0595.data.org-setting-ui.patron_search.result_cap.sql
--
-- New org setting ui.patron_search.result_cap
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0595', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype )
    VALUES (
        'ui.patron_search.result_cap',
        oils_i18n_gettext(
            'ui.patron_search.result_cap',
            'GUI: Cap results in Patron Search at this number.',
            'coust',
            'label'
        ),
        oils_i18n_gettext(
            'ui.patron_search.result_cap',
            'So for example, if you search for John Doe, normally you would get'
            || ' at most 50 results.  This setting allows you to raise or lower'
            || ' that limit.',
            'coust',
            'description'
        ),
        'integer'
    );

COMMIT;
