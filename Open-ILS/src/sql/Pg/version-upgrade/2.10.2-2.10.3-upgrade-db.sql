--Upgrade Script for 2.10.2 to 2.10.3
\set eg_version '''2.10.3'''
BEGIN;

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.10.3', :eg_version);

COMMIT;
