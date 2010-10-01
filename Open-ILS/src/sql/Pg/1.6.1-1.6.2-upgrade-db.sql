BEGIN;

-- Start picking up call number label prefixes and suffixes
-- from asset.copy_location
ALTER TABLE asset.copy_location ADD COLUMN label_prefix TEXT;
ALTER TABLE asset.copy_location ADD COLUMN label_suffix TEXT;

-- Push due dates to 23:59:59 on insert OR update
DROP TRIGGER push_due_date_tgr ON action.circulation;
CREATE TRIGGER push_due_date_tgr BEFORE INSERT OR UPDATE ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.push_circ_due_time();

COMMIT;
