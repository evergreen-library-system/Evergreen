BEGIN;

SELECT evergreen.upgrade_deps_block_check('1538', :eg_version);

UPDATE config.global_flag
SET label = oils_i18n_gettext('history.hold.retention_age_canceled_1', 'Historical Hold Retention Age - Canceled (Untargeted expiration)', 'cgf', 'label')
WHERE
name='history.hold.retention_age_canceled_1'
AND label != oils_i18n_gettext('history.hold.retention_age_canceled_1', 'Historical Hold Retention Age - Canceled (Untargeted expiration)', 'cgf', 'label')
;

COMMIT;
