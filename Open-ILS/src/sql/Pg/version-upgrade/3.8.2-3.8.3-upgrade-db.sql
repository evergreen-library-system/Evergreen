--Upgrade Script for 3.8.2 to 3.8.3
\set eg_version '''3.8.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.8.3', :eg_version);

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

-- Update auditor tables to catch changes to source tables.
--   Can be removed/skipped if there were no schema changes.
SELECT auditor.update_auditors();
