BEGIN;

SELECT evergreen.upgrade_deps_block_check('XXXX', :eg_version);

INSERT into config.org_unit_setting_type
( name, grp, label, description, datatype )
SELECT  'opac.did_you_mean.max_suggestions',
        'opac',
        'Maximum number of spelling suggestions that may be offered',
        'If set to -1, provide "best" suggestion if mispelled; if set higher than 0, the maximum suggestions that can be provided; if set to 0, disable suggestions.',
        'integer'
  WHERE NOT EXISTS (SELECT 1 FROM config.org_unit_setting_type WHERE name = 'opac.did_you_mean.max_suggestions');

COMMIT;

