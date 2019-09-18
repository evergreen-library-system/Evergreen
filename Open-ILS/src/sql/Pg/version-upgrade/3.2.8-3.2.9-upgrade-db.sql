--Upgrade Script for 3.2.8 to 3.2.9
\set eg_version '''3.2.9'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.2.9', :eg_version);
COMMIT;
