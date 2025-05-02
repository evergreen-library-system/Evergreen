BEGIN;

SELECT evergreen.upgrade_deps_block_check('1461', :eg_version);

-- for searching e.g. "111-111-1111"
CREATE INDEX actor_usr_setting_phone_values_idx
    ON actor.usr_setting (evergreen.lowercase(value))
    WHERE name IN ('opac.default_phone', 'opac.default_sms_notify');

-- for searching e.g. "1111111111"
CREATE INDEX actor_usr_setting_phone_values_numeric_idx
    ON actor.usr_setting (evergreen.lowercase(REGEXP_REPLACE(value, '[^0-9]', '', 'g')))
    WHERE name IN ('opac.default_phone', 'opac.default_sms_notify');

COMMIT;
