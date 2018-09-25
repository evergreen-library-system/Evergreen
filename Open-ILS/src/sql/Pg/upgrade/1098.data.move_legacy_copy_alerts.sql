BEGIN;

SELECT evergreen.upgrade_deps_block_check('1098', :eg_version);

\qecho Copying copy alert messages to normal checkout copy alerts...
INSERT INTO asset.copy_alert (alert_type, copy, note, create_staff)
SELECT 1, id, alert_message, 1
FROM asset.copy
WHERE alert_message IS NOT NULL
AND   alert_message <> '';

\qecho Copying copy alert messages to normal checkin copy alerts...
INSERT INTO asset.copy_alert (alert_type, copy, note, create_staff)
SELECT 2, id, alert_message, 1
FROM asset.copy
WHERE alert_message IS NOT NULL
AND   alert_message <> '';

\qecho Clearing legacy copy alert field; this may take a while
UPDATE asset.copy SET alert_message = NULL
WHERE alert_message IS NOT NULL;

COMMIT;
