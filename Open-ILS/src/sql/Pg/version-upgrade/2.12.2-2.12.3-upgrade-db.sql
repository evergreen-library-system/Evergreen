--Upgrade Script for 2.12-2a to 2.12.3
\set eg_version '''2.12.3'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.12.3', :eg_version);
COMMIT;
