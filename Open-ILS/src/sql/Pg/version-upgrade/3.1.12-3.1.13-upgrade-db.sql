--Upgrade Script for 3.1.12 to 3.1.13
\set eg_version '''3.1.13'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.1.13', :eg_version);
COMMIT;
