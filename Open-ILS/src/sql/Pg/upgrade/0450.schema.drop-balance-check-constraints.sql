BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0450'); -- gmc

-- libraries can choose to overcommit funds
ALTER TABLE acq.fund DROP CONSTRAINT balance_warning_percent_limit;
ALTER TABLE acq.fund DROP CONSTRAINT balance_stop_percent_limit;

COMMIT;
