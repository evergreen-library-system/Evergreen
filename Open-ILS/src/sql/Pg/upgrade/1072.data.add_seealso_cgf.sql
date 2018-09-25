BEGIN;

SELECT evergreen.upgrade_deps_block_check('1072', :eg_version); --gmcharlt/kmlussier

INSERT INTO config.global_flag (name, label, enabled) VALUES (
    'opac.show_related_headings_in_browse',
    oils_i18n_gettext(
        'opac.show_related_headings_in_browse',
        'Display related headings (see-also) in browse',
        'cgf',
        'label'
    ),
    TRUE
);

COMMIT;
