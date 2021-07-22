BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

DO $$
BEGIN

  PERFORM FROM config.usr_setting_type WHERE name = 'circ.collections.exempt';

  IF NOT FOUND THEN

    INSERT INTO config.usr_setting_type (
      name,
      opac_visible,
      label,
      description,
      datatype,
      reg_default
    ) VALUES (
      'circ.collections.exempt',
      FALSE,
      oils_i18n_gettext(
        'circ.collections.exempt',
        'Collections: Exempt',
        'cust',
        'label'
      ),
      oils_i18n_gettext(
        'circ.collections.exempt',
        'User is exempt from collections tracking/processing',
        'cust',
        'description'
      ),
      'bool',
      'false'
    );

  END IF;

END
$$;

COMMIT;
