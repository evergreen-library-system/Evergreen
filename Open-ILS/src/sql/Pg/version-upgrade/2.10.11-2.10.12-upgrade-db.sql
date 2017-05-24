--Upgrade Script for 2.10.11 to 2.10.12
\set eg_version '''2.10.12'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.10.12', :eg_version);
COMMIT;
