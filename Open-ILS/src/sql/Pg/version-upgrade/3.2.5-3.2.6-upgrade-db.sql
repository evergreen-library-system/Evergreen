--Upgrade Script for 3.2.5 to 3.2.6
\set eg_version '''3.2.6'''
BEGIN;
INSERT INTO config.upgrade_log (version, applied_to) VALUES ('3.2.6', :eg_version);
COMMIT;
-- No transaction needed. This can be run on a live, production server.
SELECT evergreen.upgrade_deps_block_check('1161', :eg_version); -- jboyer/stompro/gmcharlt

CREATE INDEX CONCURRENTLY atev_template_output ON action_trigger.event (template_output);
CREATE INDEX CONCURRENTLY atev_async_output ON action_trigger.event (async_output);
CREATE INDEX CONCURRENTLY atev_error_output ON action_trigger.event (error_output);
