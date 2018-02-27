--Upgrade Script for 2.12.9 to 2.12.10
\set eg_version '''2.12.10'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.12.10', :eg_version);
COMMIT;
