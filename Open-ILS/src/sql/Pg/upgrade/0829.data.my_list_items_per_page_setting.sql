--
-- Adds a setting for selecting the number of items per page of a my list.
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0829', :eg_version);

INSERT INTO config.usr_setting_type (name,opac_visible,label,description,datatype)
    VALUES (
        'opac.list_items_per_page',
        TRUE,
        oils_i18n_gettext(
            'opac.list_items_per_page',
            'List Items per Page',
            'cust',
            'label'
        ),
        oils_i18n_gettext(
            'opac.list_items_per_page',
            'A number designating the amount of list items displayed per page of a selected list.',
            'cust',
            'description'
        ),
        'string'
    );

COMMIT;
