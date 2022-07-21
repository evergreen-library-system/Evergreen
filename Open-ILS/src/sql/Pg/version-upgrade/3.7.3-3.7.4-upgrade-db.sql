--Upgrade Script for 3.7.3 to 3.7.4
\set eg_version '''3.7.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.7.4', :eg_version);
COMMIT;
