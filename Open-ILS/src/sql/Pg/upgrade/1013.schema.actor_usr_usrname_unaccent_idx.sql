BEGIN;

SELECT evergreen.upgrade_deps_block_check('1013', :eg_version); -- csharp/miker/gmcharlt

CREATE INDEX actor_usr_usrname_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(usrname));


COMMIT;
