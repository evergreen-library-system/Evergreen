-- Evergreen DB patch XXXX.data.acq-copy-creator-from-receiver.sql
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0610', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
    'acq.copy_creator_uses_receiver',
    oils_i18n_gettext( 
        'acq.copy_creator_uses_receiver',
        'Acq: Set copy creator as receiver',
        'coust',
        'label'
    ),
    oils_i18n_gettext( 
        'acq.copy_creator_uses_receiver',
        'When receiving a copy in acquisitions, set the copy "creator" to be the staff that received the copy',
        'coust',
        'label'
    ),
    'bool'
);

COMMIT;
