-- Already exists as far back as 1.6.0.0, so don't use this in version upgrades

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0073');

CREATE OR REPLACE FUNCTION action.push_circ_due_time () RETURNS TRIGGER AS $$
BEGIN
    IF (EXTRACT(EPOCH FROM NEW.duration)::INT % EXTRACT(EPOCH FROM '1 day'::INTERVAL)::INT) = 0 THEN
        NEW.due_date = (NEW.due_date::DATE + '1 day'::INTERVAL - '1 second'::INTERVAL)::TIMESTAMPTZ;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE PLPGSQL;

CREATE TRIGGER push_due_date_tgr BEFORE INSERT ON action.circulation FOR EACH ROW EXECUTE PROCEDURE action.push_circ_due_time();

COMMIT;

