BEGIN;

-- SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE INDEX aum_editor ON actor.usr_message (editor);

COMMIT;
