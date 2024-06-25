--Upgrade Script for 3.12.3 to 3.12.4
\set eg_version '''3.12.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.12.4', :eg_version);
COMMIT;
