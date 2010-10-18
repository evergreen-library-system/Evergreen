
BEGIN;

INSERT INTO config.upgrade_log (version) VALUES ('0437'); -- miker

DROP INDEX asset.asset_call_number_label_sortkey;
CREATE INDEX asset_call_number_label_sortkey ON asset.call_number(cast(label_sortkey as bytea));

COMMIT;
