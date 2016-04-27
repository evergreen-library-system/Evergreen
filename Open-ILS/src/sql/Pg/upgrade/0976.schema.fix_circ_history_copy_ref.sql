BEGIN;

SELECT evergreen.upgrade_deps_block_check('0976', :eg_version);

ALTER TABLE action.usr_circ_history 
    DROP CONSTRAINT IF EXISTS usr_circ_history_target_copy_fkey;

CREATE TRIGGER action_usr_circ_history_target_copy_trig 
    AFTER INSERT OR UPDATE ON action.usr_circ_history 
    FOR EACH ROW EXECUTE PROCEDURE evergreen.fake_fkey_tgr('target_copy');

COMMIT;

