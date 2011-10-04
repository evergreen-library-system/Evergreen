-- Evergreen DB patch 0635.data.opac.jump-to-details-setting.sql
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0635', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, grp, label, description, datatype )
    VALUES (
        'opac.staff.jump_to_details_on_single_hit', 
        'opac',
        oils_i18n_gettext(
            'opac.staff.jump_to_details_on_single_hit',
            'Jump to details on 1 hit (staff client)',
            'coust', 
            'label'
        ),
        oils_i18n_gettext(
            'opac.staff.jump_to_details_on_single_hit',
            'When a search yields only 1 result, jump directly to the record details page.  This setting only affects the OPAC within the staff client',
            'coust', 
            'description'
        ),
        'bool'
    ), (
        'opac.patron.jump_to_details_on_single_hit', 
        'opac',
        oils_i18n_gettext(
            'opac.patron.jump_to_details_on_single_hit',
            'Jump to details on 1 hit (public)',
            'coust', 
            'label'
        ),
        oils_i18n_gettext(
            'opac.patron.jump_to_details_on_single_hit',
            'When a search yields only 1 result, jump directly to the record details page.  This setting only affects the public OPAC',
            'coust', 
            'description'
        ),
        'bool'
    );

COMMIT;
