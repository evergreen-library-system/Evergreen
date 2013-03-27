BEGIN;

SELECT evergreen.upgrade_deps_block_check('0785', :eg_version);

DROP INDEX actor.prox_adj_once_idx;

CREATE UNIQUE INDEX prox_adj_once_idx ON actor.org_unit_proximity_adjustment (
    COALESCE(item_circ_lib, -1),
    COALESCE(item_owning_lib, -1),
    COALESCE(copy_location, -1),
    COALESCE(hold_pickup_lib, -1),
    COALESCE(hold_request_lib, -1),
    COALESCE(circ_mod, ''),
    pos
);

COMMIT;
