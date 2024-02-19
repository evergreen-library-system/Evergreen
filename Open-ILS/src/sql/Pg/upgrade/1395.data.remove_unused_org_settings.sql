BEGIN;

SELECT evergreen.upgrade_deps_block_check('1395', :eg_version);

DELETE FROM actor.org_unit_setting WHERE name IN (
    'opac.did_you_mean.low_result_threshold',
    'opac.did_you_mean.max_suggestions',
    'search.symspell.keyboard_distance.weight',
    'search.symspell.min_suggestion_use_threshold',
    'search.symspell.pg_trgm.weight',
    'search.symspell.soundex.weight'
);

DELETE FROM config.org_unit_setting_type WHERE name IN (
    'opac.did_you_mean.low_result_threshold',
    'opac.did_you_mean.max_suggestions',
    'search.symspell.keyboard_distance.weight',
    'search.symspell.min_suggestion_use_threshold',
    'search.symspell.pg_trgm.weight',
    'search.symspell.soundex.weight'
);

DELETE FROM config.org_unit_setting_type_log WHERE field_name IN (
    'opac.did_you_mean.low_result_threshold',
    'opac.did_you_mean.max_suggestions',
    'search.symspell.keyboard_distance.weight',
    'search.symspell.min_suggestion_use_threshold',
    'search.symspell.pg_trgm.weight',
    'search.symspell.soundex.weight'
);

COMMIT;
