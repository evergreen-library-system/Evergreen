BEGIN;

SELECT evergreen.upgrade_deps_block_check('0542', :eg_version); -- phasefx

INSERT INTO permission.perm_list VALUES
    (485, 'CREATE_VOLUME_SUFFIX', oils_i18n_gettext(485, 'Create suffix label definition.', 'ppl', 'description'))
    ,(486, 'UPDATE_VOLUME_SUFFIX', oils_i18n_gettext(486, 'Update suffix label definition.', 'ppl', 'description'))
    ,(487, 'DELETE_VOLUME_SUFFIX', oils_i18n_gettext(487, 'Delete suffix label definition.', 'ppl', 'description'))
    ,(488, 'CREATE_VOLUME_PREFIX', oils_i18n_gettext(488, 'Create prefix label definition.', 'ppl', 'description'))
    ,(489, 'UPDATE_VOLUME_PREFIX', oils_i18n_gettext(489, 'Update prefix label definition.', 'ppl', 'description'))
    ,(490, 'DELETE_VOLUME_PREFIX', oils_i18n_gettext(490, 'Delete prefix label definition.', 'ppl', 'description'))
    ,(491, 'CREATE_MONOGRAPH_PART', oils_i18n_gettext(491, 'Create monograph part definition.', 'ppl', 'description'))
    ,(492, 'UPDATE_MONOGRAPH_PART', oils_i18n_gettext(492, 'Update monograph part definition.', 'ppl', 'description'))
    ,(493, 'DELETE_MONOGRAPH_PART', oils_i18n_gettext(493, 'Delete monograph part definition.', 'ppl', 'description'))
;

COMMIT;
