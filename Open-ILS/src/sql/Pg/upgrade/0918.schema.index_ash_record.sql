-- index authority.simple_heading.record so that reingesting
-- authority records does not require a sequential scan of ash
BEGIN;

SELECT evergreen.upgrade_deps_block_check('0918', :eg_version);

CREATE INDEX authority_simple_heading_record_idx ON authority.simple_heading (record);

COMMIT;
