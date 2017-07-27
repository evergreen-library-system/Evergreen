--Upgrade Script for 2.11.6 to 2.11.7
\set eg_version '''2.11.7'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.11.7', :eg_version);
COMMIT;
