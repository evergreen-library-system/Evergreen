BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE INDEX atev_template_output ON action_trigger.event (template_output);
CREATE INDEX atev_async_output ON action_trigger.event (async_output);
CREATE INDEX atev_error_output ON action_trigger.event (error_output);

COMMIT;
