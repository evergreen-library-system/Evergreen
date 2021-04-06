BEGIN;

--SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

DROP INDEX authority.authority_full_rec_value_index;
CREATE INDEX authority_full_rec_value_index ON authority.full_rec (SUBSTRING(value FOR 1024));

DROP INDEX authority.authority_full_rec_value_tpo_index;
CREATE INDEX authority_full_rec_value_tpo_index ON authority.full_rec (SUBSTRING(value FOR 1024) text_pattern_ops);


COMMIT;
