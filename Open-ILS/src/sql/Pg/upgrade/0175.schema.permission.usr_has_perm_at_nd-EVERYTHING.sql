
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0175'); -- From patch by Jason Stephenson (applied by miker)

CREATE OR REPLACE FUNCTION permission.usr_has_perm_at_nd(
    user_id    IN INTEGER,
    perm_code  IN TEXT
)
RETURNS SETOF INTEGER AS $$
--
-- Return a set of all the org units for which a given user has a given
-- permission, granted directly (not through inheritance from a parent
-- org unit).
--
-- The permissions apply to a minimum depth of the org unit hierarchy,
-- for the org unit(s) to which the user is assigned.  (They also apply
-- to the subordinates of those org units, but we don't report the
-- subordinates here.)
--
-- For purposes of this function, the permission.usr_work_ou_map table
-- defines which users belong to which org units.  I.e. we ignore the
-- home_ou column of actor.usr.
--
-- The result set may contain duplicates, which should be eliminated
-- by a DISTINCT clause.
--
DECLARE
    b_super       BOOLEAN;
    n_perm        INTEGER;
    n_min_depth   INTEGER;
    n_work_ou     INTEGER;
    n_curr_ou     INTEGER;
    n_depth       INTEGER;
    n_curr_depth  INTEGER;
BEGIN
    --
    -- Check for superuser
    --
    SELECT INTO b_super
        super_user
    FROM
        actor.usr
    WHERE
        id = user_id;
    --
    IF NOT FOUND THEN
        return;             -- No user?  No permissions.
    ELSIF b_super THEN
        --
        -- Super user has all permissions everywhere
        --
        FOR n_work_ou IN
            SELECT
                id
            FROM
                actor.org_unit
            WHERE
                parent_ou IS NULL
        LOOP
            RETURN NEXT n_work_ou;
        END LOOP;
        RETURN;
    END IF;
    --
    -- Translate the permission name
    -- to a numeric permission id
    --
    SELECT INTO n_perm
        id
    FROM
        permission.perm_list
    WHERE
        code = perm_code;
    --
    IF NOT FOUND THEN
        RETURN;               -- No such permission
    END IF;
    --
    -- Find the highest-level org unit (i.e. the minimum depth)
    -- to which the permission is applied for this user
    --
    -- This query is modified from the one in permission.usr_perms().
    --
    SELECT INTO n_min_depth
        min( depth )
    FROM    (
        SELECT depth
          FROM permission.usr_perm_map upm
         WHERE upm.usr = user_id
           AND (upm.perm = n_perm OR upm.perm = -1)
                    UNION
        SELECT  gpm.depth
          FROM  permission.grp_perm_map gpm
          WHERE (gpm.perm = n_perm OR gpm.perm = -1)
            AND gpm.grp IN (
               SELECT   (permission.grp_ancestors(
                    (SELECT profile FROM actor.usr WHERE id = user_id)
                )).id
            )
                    UNION
        SELECT  p.depth
          FROM  permission.grp_perm_map p
          WHERE (p.perm = n_perm OR p.perm = -1)
            AND p.grp IN (
                SELECT (permission.grp_ancestors(m.grp)).id
                FROM   permission.usr_grp_map m
                WHERE  m.usr = user_id
            )
    ) AS x;
    --
    IF NOT FOUND THEN
        RETURN;                -- No such permission for this user
    END IF;
    --
    -- Identify the org units to which the user is assigned.  Note that
    -- we pay no attention to the home_ou column in actor.usr.
    --
    FOR n_work_ou IN
        SELECT
            work_ou
        FROM
            permission.usr_work_ou_map
        WHERE
            usr = user_id
    LOOP            -- For each org unit to which the user is assigned
        --
        -- Determine the level of the org unit by a lookup in actor.org_unit_type.
        -- We take it on faith that this depth agrees with the actual hierarchy
        -- defined in actor.org_unit.
        --
        SELECT INTO n_depth
            type.depth
        FROM
            actor.org_unit_type type
                INNER JOIN actor.org_unit ou
                    ON ( ou.ou_type = type.id )
        WHERE
            ou.id = n_work_ou;
        --
        IF NOT FOUND THEN
            CONTINUE;        -- Maybe raise exception?
        END IF;
        --
        -- Compare the depth of the work org unit to the
        -- minimum depth, and branch accordingly
        --
        IF n_depth = n_min_depth THEN
            --
            -- The org unit is at the right depth, so return it.
            --
            RETURN NEXT n_work_ou;
        ELSIF n_depth > n_min_depth THEN
            --
            -- Traverse the org unit tree toward the root,
            -- until you reach the minimum depth determined above
            --
            n_curr_depth := n_depth;
            n_curr_ou := n_work_ou;
            WHILE n_curr_depth > n_min_depth LOOP
                SELECT INTO n_curr_ou
                    parent_ou
                FROM
                    actor.org_unit
                WHERE
                    id = n_curr_ou;
                --
                IF FOUND THEN
                    n_curr_depth := n_curr_depth - 1;
                ELSE
                    --
                    -- This can happen only if the hierarchy defined in
                    -- actor.org_unit is corrupted, or out of sync with
                    -- the depths defined in actor.org_unit_type.
                    -- Maybe we should raise an exception here, instead
                    -- of silently ignoring the problem.
                    --
                    n_curr_ou = NULL;
                    EXIT;
                END IF;
            END LOOP;
            --
            IF n_curr_ou IS NOT NULL THEN
                RETURN NEXT n_curr_ou;
            END IF;
        ELSE
            --
            -- The permission applies only at a depth greater than the work org unit.
            -- Use connectby() to find all dependent org units at the specified depth.
            --
            FOR n_curr_ou IN
                SELECT ou::INTEGER
                FROM connectby(
                        'actor.org_unit',         -- table name
                        'id',                     -- key column
                        'parent_ou',              -- recursive foreign key
                        n_work_ou::TEXT,          -- id of starting point
                        (n_min_depth - n_depth)   -- max depth to search, relative
                    )                             --   to starting point
                    AS t(
                        ou text,            -- dependent org unit
                        parent_ou text,     -- (ignore)
                        level int           -- depth relative to starting point
                    )
                WHERE
                    level = n_min_depth - n_depth
            LOOP
                RETURN NEXT n_curr_ou;
            END LOOP;
        END IF;
        --
    END LOOP;
    --
    RETURN;
    --
END;
$$ LANGUAGE 'plpgsql';

COMMIT;

