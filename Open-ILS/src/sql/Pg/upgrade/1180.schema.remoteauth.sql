BEGIN;

SELECT evergreen.upgrade_deps_block_check('1180', :eg_version);

INSERT INTO permission.perm_list ( id, code, description ) VALUES
 ( 615, 'ADMIN_REMOTEAUTH', oils_i18n_gettext( 615,
    'Administer remote patron authentication', 'ppl', 'description' ));

CREATE TABLE config.remoteauth_profile (
    name TEXT PRIMARY KEY,
    description TEXT,
    context_org INT NOT NULL REFERENCES actor.org_unit(id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    perm INT NOT NULL REFERENCES permission.perm_list(id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    restrict_to_org BOOLEAN NOT NULL DEFAULT TRUE,
    allow_inactive BOOL NOT NULL DEFAULT FALSE,
    allow_expired BOOL NOT NULL DEFAULT FALSE,
    block_list TEXT,
    usr_activity_type INT REFERENCES config.usr_activity_type(id) ON UPDATE CASCADE ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED
);

CREATE OR REPLACE FUNCTION actor.permit_remoteauth (profile_name TEXT, userid BIGINT) RETURNS TEXT AS $func$
DECLARE
    usr               actor.usr%ROWTYPE;
    profile           config.remoteauth_profile%ROWTYPE;
    perm              TEXT;
    context_org_list  INT[];
    home_prox         INT;
    block             TEXT;
    penalty_count     INT;
BEGIN

    SELECT INTO usr * FROM actor.usr WHERE id = userid AND NOT deleted;
    IF usr IS NULL THEN
        RETURN 'not_found';
    END IF;

    IF usr.barred IS TRUE THEN
        RETURN 'blocked';
    END IF;

    SELECT INTO profile * FROM config.remoteauth_profile WHERE name = profile_name;
    SELECT INTO context_org_list ARRAY_AGG(id) FROM actor.org_unit_full_path( profile.context_org );

    -- user's home library must be within the context org
    IF profile.restrict_to_org IS TRUE AND usr.home_ou NOT IN (SELECT * FROM UNNEST(context_org_list)) THEN
        RETURN 'not_found';
    END IF;

    SELECT INTO perm code FROM permission.perm_list WHERE id = profile.perm;
    IF permission.usr_has_perm(usr.id, perm, profile.context_org) IS FALSE THEN
        RETURN 'not_found';
    END IF;
    
    IF usr.expire_date < NOW() AND profile.allow_expired IS FALSE THEN
        RETURN 'expired';
    END IF;

    IF usr.active IS FALSE AND profile.allow_inactive IS FALSE THEN
        RETURN 'blocked';
    END IF;

    -- Proximity of user's home_ou to context_org to see if penalties should be ignored.
    SELECT INTO home_prox prox FROM actor.org_unit_proximity WHERE from_org = usr.home_ou AND to_org = profile.context_org;

    -- Loop through the block list to see if the user has any matching penalties.
    IF profile.block_list IS NOT NULL THEN
        FOR block IN SELECT UNNEST(STRING_TO_ARRAY(profile.block_list, '|')) LOOP
            SELECT INTO penalty_count COUNT(DISTINCT csp.*)
                FROM  actor.usr_standing_penalty usp
                        JOIN config.standing_penalty csp ON (csp.id = usp.standing_penalty)
                WHERE usp.usr = usr.id
                        AND usp.org_unit IN ( SELECT * FROM UNNEST(context_org_list) )
                        AND ( usp.stop_date IS NULL or usp.stop_date > NOW() )
                        AND ( csp.ignore_proximity IS NULL OR csp.ignore_proximity < home_prox )
                        AND csp.block_list ~ block;
            IF penalty_count > 0 THEN
                -- User has penalties that match this block, so auth is not permitted.
                -- Don't bother testing the rest of the block list.
                RETURN 'blocked';
            END IF;
        END LOOP;
    END IF;

    -- User has passed all tests.
    RETURN 'success';

END;
$func$ LANGUAGE plpgsql;

COMMIT;

