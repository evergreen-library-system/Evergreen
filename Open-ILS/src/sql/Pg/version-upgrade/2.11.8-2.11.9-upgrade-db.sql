--Upgrade Script for 2.11.8 to 2.11.9
\set eg_version '''2.11.9'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.11.9', :eg_version);
COMMIT;
