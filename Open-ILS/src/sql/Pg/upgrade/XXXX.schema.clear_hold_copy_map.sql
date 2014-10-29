BEGIN;

CREATE OR REPLACE FUNCTION action.hold_request_clear_map () RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM action.hold_copy_map WHERE hold = NEW.id;
  RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER hold_request_clear_map_tgr
    AFTER UPDATE ON action.hold_request
    FOR EACH ROW
    WHEN (
        (NEW.cancel_time IS NOT NULL AND OLD.cancel_time IS NULL)
        OR (NEW.capture_time IS NOT NULL AND OLD.capture_time IS NULL)
    )
    EXECUTE PROCEDURE action.hold_request_clear_map();

COMMIT;

