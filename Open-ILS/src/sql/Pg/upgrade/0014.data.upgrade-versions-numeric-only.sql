BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0014');

-- Changing the rules retroactively:
-- versions should be numeric only

UPDATE config.upgrade_log set version = '0001' where version = '0001.data.config.org_unit_setting_type.sql';
UPDATE config.upgrade_log set version = '0002' where version = '0002.schema.hold-index-on-unfilled_hold_list.sql';
UPDATE config.upgrade_log set version = '0003' where version = '0003.schema.hold-loop-counting.sql';
UPDATE config.upgrade_log set version = '0004' where version = '0004.data.org-setting-precat-circ-lib.sql';
UPDATE config.upgrade_log set version = '0005' where version = '0005.data.org-setting-max-claims-return-count.sql';
UPDATE config.upgrade_log set version = '0006' where version = '0006.data.override-max-claims-returned-perm.sql';
UPDATE config.upgrade_log set version = '0007' where version = '0007.data.org-setting-checkout-auto-renew-age.sql';
UPDATE config.upgrade_log set version = '0008' where version = '0008.data.org-setting-lib-supports-behind-desk-holds.sql';
UPDATE config.upgrade_log set version = '0009' where version = '0009.data.action-trigger-hold-cancel-hook.sql';
UPDATE config.upgrade_log set version = '0010' where version = '0010.schema.asset-copy-dummy-isbn.sql';
UPDATE config.upgrade_log set version = '0011' where version = '0011.data.org-setting-no-autoprint.sql';
UPDATE config.upgrade_log set version = '0012' where version = '0012.schema.circ-parent-circ.sql';
UPDATE config.upgrade_log set version = '0013' where version = '0013.schema.circ-checkin-ws-and-scan-time.sql';

COMMIT;
