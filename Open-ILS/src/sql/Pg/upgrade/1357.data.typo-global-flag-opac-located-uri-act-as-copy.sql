BEGIN;

SELECT evergreen.upgrade_deps_block_check('1357', :eg_version);

UPDATE config.global_flag
SET label = 'When enabled, Located URIs will provide visibility behavior identical to copies.'
WHERE name = 'opac.located_uri.act_as_copy'
  AND label =
      'When enabled, Located URIs will provide visiblity behavior identical to copies.';

COMMIT;
