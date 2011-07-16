-- Evergreen DB patch 0581.schema.opac_renewal_reuse_circ_lib.sql
--
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0581', :eg_version);

INSERT INTO config.global_flag (name, label, enabled)
    VALUES (
        'circ.opac_renewal.use_original_circ_lib',
        oils_i18n_gettext(
            'circ.opac_renewal.use_original_circ_lib',
            'Circ: Use original circulation library on opac renewal instead of user home library',
            'cgf',
            'label'
        ),
        FALSE
    );


COMMIT;
