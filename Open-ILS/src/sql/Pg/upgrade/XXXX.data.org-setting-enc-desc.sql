BEGIN;

UPDATE config.org_unit_setting_type
    SET label = 'Rollover encumbrances only'
    SET description = 'Rollover encumbrances only when doing fiscal year end.  This makes money left in the old fund disappear, modeling its return to some outside entity.'
    WHERE name= 'acq.fund.allow_rollover_without_money';

COMMIT;