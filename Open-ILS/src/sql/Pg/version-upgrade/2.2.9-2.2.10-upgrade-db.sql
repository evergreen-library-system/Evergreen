--Upgrade Script for 2.2.9 to 2.2.10 (no changes this version)
\set eg_version '''2.2.10'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.2.10', :eg_version);
COMMIT;
