BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT INTO config.global_flag (name, enabled, value, label) 
    VALUES (
        'search.max_suggestion_search_terms',
        TRUE,
        3,
        oils_i18n_gettext(
            'search.max_suggestion_search_terms',
            'Limit suggestion generation to searches with this many terms or less',
            'cgf',
            'label'
        )
    );

COMMIT;

/* UNDO
BEGIN;
DELETE FROM config.global_flag WHERE name = 'search.max_suggestion_search_terms';
COMMIT;
*/

