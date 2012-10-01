BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.org_unit_setting_type
    (name, grp, label, description, datatype)
    VALUES
        ('circ.void_lost_on_claimsreturned',
         'circ',
         oils_i18n_gettext('circ.void_lost_on_claimsreturned',
             'Void lost item billing when claims returned',
             'coust', 'label'),
         oils_i18n_gettext('circ.void_lost_on_claimsreturned',
             'Void lost item billing when claims returned',
             'coust', 'description'),
         'bool');

COMMIT;
