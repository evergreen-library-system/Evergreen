BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('XXX');

INSERT INTO config.usr_setting_type 
( name, opac_visible, label, description, datatype) VALUES 
( 'circ.collections.exempt',
  FALSE, 
  oils_i18n_gettext('circ.collections.exempt', 'Collections: Exempt', 'cust', 'description'),
  oils_i18n_gettext('circ.collections.exempt', 'User is exempt from collections tracking/processing', 'cust', 'description'),
  'bool'
);

COMMIT;

