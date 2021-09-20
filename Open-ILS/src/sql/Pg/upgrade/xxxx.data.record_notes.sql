BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);


ALTER TABLE biblio.record_note ADD COLUMN deleted BOOLEAN DEFAULT FALSE;

INSERT INTO permission.perm_list ( id, code, description ) VALUES
( 633, 'CREATE_RECORD_NOTE', oils_i18n_gettext(633,
   'Allow the user to create a record note', 'ppl', 'description')),
( 634, 'UPDATE_RECORD_NOTE', oils_i18n_gettext(634,
   'Allow the user to update a record note', 'ppl', 'description')),
( 635, 'DELETE_RECORD_NOTE', oils_i18n_gettext(635,
   'Allow the user to delete a record note', 'ppl', 'description'));

INSERT INTO config.workstation_setting_type (name, grp, datatype, label)
VALUES (
    'eg.grid.catalog.record.notes', 'gui', 'object',
    oils_i18n_gettext(
        'eg.grid.catalog.record.notes',
        'Grid Config: eg.grid.catalog.record.notes',
        'cwst', 'label'
    )
);

COMMIT;
