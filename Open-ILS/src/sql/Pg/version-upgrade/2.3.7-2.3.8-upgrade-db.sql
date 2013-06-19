--Upgrade Script for 2.3.6 to 2.3.7
\set eg_version '''2.3.8'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.3.8', :eg_version);
COMMIT;
