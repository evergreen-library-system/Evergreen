BEGIN;

-- check whether patch can be applied
SELECT evergreen.upgrade_deps_block_check('0845', :eg_version);

ALTER FUNCTION metabib.browse_pivot (integer[], text) STABLE;
ALTER FUNCTION metabib.browse_bib_pivot (integer[], text) STABLE;
ALTER FUNCTION metabib.browse_authority_pivot (integer[], text) STABLE;
ALTER FUNCTION metabib.browse_authority_refs_pivot (integer[], text) STABLE;

COMMIT;
