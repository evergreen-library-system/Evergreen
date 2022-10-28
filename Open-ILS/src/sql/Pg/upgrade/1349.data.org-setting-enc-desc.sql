BEGIN;

SELECT evergreen.upgrade_deps_block_check('1349', :eg_version);

UPDATE config.org_unit_setting_type
    SET label = 'Rollover encumbrances only',
        description = 'Rollover encumbrances only when doing fiscal year end.  This makes money left in the old fund disappear, modeling its return to some outside entity.'
    WHERE name = 'acq.fund.allow_rollover_without_money'
    AND label = 'Allow funds to be rolled over without bringing the money along'
    AND description = 'Allow funds to be rolled over without bringing the money along.  This makes money left in the old fund disappear, modeling its return to some outside entity.';

COMMIT;
