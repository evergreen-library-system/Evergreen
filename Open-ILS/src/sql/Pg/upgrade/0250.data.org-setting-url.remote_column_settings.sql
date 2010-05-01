BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0250'); -- phasefx

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'url.remote_column_settings',
        oils_i18n_gettext(
            'url.remote_column_settings',
            'GUI: URL for remote directory containing list column settings.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'url.remote_column_settings',
            'GUI: URL for remote directory containing list column settings.  The format and naming convention for the files found in this directory match those in the local settings directory for a given workstation.  An administrator could create the desired settings locally and then copy all the tree_columns_for_* files to the remote directory.', 
            'coust', 
            'description'),
        'string'
);

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'gui.disable_local_save_columns',
        oils_i18n_gettext(
            'gui.disable_local_save_columns',
            'GUI: Disable the ability to save list column configurations locally.', 
            'coust', 
            'label'),
        oils_i18n_gettext(
            'gui.disable_local_save_columns',
            'GUI: Disable the ability to save list column configurations locally.  If set, columns may still be manipulated, however, the changes do not persist.  Also, existing local configurations are ignored if this setting is true.', 
            'coust', 
            'description'),
        'bool'
);


COMMIT;
