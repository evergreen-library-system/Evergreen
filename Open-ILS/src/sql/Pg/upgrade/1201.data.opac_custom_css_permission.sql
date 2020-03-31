BEGIN;

SELECT evergreen.upgrade_deps_block_check('1201', :eg_version); -- rhamby/jboyer

INSERT INTO permission.perm_list ( id, code, description ) VALUES
( 620, 'UPDATE_ORG_UNIT_SETTING.opac.patron.custom_css', oils_i18n_gettext(620,
   'Update CSS setting for the OPAC', 'ppl', 'description'))
;

UPDATE config.org_unit_setting_type SET update_perm = 620 WHERE name = 'opac.patron.custom_css';

COMMIT;
