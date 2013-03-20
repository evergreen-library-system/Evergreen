--Upgrade Script for 2.2.5 to 2.2.6
\set eg_version '''2.2.6'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.2.6', :eg_version);
COMMIT;
