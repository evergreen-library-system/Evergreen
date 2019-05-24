--Upgrade Script for 3.1.11 to 3.1.12
\set eg_version '''3.1.12'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.1.12', :eg_version);
COMMIT;
