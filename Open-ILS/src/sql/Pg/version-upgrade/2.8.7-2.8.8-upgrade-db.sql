--Upgrade Script for 2.8.7 to 2.8.8
\set eg_version '''2.8.8'''
BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.8.8', :eg_version);

COMMIT;
