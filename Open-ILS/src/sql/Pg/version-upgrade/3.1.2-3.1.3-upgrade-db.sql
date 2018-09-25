--Upgrade Script for 3.1.2 to 3.1.3
\set eg_version '''3.1.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.1.3', :eg_version);

SELECT evergreen.upgrade_deps_block_check('1112', :eg_version);

-- Add an index to action.usr_circ_history (source_circ) to speed up aging circs and purging accounts

CREATE INDEX action_usr_circ_history_source_circ_idx 
  ON action.usr_circ_history
  USING btree
  (source_circ);

COMMIT;
