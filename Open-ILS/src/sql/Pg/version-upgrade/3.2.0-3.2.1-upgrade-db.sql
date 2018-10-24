--Upgrade Script for 3.2.0 to 3.2.1
\set eg_version '''3.2.1'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.2.1', :eg_version);
COMMIT;
