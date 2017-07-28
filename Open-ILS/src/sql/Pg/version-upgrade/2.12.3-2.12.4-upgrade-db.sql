--Upgrade Script for 2.12.3 to 2.12.4
\set eg_version '''2.12.4'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.12.4', :eg_version);
COMMIT;
