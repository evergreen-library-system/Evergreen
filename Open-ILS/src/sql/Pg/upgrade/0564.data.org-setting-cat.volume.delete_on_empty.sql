-- Evergreen DB patch 0564.data.delete_empty_volume.sql
--
-- New org setting cat.volume.delete_on_empty
--
BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0564', :eg_version);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) 
    VALUES ( 
        'cat.volume.delete_on_empty',
        oils_i18n_gettext('cat.volume.delete_on_empty', 'Cat: Delete volume with last copy', 'coust', 'label'),
        oils_i18n_gettext('cat.volume.delete_on_empty', 'Automatically delete a volume when the last linked copy is deleted', 'coust', 'description'),
        'bool'
    );


COMMIT;
