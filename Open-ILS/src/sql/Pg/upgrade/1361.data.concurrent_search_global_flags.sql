BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1361', :eg_version);

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'opac.max_concurrent_search.query',
    '20',
    TRUE,
    oils_i18n_gettext(
        'opac.max_concurrent_search.query',
        'Limit the number of global concurrent matching search queries',
        'cgf', 'label'
    )
);

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'opac.max_concurrent_search.ip',
    '0',
    TRUE,
    oils_i18n_gettext(
        'opac.max_concurrent_search.ip',
        'Limit the number of global concurrent searches per client IP address',
        'cgf', 'label'
    )
);

COMMIT;

