--Upgrade Script for 3.1.14 to 3.1.15
\set eg_version '''3.1.15'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.1.15', :eg_version);
COMMIT;
