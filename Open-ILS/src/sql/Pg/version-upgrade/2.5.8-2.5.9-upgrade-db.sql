--Upgrade Script for 2.5.8 to 2.5.9
\set eg_version '''2.5.9'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.5.9', :eg_version);
COMMIT;
