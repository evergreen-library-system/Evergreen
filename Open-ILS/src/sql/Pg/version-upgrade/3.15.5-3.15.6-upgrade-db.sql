--Upgrade Script for 3.15.5 to 3.15.6
\set eg_version '''3.15.6'''
BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.15.6', :eg_version);

COMMIT;
