--Upgrade Script for 3.11.5 to 3.11.6
\set eg_version '''3.11.6'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.11.6', :eg_version);
COMMIT;
