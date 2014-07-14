BEGIN;

SELECT evergreen.upgrade_deps_block_check('0886', :eg_version);

INSERT INTO config.copy_status
(id, name, holdable, opac_visible, copy_active, restrict_copy_delete)
VALUES (17, 'Lost and Paid', FALSE, FALSE, FALSE, TRUE);

INSERT INTO config.org_unit_setting_type
(name, grp, label, description, datatype)
VALUES
('circ.use_lost_paid_copy_status',
 'circ',
 oils_i18n_gettext('circ.use_lost_paid_copy_status',
     'Use Lost and Paid copy status',
     'coust', 'label'),
 oils_i18n_gettext('circ.use_lost_paid_copy_status',
     'Use Lost and Paid copy status when lost or long overdue billing is paid',
     'coust', 'description'),
 'bool');

COMMIT;
