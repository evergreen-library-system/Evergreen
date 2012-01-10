BEGIN;

SELECT evergreen.upgrade_deps_block_check('0667', :eg_version);

ALTER TABLE config.standing_penalty ADD staff_alert BOOL NOT NULL DEFAULT FALSE;

-- 20 is ALERT_NOTE
-- for backwards compat, set all blocking penalties to alerts
UPDATE config.standing_penalty SET staff_alert = TRUE 
    WHERE id = 20 OR block_list IS NOT NULL;

COMMIT;
