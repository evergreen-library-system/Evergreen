-- Evergreen DB patch XXXX.data.yaous-opac-tag-circed-items.sql
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

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
            'When a user is both logged in and has opted in to circ history tracking, turning on this setting will cause previous (or currenlty) circulated items to be highlighted in search results',
            'coust', 
            'description'
        ),
        'bool'
    );


COMMIT;
