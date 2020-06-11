--Upgrade Script for 3.3.6 to 3.3.7
\set eg_version '''3.3.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.3.7', :eg_version);
COMMIT;
