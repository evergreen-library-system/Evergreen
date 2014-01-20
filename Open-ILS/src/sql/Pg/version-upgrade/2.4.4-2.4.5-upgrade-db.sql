--Upgrade Script for 2.4.3 to 2.4.5
\set eg_version '''2.4.5'''

INSERT INTO config.upgrade_log (version, applied_to) VALUES ('2.4.5', :eg_version);

