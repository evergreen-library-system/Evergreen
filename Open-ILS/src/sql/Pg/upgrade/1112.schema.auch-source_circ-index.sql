BEGIN;

SELECT evergreen.upgrade_deps_block_check('1112', :eg_version);

-- Add an index to action.usr_circ_history (source_circ) to speed up aging circs and purging accounts

CREATE INDEX action_usr_circ_history_source_circ_idx 
  ON action.usr_circ_history
  USING btree
  (source_circ);

COMMIT;
