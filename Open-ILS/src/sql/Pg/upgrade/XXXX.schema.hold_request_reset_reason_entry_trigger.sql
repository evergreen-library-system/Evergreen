BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

ALTER TABLE action.hold_request_reset_reason_entry DROP CONSTRAINT hold_request_reset_reason_entry_previous_copy_fkey;

CREATE TRIGGER action_hold_request_reset_reason_entry_previous_copy_trig
    AFTER INSERT OR UPDATE ON action.hold_request_reset_reason_entry
    FOR EACH ROW EXECUTE FUNCTION fake_fkey_tgr('previous_copy');

COMMIT;
