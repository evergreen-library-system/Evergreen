BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1377', :eg_version);

-- 950.data.seed-values.sql

INSERT INTO config.global_flag (name, value, enabled, label)
VALUES (
    'opac.login_redirect_domains',
    '',
    TRUE,
    oils_i18n_gettext(
        'opac.login_redirect_domains',
        'Restrict post-login redirection to local URLs, or those that match the supplied comma-separated list of foreign domains or host names.',
        'cgf', 'label'
    )
);

COMMIT;

