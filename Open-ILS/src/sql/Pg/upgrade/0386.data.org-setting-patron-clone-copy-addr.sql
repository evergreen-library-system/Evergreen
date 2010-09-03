BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0386');

INSERT INTO config.org_unit_setting_type ( name, label, description, datatype ) VALUES (
        'circ.patron_edit.clone.copy_address',
        oils_i18n_gettext(
            'circ.patron_edit.clone.copy_address',
            'Patron Registration: Cloned patrons get address copy',
            'coust', 
            'label'
        ),
        oils_i18n_gettext(
            'circ.patron_edit.clone.copy_address',
            'In the Patron editor, copy addresses from the cloned user instead of linking directly to the address',
            'coust', 
            'description'
        ),
        'bool'
);

COMMIT;
