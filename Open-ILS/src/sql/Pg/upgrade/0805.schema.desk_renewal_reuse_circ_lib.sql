BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0805', :eg_version);

INSERT INTO config.global_flag (name, label, enabled)
    VALUES (
        'circ.desk_renewal.use_original_circ_lib',
        oils_i18n_gettext(
            'circ.desk_renewal.use_original_circ_lib',
            'Circ: Use original circulation library on desk renewal instead of user home library',
            'cgf',
            'label'
        ),
        FALSE
    );

COMMIT;
