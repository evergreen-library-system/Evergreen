-- Correct the description of the org unit setting to match its use.

BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0076'); -- senator

DELETE FROM config.org_unit_setting_type WHERE name = 'ui.circ.patron_display_timeout_interval';

INSERT INTO config.org_unit_setting_type
    (name, label, description, datatype) VALUES
    ('ui.general.idle_timeout', 'GUI: Idle timeout', 'If you want staff client windows to be minimized after a certain amount of system idle time, set this to the number of seconds of idle time that you want to allow before minimizing (requires staff client restart).', 'integer');

COMMIT;
