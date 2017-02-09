BEGIN;

SELECT evergreen.upgrade_deps_block_check('1008', :eg_version);

CREATE OR REPLACE FUNCTION evergreen.unaccent_and_squash ( IN arg text) RETURNS text
    IMMUTABLE STRICT AS $$
	BEGIN
	RETURN evergreen.lowercase(unaccent(regexp_replace(arg, '[\s[:punct:]]','','g')));
	END;
$$ LANGUAGE PLPGSQL;

-- Upon upgrade, we need to
-- reindex because the definition of the unaccent_and_squash function
-- has changed.
REINDEX INDEX actor.actor_usr_first_given_name_unaccent_idx;
REINDEX INDEX actor.actor_usr_second_given_name_unaccent_idx;
REINDEX INDEX actor.actor_usr_family_name_unaccent_idx;

COMMIT;


