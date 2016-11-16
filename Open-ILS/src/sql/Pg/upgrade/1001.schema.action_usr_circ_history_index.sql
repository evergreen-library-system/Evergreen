BEGIN;

SELECT evergreen.upgrade_deps_block_check('1001', :eg_version); -- stompro/gmcharlt

CREATE INDEX action_usr_circ_history_usr_idx ON action.usr_circ_history ( usr );

COMMIT;
