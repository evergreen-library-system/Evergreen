-- Evergreen DB patch 0661.data.yaous-opac-tag-circed-items.sql
--
-- Add org unit setting that enables users who have opted in to
-- tracking their circulation history to see which items they
-- have previously checked out in search results.
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0661', :eg_version);

INSERT into config.org_unit_setting_type 
    (name, grp, label, description, datatype) 
    VALUES ( 
        'opac.search.tag_circulated_items', 
        'opac',
        oils_i18n_gettext(
            'opac.search.tag_circulated_items',
            'Tag Circulated Items in Results',
            'coust', 
            'label'
        ),
        oils_i18n_gettext(
            'opac.search.tag_circulated_items',
            'When a user is both logged in and has opted in to circulation history tracking, turning on this setting will cause previous (or currently) circulated items to be highlighted in search results',
            'coust', 
            'description'
        ),
        'bool'
    );


COMMIT;
