BEGIN;

SELECT evergreen.upgrade_deps_block_check('1005', :eg_version);

CREATE INDEX action_aged_circulation_parent_circ_idx ON action.aged_circulation (parent_circ);

COMMIT;
