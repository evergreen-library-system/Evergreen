--Upgrade Script for 3.16.4 to 3.16.5
\set eg_version '''3.16.5'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.16.5', :eg_version);
COMMIT;
