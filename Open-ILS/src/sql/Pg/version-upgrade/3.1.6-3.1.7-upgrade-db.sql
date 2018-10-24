--Upgrade Script for 3.1.6 to 3.1.7
\set eg_version '''3.1.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.1.7', :eg_version);
COMMIT;
