BEGIN;

SELECT evergreen.upgrade_deps_block_check('1009', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype, fm_class ) VALUES
( 'acq.copy_status_on_receiving', 'acq',
    oils_i18n_gettext('acq.copy_status_on_receiving',
        'Initial status for received items',
        'coust', 'label'),
    oils_i18n_gettext('acq.copy_status_on_receiving',
        'Allows staff to designate a custom copy status on received lineitems.  Default status is "In Process".',
        'coust', 'description'),
    'link', 'ccs');

COMMIT;
