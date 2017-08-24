--Upgrade Script for 2.11.7 to 2.11.8
\set eg_version '''2.11.8'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.11.8', :eg_version);
COMMIT;
