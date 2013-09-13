--
-- Adds a setting for selecting the number of lists per page for my list.
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0830', :eg_version);

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES (
        'opac.lists_per_page',
        TRUE,
        oils_i18n_gettext(
            'opac.lists_per_page',
            'Lists per Page',
            'cust',
            'label'
        ),
        oils_i18n_gettext(
            'opac.lists_per_page',
            'A number designating the amount of lists displayed per page.',
            'cust',
            'description'
        ),
        'string'
    );
    
COMMIT;
