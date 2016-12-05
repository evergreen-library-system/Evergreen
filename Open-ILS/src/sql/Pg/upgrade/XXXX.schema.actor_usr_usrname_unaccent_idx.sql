BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version); -- csharp/miker

CREATE INDEX actor_usr_usrname_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(usrname));


COMMIT;
