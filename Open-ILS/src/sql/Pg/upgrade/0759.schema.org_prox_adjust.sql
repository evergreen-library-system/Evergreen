BEGIN;

SELECT evergreen.upgrade_deps_block_check('0759', :eg_version);

CREATE TABLE actor.org_unit_proximity_adjustment (
    id                  SERIAL   PRIMARY KEY,
    item_circ_lib       INT         REFERENCES actor.org_unit (id),
    item_owning_lib     INT         REFERENCES actor.org_unit (id),
    copy_location       INT         REFERENCES asset.copy_location (id),
    hold_pickup_lib     INT         REFERENCES actor.org_unit (id),
    hold_request_lib    INT         REFERENCES actor.org_unit (id),
    pos                 INT         NOT NULL DEFAULT 0,
    absolute_adjustment BOOL        NOT NULL DEFAULT FALSE,
    prox_adjustment     NUMERIC,
    circ_mod            TEXT,       -- REFERENCES config.circ_modifier (code),
    CONSTRAINT prox_adj_criterium CHECK (COALESCE(item_circ_lib::TEXT,item_owning_lib::TEXT,copy_location::TEXT,hold_pickup_lib::TEXT,hold_request_lib::TEXT,circ_mod) IS NOT NULL)
);
CREATE UNIQUE INDEX prox_adj_once_idx ON actor.org_unit_proximity_adjustment (item_circ_lib,item_owning_lib,copy_location,hold_pickup_lib,hold_request_lib,circ_mod);
CREATE INDEX prox_adj_circ_lib_idx ON actor.org_unit_proximity_adjustment (item_circ_lib);
CREATE INDEX prox_adj_owning_lib_idx ON actor.org_unit_proximity_adjustment (item_owning_lib);
CREATE INDEX prox_adj_copy_location_idx ON actor.org_unit_proximity_adjustment (copy_location);
CREATE INDEX prox_adj_pickup_lib_idx ON actor.org_unit_proximity_adjustment (hold_pickup_lib);
CREATE INDEX prox_adj_request_lib_idx ON actor.org_unit_proximity_adjustment (hold_request_lib);
CREATE INDEX prox_adj_circ_mod_idx ON actor.org_unit_proximity_adjustment (circ_mod);

CREATE OR REPLACE FUNCTION actor.org_unit_ancestors_distance( INT ) RETURNS TABLE (id INT, distance INT) AS $$
    WITH RECURSIVE org_unit_ancestors_distance(id, distance) AS (
            SELECT $1, 0
        UNION
            SELECT ou.parent_ou, ouad.distance+1
            FROM actor.org_unit ou JOIN org_unit_ancestors_distance ouad ON (ou.id = ouad.id)
            WHERE ou.parent_ou IS NOT NULL
    )
    SELECT * FROM org_unit_ancestors_distance;
$$ LANGUAGE SQL STABLE ROWS 1;

CREATE OR REPLACE FUNCTION action.hold_copy_calculated_proximity(
    ahr_id INT,
    acp_id BIGINT,
    copy_context_ou INT DEFAULT NULL
    -- TODO maybe? hold_context_ou INT DEFAULT NULL.  This would optionally
    -- support an "ahprox" measurement: adjust prox between copy circ lib and
    -- hold request lib, but I'm unsure whether to use this theoretical
    -- argument only in the baseline calculation or later in the other
    -- queries in this function.
) RETURNS NUMERIC AS $f$
DECLARE
    aoupa           actor.org_unit_proximity_adjustment%ROWTYPE;
    ahr             action.hold_request%ROWTYPE;
    acp             asset.copy%ROWTYPE;
    acn             asset.call_number%ROWTYPE;
    acl             asset.copy_location%ROWTYPE;
    baseline_prox   NUMERIC;

    icl_list        INT[];
    iol_list        INT[];
    isl_list        INT[];
    hpl_list        INT[];
    hrl_list        INT[];

BEGIN

    SELECT * INTO ahr FROM action.hold_request WHERE id = ahr_id;
    SELECT * INTO acp FROM asset.copy WHERE id = acp_id;
    SELECT * INTO acn FROM asset.call_number WHERE id = acp.call_number;
    SELECT * INTO acl FROM asset.copy_location WHERE id = acp.location;

    IF copy_context_ou IS NULL THEN
        copy_context_ou := acp.circ_lib;
    END IF;

    -- First, gather the baseline proximity of "here" to pickup lib
    SELECT prox INTO baseline_prox FROM actor.org_unit_proximity WHERE from_org = copy_context_ou AND to_org = ahr.pickup_lib;

    -- Find any absolute adjustments, and set the baseline prox to that
    SELECT  adj.* INTO aoupa
      FROM  actor.org_unit_proximity_adjustment adj
            LEFT JOIN actor.org_unit_ancestors_distance(copy_context_ou) acp_cl ON (acp_cl.id = adj.item_circ_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(acn.owning_lib) acn_ol ON (acn_ol.id = adj.item_owning_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(acl.owning_lib) acl_ol ON (acn_ol.id = adj.copy_location)
            LEFT JOIN actor.org_unit_ancestors_distance(ahr.pickup_lib) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(ahr.request_lib) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
      WHERE (adj.circ_mod IS NULL OR adj.circ_mod = acp.circ_modifier) AND
        absolute_adjustment AND
        COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
      ORDER BY
            COALESCE(acp_cl.distance,999)
                + COALESCE(acn_ol.distance,999)
                + COALESCE(acl_ol.distance,999)
                + COALESCE(ahr_pl.distance,999)
                + COALESCE(ahr_rl.distance,999),
            adj.pos
      LIMIT 1;

    IF FOUND THEN
        baseline_prox := aoupa.prox_adjustment;
    END IF;

    -- Now find any relative adjustments, and change the baseline prox based on them
    FOR aoupa IN
        SELECT  adj.* 
          FROM  actor.org_unit_proximity_adjustment adj
                LEFT JOIN actor.org_unit_ancestors_distance(copy_context_ou) acp_cl ON (acp_cl.id = adj.item_circ_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(acn.owning_lib) acn_ol ON (acn_ol.id = adj.item_owning_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(acl.owning_lib) acl_ol ON (acn_ol.id = adj.copy_location)
                LEFT JOIN actor.org_unit_ancestors_distance(ahr.pickup_lib) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
                LEFT JOIN actor.org_unit_ancestors_distance(ahr.request_lib) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
          WHERE (adj.circ_mod IS NULL OR adj.circ_mod = acp.circ_modifier) AND
            NOT absolute_adjustment AND
            COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
    LOOP
        baseline_prox := baseline_prox + aoupa.prox_adjustment;
    END LOOP;

    RETURN baseline_prox;
END;
$f$ LANGUAGE PLPGSQL;

ALTER TABLE actor.org_unit_proximity_adjustment
    ADD CONSTRAINT actor_org_unit_proximity_adjustment_circ_mod_fkey
    FOREIGN KEY (circ_mod) REFERENCES config.circ_modifier (code)
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE action.hold_copy_map ADD COLUMN proximity NUMERIC;

COMMIT;
