--Upgrade Script for 2.12.10 to 2.12.11
\set eg_version '''2.12.11'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.12.11', :eg_version);
COMMIT;
