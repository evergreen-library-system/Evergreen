BEGIN;

SELECT evergreen.upgrade_deps_block_check('0899', :eg_version);

ALTER FUNCTION asset.label_normalizer_generic(TEXT) IMMUTABLE;
ALTER FUNCTION asset.label_normalizer_dewey(TEXT) IMMUTABLE;
ALTER FUNCTION asset.label_normalizer_lc(TEXT) IMMUTABLE;

COMMIT;
