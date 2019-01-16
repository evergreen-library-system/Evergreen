--Upgrade Script for 3.1.8 to 3.1.9
\set eg_version '''3.1.9'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.1.9', :eg_version);
COMMIT;
