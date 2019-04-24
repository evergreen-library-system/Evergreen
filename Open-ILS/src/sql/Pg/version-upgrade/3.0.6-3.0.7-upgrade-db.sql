--Upgrade Script for 3.0.6 to 3.0.7
\set eg_version '''3.0.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.0.7', :eg_version);
COMMIT;
