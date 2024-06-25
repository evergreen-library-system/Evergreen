--Upgrade Script for 3.10.4 to 3.10.5
\set eg_version '''3.10.5'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.10.5', :eg_version);
COMMIT;
