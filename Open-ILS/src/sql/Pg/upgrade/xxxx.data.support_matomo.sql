       BEGIN;

       SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

       INSERT into config.org_unit_setting_type
       ( name, grp, label, description, datatype, fm_class ) VALUES
      ( 'opac.analytics.matomo_id', 'opac',
          oils_i18n_gettext('opac.analytics.matomo_id',
               'Requires the Matomo ID',
               'coust', 'label'),
          oils_i18n_gettext('opac.analytics.matomo_id',
               'Requires the Matomo ID',
               'coust', 'description'),
          'string', NULL),
      ( 'opac.analytics.matomo_url', 'opac',
          oils_i18n_gettext('opac.analytics.matomo_url',
               'Requires the url to the Matomo software',
               'coust', 'label'),
          oils_i18n_gettext('opac.analytics.matomo_url',
               'Requires the url to the Matomo software',
               'coust', 'description'),
          'string', NULL)
      ;

      INSERT INTO permission.perm_list ( id, code, description ) VALUES
      ( 623, 'UPDATE_ORG_UNIT_SETTING.opac.analytics.use_matomo', oils_i18n_gettext(623,
         'Set OPAC to use Matomo tracking', 'ppl', 'description')),
      ;

      UPDATE config.org_unit_setting_type SET update_perm = 623 WHERE name = 'opac.analytics.matomo_id';            
      UPDATE config.org_unit_setting_type SET update_perm = 623 WHERE name = 'opac.analytics.matomo_url';

      COMMIT;

