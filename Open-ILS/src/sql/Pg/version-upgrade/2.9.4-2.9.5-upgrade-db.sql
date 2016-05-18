--Upgrade Script for 2.9.4 to 2.9.5
\set eg_version '''2.9.5'''

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.9.5', :eg_version);

