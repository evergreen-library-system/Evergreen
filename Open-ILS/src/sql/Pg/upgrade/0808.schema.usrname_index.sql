-- Evergreen DB patch XXXX.schema.usrname_index.sql
--
-- Create search index on actor.usr.usrname
--
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0808', :eg_version);

CREATE INDEX actor_usr_usrname_idx ON actor.usr (evergreen.lowercase(usrname));

COMMIT;
