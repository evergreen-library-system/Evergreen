BEGIN;

SELECT evergreen.upgrade_deps_block_check('1460', :eg_version); -- JBoyer

-- Note: the value will not be consistent from system to system. It's an opaque key that has no meaning of its own,
-- if the value cached in the client does not match or is missing, it clears some cached values and then saves the current value.
INSERT INTO config.global_flag (name, label, value, enabled) VALUES (
    'staff.client_cache_key',
    oils_i18n_gettext(
        'staff.client_cache_key',
        'Change this value to force staff clients to clear some cached values',
        'cgf',
        'label'
    ),
    md5(random()::text),
    TRUE
);

COMMIT;
