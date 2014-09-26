BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

CREATE INDEX m_b_voider_idx ON money.billing (voider);

COMMIT;
