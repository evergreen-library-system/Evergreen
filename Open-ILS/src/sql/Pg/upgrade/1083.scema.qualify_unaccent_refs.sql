-- Evergreen DB patch XXXX.schema.qualify_unaccent_refs.sql
--
-- LP#1671150 Fix unaccent() function call in evergreen.unaccent_and_squash()
--
BEGIN;


-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('1083', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.unaccent_and_squash ( IN arg text) RETURNS text
    IMMUTABLE STRICT AS $$
        BEGIN
        RETURN evergreen.lowercase(public.unaccent('public.unaccent', regexp_replace(arg, '[\s[:punct:]]','','g')));
        END;
$$ LANGUAGE PLPGSQL;

-- Drop indexes if present, so that we can re-create them
DROP INDEX IF EXISTS actor.actor_usr_first_given_name_unaccent_idx;
DROP INDEX IF EXISTS actor.actor_usr_second_given_name_unaccent_idx;
DROP INDEX IF EXISTS actor.actor_usr_family_name_unaccent_idx; 
DROP INDEX IF EXISTS actor.actor_usr_usrname_unaccent_idx; 

-- Create (or re-create) indexes -- they may be missing if pg_restore failed to create
-- them due to the previously unqualified call to unaccent()
CREATE INDEX actor_usr_first_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(first_given_name));
CREATE INDEX actor_usr_second_given_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(second_given_name));
CREATE INDEX actor_usr_family_name_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(family_name));
CREATE INDEX actor_usr_usrname_unaccent_idx ON actor.usr (evergreen.unaccent_and_squash(usrname));

COMMIT;
