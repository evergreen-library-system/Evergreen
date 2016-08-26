--Upgrade Script for 2.10.5 to 2.10.6
\set eg_version '''2.10.6'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.10.6', :eg_version);
COMMIT;
