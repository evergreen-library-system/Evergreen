--Upgrade Script for 2.5.1 to 2.5.2
\set eg_version '''2.5.2'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.5.2', :eg_version);

SELECT evergreen.upgrade_deps_block_check('0849', :eg_version);

UPDATE config.global_flag
    SET label = 'Circ: Use original circulation library on desk renewal instead of the workstation library'
    WHERE name = 'circ.desk_renewal.use_original_circ_lib';



SELECT evergreen.upgrade_deps_block_check('0850', :eg_version);

CREATE OR REPLACE FUNCTION unapi.mra ( obj_id BIGINT, format TEXT,  ename TEXT, includes TEXT[], org TEXT, depth INT DEFAULT NULL, slimit HSTORE DEFAULT NULL, soffset HSTORE DEFAULT NULL, include_xmlns BOOL DEFAULT TRUE ) RETURNS XML AS $F$
        SELECT  XMLELEMENT(
                    name attributes,
                    XMLATTRIBUTES(
                        CASE WHEN $9 THEN 'http://open-ils.org/spec/indexing/v1' ELSE NULL END AS xmlns,
                        'tag:open-ils.org:U2@mra/' || mra.id AS id,
                        'tag:open-ils.org:U2@bre/' || mra.id AS record
                    ),
                    (SELECT XMLAGG(foo.y)
                      FROM (SELECT XMLELEMENT(
                                name field,
                                XMLATTRIBUTES(
                                    key AS name,
                                    cvm.value AS "coded-value",
                                    cvm.id AS "cvmid",
                                    rad.filter,
                                    rad.sorter
                                ),
                                x.value
                            )
                           FROM EACH(mra.attrs) AS x
                                JOIN config.record_attr_definition rad ON (x.key = rad.name)
                                LEFT JOIN config.coded_value_map cvm ON (cvm.ctype = x.key AND code = x.value)
                        )foo(y)
                    )
                )
          FROM  metabib.record_attr mra
          WHERE mra.id = $1;
$F$ LANGUAGE SQL STABLE;


SELECT evergreen.upgrade_deps_block_check('0852', :eg_version);

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
            LEFT JOIN actor.org_unit_ancestors_distance(acl.owning_lib) acl_ol ON (acl_ol.id = adj.copy_location)
            LEFT JOIN actor.org_unit_ancestors_distance(ahr.pickup_lib) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(ahr.request_lib) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
      WHERE (adj.circ_mod IS NULL OR adj.circ_mod = acp.circ_modifier) AND
            (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
            (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
            (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
            (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
            (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
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
                (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
                (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
                (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
                (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
                (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
                NOT absolute_adjustment AND
                COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
    LOOP
        baseline_prox := baseline_prox + aoupa.prox_adjustment;
    END LOOP;

    RETURN baseline_prox;
END;
$f$ LANGUAGE PLPGSQL;


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
            LEFT JOIN actor.org_unit_ancestors_distance(acl.owning_lib) acl_ol ON (acl_ol.id = adj.copy_location)
            LEFT JOIN actor.org_unit_ancestors_distance(ahr.pickup_lib) ahr_pl ON (ahr_pl.id = adj.hold_pickup_lib)
            LEFT JOIN actor.org_unit_ancestors_distance(ahr.request_lib) ahr_rl ON (ahr_rl.id = adj.hold_request_lib)
      WHERE (adj.circ_mod IS NULL OR adj.circ_mod = acp.circ_modifier) AND
            (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
            (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
            (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
            (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
            (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
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
                (adj.item_circ_lib IS NULL OR adj.item_circ_lib = acp_cl.id) AND
                (adj.item_owning_lib IS NULL OR adj.item_owning_lib = acn_ol.id) AND
                (adj.copy_location IS NULL OR adj.copy_location = acl_ol.id) AND
                (adj.hold_pickup_lib IS NULL OR adj.hold_pickup_lib = ahr_pl.id) AND
                (adj.hold_request_lib IS NULL OR adj.hold_request_lib = ahr_rl.id) AND
                NOT absolute_adjustment AND
                COALESCE(acp_cl.id, acn_ol.id, acl_ol.id, ahr_pl.id, ahr_rl.id) IS NOT NULL
    LOOP
        baseline_prox := baseline_prox + aoupa.prox_adjustment;
    END LOOP;

    RETURN baseline_prox;
END;
$f$ LANGUAGE PLPGSQL;

COMMIT;
