BEGIN;

SELECT evergreen.upgrade_deps_block_check('xxxx', :eg_version);

ALTER TABLE asset.call_number_suffix ADD COLUMN deleted BOOLEAN DEFAULT FALSE;
ALTER TABLE asset.call_number_prefix ADD COLUMN deleted BOOLEAN DEFAULT FALSE;

CREATE RULE protect_acn_suffix_delete AS ON DELETE TO asset.call_number_suffix DO INSTEAD UPDATE asset.call_number_suffix SET deleted = TRUE WHERE OLD.id = asset.call_number_suffix.id;
CREATE RULE protect_acn_prefix_delete AS ON DELETE TO asset.call_number_prefix DO INSTEAD UPDATE asset.call_number_prefix SET deleted = TRUE WHERE OLD.id = asset.call_number_prefix.id;

COMMIT;
